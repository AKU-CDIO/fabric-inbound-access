import os
import unittest
from unittest.mock import patch

from fabricpy.client import (
    TOKEN_REFRESH_BUFFER_SECONDS,
    _build_sql_connection_string,
    _format_sql_table_name,
    _is_usable,
    _needs_refresh,
    _normalize_access_token,
    _pack_odbc_access_token,
    _now,
    _try_env_var_token,
)


class TokenAuthTests(unittest.TestCase):
    def test_normalizes_raw_and_bearer_jwt_tokens(self):
        token = "eyJ" + ("a" * 20)

        self.assertEqual(_normalize_access_token(token, required=True), token)
        self.assertEqual(_normalize_access_token(f"Bearer {token}", required=True), token)
        self.assertIsNone(_normalize_access_token(""))

    def test_rejects_non_jwt_explicit_token(self):
        with self.assertRaisesRegex(ValueError, "Access token must be a JWT"):
            _normalize_access_token("not-a-jwt", required=True)

    def test_cached_tokens_refresh_before_expiry(self):
        fresh = {"access_token": "fresh", "expires_at": _now() + TOKEN_REFRESH_BUFFER_SECONDS + 60}
        near_expiry = {"access_token": "soon", "expires_at": _now() + 120}
        expired = {"access_token": "old", "expires_at": _now() - 1}

        self.assertFalse(_needs_refresh(fresh))
        self.assertTrue(_needs_refresh(near_expiry))
        self.assertTrue(_is_usable(near_expiry))
        self.assertFalse(_is_usable(expired))

    def test_reads_delegated_token_env_alias(self):
        token = "eyJ" + ("b" * 20)
        env = {
            "FABRIC_DELEGATED_ACCESS_TOKEN": f"Bearer {token}",
        }

        with patch.dict(os.environ, env, clear=True):
            self.assertEqual(_try_env_var_token(), token)


    def test_packs_odbc_access_token_as_utf16_with_length_prefix(self):
        packed = _pack_odbc_access_token("abc")
        self.assertEqual(packed[:4], (6).to_bytes(4, "little"))
        self.assertEqual(packed[4:], "abc".encode("utf-16-le"))

    def test_builds_sql_connection_string(self):
        conn_str = _build_sql_connection_string(
            "example.fabric.microsoft.com",
            "db",
            "ODBC Driver 18 for SQL Server",
        )
        self.assertIn("Driver={ODBC Driver 18 for SQL Server};", conn_str)
        self.assertIn("Server=tcp:example.fabric.microsoft.com,1433;", conn_str)
        self.assertIn("Database=db;", conn_str)

    def test_formats_schema_qualified_sql_table_names(self):
        self.assertEqual(_format_sql_table_name("people"), "[dbo].[people]")
        self.assertEqual(_format_sql_table_name("dbo.people"), "[dbo].[people]")
        self.assertEqual(_format_sql_table_name("db]o.people"), "[db]]o].[people]")


if __name__ == "__main__":
    unittest.main()
