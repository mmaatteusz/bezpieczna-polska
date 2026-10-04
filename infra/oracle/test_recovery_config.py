import base64
import importlib.util
import json
from pathlib import Path
import unittest

from cryptography.exceptions import InvalidTag

spec = importlib.util.spec_from_file_location("recovery", Path(__file__).with_name("recovery-config.py"))
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)


class RecoveryTest(unittest.TestCase):
    def test_password_and_tamper_protection(self):
        password = "test-only recovery password"
        envelope = recovery.seal(b"test-only secret", password)
        self.assertEqual(recovery.unseal(envelope, password), b"test-only secret")
        with self.assertRaises(InvalidTag):
            recovery.unseal(envelope, "wrong password")
        data = json.loads(envelope)
        ciphertext = bytearray(base64.b64decode(data["ciphertext"]))
        ciphertext[0] ^= 1
        data["ciphertext"] = base64.b64encode(ciphertext).decode()
        with self.assertRaises(InvalidTag):
            recovery.unseal(json.dumps(data), password)
        self.assertNotEqual(envelope, recovery.seal(b"test-only secret", password))


if __name__ == "__main__":
    unittest.main()
