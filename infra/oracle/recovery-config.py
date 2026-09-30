#!/usr/bin/env python3
"""Password-encrypted host configuration; never extract into the live host."""
import base64
from datetime import datetime, timezone
import getpass
import io
import importlib.util
import json
import os
from pathlib import Path
import sys
import tarfile

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

AAD = b"bezpieczna-polska-recovery-v1"
FILES = (
    "/etc/bezpieczna-polska/backend.env",
    "/etc/bezpieczna-polska/database-password",
    "/etc/bezpieczna-polska/backup-object-storage.json",
    "/etc/bezpieczna-polska/backup.env",
    "/opt/bezpieczna-polska/release.env",
)


def derive(password, salt):
    return Scrypt(salt=salt, length=32, n=2**17, r=8, p=1).derive(password.encode())


def seal(payload, password):
    salt, nonce = os.urandom(16), os.urandom(12)
    ciphertext = AESGCM(derive(password, salt)).encrypt(nonce, payload, AAD)
    return json.dumps({"format": "bp-recovery-v1", "salt": base64.b64encode(salt).decode(),
                       "nonce": base64.b64encode(nonce).decode(),
                       "ciphertext": base64.b64encode(ciphertext).decode()}).encode()


def unseal(envelope, password):
    data = json.loads(envelope)
    if data["format"] != "bp-recovery-v1":
        raise ValueError("Unsupported format")
    salt, nonce, ciphertext = [base64.b64decode(data[k], validate=True)
                               for k in ("salt", "nonce", "ciphertext")]
    if len(salt) != 16 or len(nonce) != 12:
        raise ValueError("Invalid parameters")
    return AESGCM(derive(password, salt)).decrypt(nonce, ciphertext, AAD)


def inspect_payload(payload):
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz") as archive:
        members = archive.getmembers()
        if {m.name for m in members} != {p.lstrip("/") for p in FILES}:
            raise ValueError("Unexpected archive members")
        for member in members:
            if not member.isfile() or member.size > 10 * 1024 * 1024:
                raise ValueError("Invalid archive member")
            if len(archive.extractfile(member).read()) != member.size:
                raise ValueError("Incomplete archive")


def main():
    if os.geteuid() != 0 or len(sys.argv) < 2:
        raise ValueError("Run as root with create or verify PATH")
    password = getpass.getpass("Haslo pakietu odzyskiwania: ")
    if sys.argv[1] == "verify" and len(sys.argv) == 3:
        source = Path(sys.argv[2])
        if source.stat().st_size > 25 * 1024 * 1024:
            raise ValueError("Package too large")
        inspect_payload(unseal(source.read_bytes(), password))
        print("CONFIG_RECOVERY_PASS files=5 authenticated=true")
        return
    if sys.argv[1:] != ["create"]:
        raise ValueError("Unknown operation")
    if len(password) < 16 or password != getpass.getpass("Powtorz haslo: "):
        raise ValueError("Passwords differ or too short")
    memory = io.BytesIO()
    with tarfile.open(fileobj=memory, mode="w:gz") as archive:
        for name in FILES:
            path = Path(name)
            if path.is_symlink() or not path.is_file() or path.stat().st_uid != 0:
                raise ValueError("Invalid configuration file")
            mode = path.stat().st_mode
            if mode & 0o022 or (mode & 0o077 and name != FILES[-1]) or path.stat().st_size > 10 * 1024 * 1024:
                raise ValueError("Insecure or oversized configuration file")
            archive.add(name, arcname=name.lstrip("/"), recursive=False)
    envelope = seal(memory.getvalue(), password)
    inspect_payload(unseal(envelope, password))
    os.umask(0o077)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = Path("/var/backups/bezpieczna-polska") / ("host-recovery-" + stamp + ".enc")
    with output.open("xb") as target:
        target.write(envelope)
    spec = importlib.util.spec_from_file_location("bp_upload", Path(__file__).with_name("upload-backup.py"))
    uploader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(uploader)
    import oci
    config = json.loads(Path(FILES[2]).read_text())
    signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
    client = oci.object_storage.ObjectStorageClient(
        {"region": config["region"]}, signer=signer,
        retry_strategy=oci.retry.DEFAULT_RETRY_STRATEGY, timeout=(10, 120))
    uploader.upload(client, config["namespace"], config["bucket"], "recovery/" + output.name, output)
    print("CONFIG_RECOVERY_UPLOAD_PASS object=recovery/" + output.name)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("CONFIG_RECOVERY_FAIL type=" + type(error).__name__, file=sys.stderr)
        sys.exit(1)
