#!/usr/bin/env python3
"""Append-only OCI Object Storage backup upload using instance principals."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys


def checksums(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("Backup must be a regular file")
    if stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise ValueError("Backup file permissions must be owner-only")
    sha, md5 = hashlib.sha256(), hashlib.md5(usedforsecurity=False)
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            sha.update(chunk)
            md5.update(chunk)
    return sha.hexdigest(), base64.b64encode(md5.digest()).decode(), path.stat().st_size


def upload(client, namespace, bucket, object_name, path):
    sha, md5, size = checksums(path)
    try:
        with path.open("rb") as source:
            client.put_object(namespace, bucket, object_name, source,
                              content_length=size, content_md5=md5,
                              opc_meta={"sha256": sha}, if_none_match="*")
    except Exception as error:
        # A retry after a successful PUT can encounter the now-existing object.
        # Accept it only if HEAD proves the exact same contents; never overwrite.
        if getattr(error, "status", None) != 412:
            raise
    headers = client.head_object(namespace, bucket, object_name).headers
    if (int(headers["content-length"]) != size or
            headers.get("opc-meta-sha256") != sha or headers.get("content-md5") != md5):
        raise ValueError("Remote backup verification failed")


def main():
    if os.geteuid() != 0 or len(sys.argv) != 4:
        raise ValueError("Run as root with dump, checksum and metadata paths")
    paths = [Path(value) for value in sys.argv[1:]]
    dump = paths[0]
    if not re.fullmatch(r"bezpieczna-polska-\d{8}T\d{6}Z\.dump", dump.name):
        raise ValueError("Unexpected backup filename")
    if paths[1] != Path(str(dump) + ".sha256") or paths[2] != Path(str(dump) + ".json"):
        raise ValueError("Unexpected backup sidecars")
    for path in paths:
        if path.parent.resolve() != Path("/var/backups/bezpieczna-polska"):
            raise ValueError("Backup outside the private backup directory")
        checksums(path)
    if paths[1].read_text().split()[0] != checksums(dump)[0]:
        raise ValueError("Local backup checksum mismatch")
    json.loads(paths[2].read_text())
    config = json.loads(Path("/etc/bezpieczna-polska/backup-object-storage.json").read_text())
    prefix = config.get("prefix", "backups/")
    if not re.fullmatch(r"[A-Za-z0-9_-]+/", prefix):
        raise ValueError("Invalid backup object prefix")
    import oci
    signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
    client = oci.object_storage.ObjectStorageClient(
        {"region": config["region"]}, signer=signer,
        retry_strategy=oci.retry.DEFAULT_RETRY_STRATEGY,
        timeout=(10, 120))
    for path in paths:
        upload(client, config["namespace"], config["bucket"], prefix + path.name, path)
    print("OFF_VM_UPLOAD_PASS files=3 overwrite=false")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # SDK errors can contain URLs/headers; report only a safe category/status.
        print("OFF_VM_UPLOAD_FAIL type=" + type(error).__name__ +
              " status=" + str(getattr(error, "status", "unknown")), file=sys.stderr)
        sys.exit(1)
