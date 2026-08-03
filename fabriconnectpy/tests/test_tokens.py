import os
import sys
import types
import unittest
from unittest.mock import patch

from fabricpy.client import (
    TOKEN_REFRESH_BUFFER_SECONDS,
    _build_sql_connection_string,
    _get_keyvault_credential,
    _get_service_principal_from_keyvault,
    _KEYVAULT_CREDENTIAL_CACHE,
    _ensure_read_only_sql,
    _format_sql_table_name,
    _is_usable,
    _needs_refresh,
    _normalize_access_token,
    _normalize_keyvault_auth_method,
    _normalize_sql_auth,
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

    def test_sql_auth_requires_sp_vault(self):
        self.assertEqual(_normalize_sql_auth(), "sp_vault")
        self.assertEqual(_normalize_sql_auth("sp_vault"), "sp_vault")
        self.assertEqual(_normalize_sql_auth("sp"), "sp_vault")
        self.assertEqual(_normalize_sql_auth("service-principal"), "sp_vault")
        with self.assertRaisesRegex(ValueError, "auth must be 'sp_vault'"):
            _normalize_sql_auth("browser")

    def test_keyvault_auth_method_defaults_to_browser(self):
        with patch.dict(os.environ, {"FABRIC_KEYVAULT_AUTH_METHOD": "device_code"}):
            self.assertEqual(_normalize_keyvault_auth_method(), "browser")
        self.assertEqual(_normalize_keyvault_auth_method("device-code"), "device_code")
        self.assertEqual(_normalize_keyvault_auth_method("browser"), "browser")
        self.assertEqual(_normalize_keyvault_auth_method("auto"), "auto")
        with self.assertRaisesRegex(ValueError, "keyvault_auth_method"):
            _normalize_keyvault_auth_method("bad")

    def test_default_keyvault_credential_creates_browser_credential(self):
        calls = []

        class FakeDeviceCodeCredential:
            def __init__(self, **kwargs):
                calls.append(("device", kwargs))

        class FakeInteractiveBrowserCredential:
            def __init__(self, **kwargs):
                calls.append(("browser", kwargs))

        fake_identity = types.ModuleType("azure.identity")
        fake_identity.DeviceCodeCredential = FakeDeviceCodeCredential
        fake_identity.InteractiveBrowserCredential = FakeInteractiveBrowserCredential

        _KEYVAULT_CREDENTIAL_CACHE.clear()
        with patch.dict(sys.modules, {"azure.identity": fake_identity}):
            cred = _get_keyvault_credential("tenant-1")

        self.assertIsInstance(cred, FakeInteractiveBrowserCredential)
        self.assertEqual([kind for kind, _ in calls], ["browser"])

    def test_service_principal_secret_lookup_is_not_cached(self):
        class FakeCredential:
            pass

        class FakeSecret:
            def __init__(self, value):
                self.value = value

        class FakeSecretClient:
            calls = []

            def __init__(self, vault_url, credential):
                self.vault_url = vault_url
                self.credential = credential

            def get_secret(self, name):
                FakeSecretClient.calls.append(name)
                return FakeSecret(f"value-for-{name}")

        fake_secrets = types.ModuleType("azure.keyvault.secrets")
        fake_secrets.SecretClient = FakeSecretClient
        sql_cfg = {
            "vault_url": "https://vault.example",
            "keyvault_tenant": "tenant-1",
            "secret_names": {
                "tenant_id": "tenant-secret",
                "client_id": "client-secret",
                "client_secret": "password-secret",
            },
        }

        FakeSecretClient.calls.clear()
        with patch.dict(sys.modules, {"azure.keyvault.secrets": fake_secrets}):
            with patch("fabricpy.client._get_keyvault_credential", return_value=FakeCredential()):
                first = _get_service_principal_from_keyvault(sql_cfg)
                second = _get_service_principal_from_keyvault(sql_cfg)

        self.assertIsNot(first, second)
        self.assertEqual(first["client_secret"], "value-for-password-secret")
        self.assertEqual(
            FakeSecretClient.calls,
            [
                "tenant-secret", "client-secret", "password-secret",
                "tenant-secret", "client-secret", "password-secret",
            ],
        )

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
        self.assertIn("ApplicationIntent=ReadOnly;", conn_str)

    def test_formats_schema_qualified_sql_table_names(self):
        self.assertEqual(_format_sql_table_name("people"), "[dbo].[people]")
        self.assertEqual(_format_sql_table_name("dbo.people"), "[dbo].[people]")
        self.assertEqual(_format_sql_table_name("db]o.people"), "[db]]o].[people]")

    def test_read_only_sql_guard_allows_selects(self):
        _ensure_read_only_sql("SELECT COUNT(*) FROM dbo.people")
        _ensure_read_only_sql("-- comment\nWITH rows AS (SELECT 1 AS x) SELECT x FROM rows")

    def test_read_only_sql_guard_blocks_mutations(self):
        blocked = [
            "DELETE FROM dbo.people",
            "SELECT * INTO dbo.copy FROM dbo.people",
            "WITH rows AS (SELECT 1 AS x) UPDATE dbo.people SET x = 1",
            "EXEC dbo.refresh_data",
        ]
        for sql in blocked:
            with self.subTest(sql=sql):
                with self.assertRaisesRegex(ValueError, "read-only SELECT"):
                    _ensure_read_only_sql(sql)


if __name__ == "__main__":
    unittest.main()
