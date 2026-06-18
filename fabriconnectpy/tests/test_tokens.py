import os
import unittest
from unittest.mock import patch

from fabricpy.client import _normalize_access_token, _try_env_var_token


class TokenAuthTests(unittest.TestCase):
    def test_normalizes_raw_and_bearer_jwt_tokens(self):
        token = "eyJ" + ("a" * 20)

        self.assertEqual(_normalize_access_token(token, required=True), token)
        self.assertEqual(_normalize_access_token(f"Bearer {token}", required=True), token)
        self.assertIsNone(_normalize_access_token(""))

    def test_rejects_non_jwt_explicit_token(self):
        with self.assertRaisesRegex(ValueError, "Access token must be a JWT"):
            _normalize_access_token("not-a-jwt", required=True)

    def test_reads_delegated_token_env_alias(self):
        token = "eyJ" + ("b" * 20)
        env = {
            "FABRIC_DELEGATED_ACCESS_TOKEN": f"Bearer {token}",
        }

        with patch.dict(os.environ, env, clear=True):
            self.assertEqual(_try_env_var_token(), token)


if __name__ == "__main__":
    unittest.main()
