import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location("upload_backup", Path(__file__).with_name("upload-backup.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FakeClient:
    def __init__(self):
        self.headers = {}
        self.conflict = False
        self.corrupt = False

    def put_object(self, namespace, bucket, name, source, **kwargs):
        assert kwargs["if_none_match"] == "*"
        if self.conflict:
            error = RuntimeError("already exists")
            error.status = 412
            raise error
        self.headers = {"content-length": str(len(source.read())),
                        "content-md5": kwargs["content_md5"],
                        "opc-meta-sha256": kwargs["opc_meta"]["sha256"]}

    def head_object(self, *args):
        headers = dict(self.headers)
        if self.corrupt:
            headers["opc-meta-sha256"] = "different"
        return SimpleNamespace(headers=headers)


class UploadTests(unittest.TestCase):
    def test_uploaded_bytes_and_idempotent_retry_are_verified(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "backup.dump"
            path.write_bytes(b"private backup")
            path.chmod(0o600)
            client = FakeClient()
            module.upload(client, "namespace", "bucket", "backups/name", path)
            client.conflict = True
            module.upload(client, "namespace", "bucket", "backups/name", path)
            client.corrupt = True
            with self.assertRaises(ValueError):
                module.upload(client, "namespace", "bucket", "backups/name", path)

    def test_publicly_readable_file_and_symlink_are_rejected(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "backup.dump"
            path.write_bytes(b"private backup")
            path.chmod(0o644)
            with self.assertRaises(ValueError):
                module.checksums(path)
            path.chmod(0o600)
            link = Path(directory) / "link"
            link.symlink_to(path)
            with self.assertRaises(ValueError):
                module.checksums(link)


if __name__ == "__main__":
    unittest.main()
