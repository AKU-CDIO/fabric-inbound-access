import subprocess
import json
import urllib.request
import urllib.error
import os
import sys
import platform
import webbrowser
import time
import urllib.parse
import struct

_CONFIG = None

def _load_config():
    global _CONFIG
    if _CONFIG is not None:
        return _CONFIG
    path = os.path.join(os.path.dirname(__file__), "config.json")
    with open(path) as f:
        _CONFIG = json.load(f)
    return _CONFIG

AZ_CMD = "az.cmd"
STORAGE_RESOURCE = "https://storage.azure.com"
FABRIC_API_RESOURCE = "https://api.fabric.microsoft.com"
FABRIC_SQL_SCOPE = "https://database.windows.net/.default"
SQL_ACCESS_TOKEN_ATTR = 1256

_TOKEN_CACHE = {}
_KEYVAULT_CREDENTIAL_CACHE = {}
_SERVICE_PRINCIPAL_CACHE = {}
TOKEN_REFRESH_BUFFER_SECONDS = 300

def _now():
    return time.time()

def _is_usable(entry):
    return _now() < entry.get("expires_at", 0)

def _needs_refresh(entry):
    return _now() >= entry.get("expires_at", 0) - TOKEN_REFRESH_BUFFER_SECONDS

def _make_entry(access_token, refresh_token=None):
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "expires_at": _now() + 3300,
    }

def _normalize_access_token(token, *, required=False):
    if token is None:
        return None
    token = str(token).strip()
    if token.lower().startswith("bearer "):
        token = token[7:].strip()
    if not token:
        return None
    if not token.startswith("eyJ"):
        if required:
            raise ValueError(
                "Access token must be a JWT. Paste only the token value "
                "or 'Bearer <token>'."
            )
        return None
    return token

def _refresh_token(tenant, refresh_token, resource):
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "client_id": "1950a258-227b-4e31-a9cf-717495945fc2",
        "refresh_token": refresh_token,
        "scope": f"{resource}/.default offline_access",
    }).encode()
    req = urllib.request.Request(
        f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            tok = json.loads(resp.read().decode())
    except Exception:
        return None
    if "access_token" not in tok:
        return None
    return _make_entry(
        tok["access_token"],
        tok.get("refresh_token", refresh_token),
    )

def _try_env_var_token():
    for name in ("FABRIC_ACCESS_TOKEN", "FABRIC_DELEGATED_ACCESS_TOKEN", "AZURE_ACCESS_TOKEN"):
        token = _normalize_access_token(os.environ.get(name))
        if token:
            return token
    return None

def _try_local_token_file():
    candidates = []
    env_file = os.environ.get("FABRIC_ACCESS_TOKEN_FILE", "")
    if env_file:
        candidates.append(env_file)
    programdata = os.environ.get("PROGRAMDATA", "C:\\ProgramData")
    candidates.append(os.path.join(programdata, "UZIMA", "FabricTokenBroker", "fab_token.txt"))
    home = os.environ.get("HOME") or os.environ.get("USERPROFILE", "")
    if home:
        candidates.append(os.path.join(home, "fab_token.txt"))
    seen = set()
    for path in candidates:
        if not path or path in seen:
            continue
        seen.add(path)
        try:
            with open(path, "r") as f:
                raw = f.read().strip()
            token = _normalize_access_token(raw)
            if token:
                return token
        except (OSError, IOError):
            continue
    return None

def _try_webhook_token(tenant, resource):
    webhook_url = os.environ.get("FABRIC_WEBHOOK_URL") or _load_config().get("automation", {}).get("webhook_url")
    if not webhook_url:
        return None

    email = os.environ.get("FABRIC_RESEARCHER_EMAIL")
    if not email:
        return None
    if email.endswith("@aku.edu"):
        return None

    cfg = _load_config().get("automation", {})
    sub = cfg.get("subscription_id")
    rg = cfg.get("resource_group")
    aa = cfg.get("account_name")
    if not all([sub, rg, aa]):
        print("Auth service error: missing automation config for job polling.", file=sys.stderr)
        return None

    try:
        body = json.dumps({"action": "get_token", "email": email}).encode()
        req = urllib.request.Request(
            webhook_url, data=body,
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            job_data = json.loads(resp.read().decode())
        job_ids = job_data.get("JobIds")
        if not job_ids:
            print("Auth service error: no JobIds in webhook response.", file=sys.stderr)
            return None
        job_id = job_ids[0]

        import time
        deadline = time.time() + 120
        while time.time() < deadline:
            time.sleep(10)
            result = subprocess.run(
                f'az rest --method GET --uri "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Automation/automationAccounts/{aa}/jobs/{job_id}?api-version=2023-11-01" --query "properties.status" -o tsv',
                capture_output=True, text=True, timeout=15, shell=True
            )
            status = result.stdout.strip() if result.returncode == 0 else ""
            if status == "Completed":
                break
            if status in ("Failed", "Stopped", "Suspended"):
                print(f"Auth service error: job {status}.", file=sys.stderr)
                return None

        out_result = subprocess.run(
            f'az rest --method GET --uri "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Automation/automationAccounts/{aa}/jobs/{job_id}/output?api-version=2023-11-01" -o json 2>nul',
            capture_output=True, text=True, timeout=15, shell=True
        )
        output_text = out_result.stdout or ""
        marker_start = "---BEGIN-RESPONSE---"
        marker_end = "---END-RESPONSE---"
        start_idx = output_text.find(marker_start)
        if start_idx == -1:
            print("Auth service error: unexpected response format.", file=sys.stderr)
            return None
        start_idx += len(marker_start)
        end_idx = output_text.find(marker_end, start_idx)
        if end_idx == -1:
            print("Auth service error: unexpected response format.", file=sys.stderr)
            return None
        json_str = output_text[start_idx:end_idx].strip()
        data = json.loads(json_str)
        if data.get("status") == "success":
            token = data["data"]["access_token"]
            if token:
                print(f"Authenticated as {email}", file=sys.stderr)
                return token
        print(f"Access denied: {data.get('message', 'Unknown error')}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Auth service error: {e}", file=sys.stderr)
        return None

def _try_azure_cli(tenant, resource, az_cmd):
    result = subprocess.run(
        f"{az_cmd} account get-access-token "
        f"--resource {resource} "
        f"--tenant {tenant} "
        f"--query accessToken -o tsv",
        capture_output=True, text=True, timeout=30, shell=True
    )
    if result.returncode != 0:
        return None
    return _normalize_access_token(result.stdout)


def _get_sql_access_config(database=None, server=None, vault_url=None, keyvault_tenant=None):
    cfg = _load_config()
    sql_cfg = cfg.get("sql_access", {})
    return {
        "database": (
            database
            or os.environ.get("FABRIC_SQL_DATABASE")
            or sql_cfg.get("default_database")
            or cfg.get("lakehouse_name")
        ),
        "server": (
            server
            or os.environ.get("FABRIC_SQL_SERVER")
            or sql_cfg.get("server")
        ),
        "vault_url": (
            vault_url
            or os.environ.get("FABRIC_KEYVAULT_URL")
            or sql_cfg.get("key_vault_url")
        ),
        "keyvault_tenant": (
            keyvault_tenant
            or os.environ.get("FABRIC_KEYVAULT_TENANT")
            or sql_cfg.get("key_vault_tenant")
        ),
        "secret_names": {
            "tenant_id": sql_cfg.get("tenant_secret", "fabric-sp-tenant-id"),
            "client_id": sql_cfg.get("client_id_secret", "fabric-sp-client-id"),
            "client_secret": sql_cfg.get("client_secret_secret", "fabric-sp-client-secret"),
        },
    }

def _require_sql_config(sql_cfg):
    missing = [name for name in ("database", "server", "vault_url", "keyvault_tenant")
               if not sql_cfg.get(name)]
    if missing:
        raise ValueError(
            "Missing Fabric SQL access configuration: "
            + ", ".join(missing)
            + ". Set it in fabricpy/config.json or environment variables."
        )

def _normalize_keyvault_auth_method(auth_method=None):
    value = auth_method or "browser"
    value = str(value).strip().lower().replace("-", "_")
    aliases = {
        "device": "device_code",
        "devicecode": "device_code",
        "device_code": "device_code",
        "browser": "browser",
        "interactive_browser": "browser",
        "auto": "auto",
    }
    if value not in aliases:
        raise ValueError(
            "keyvault_auth_method must be 'device_code', 'browser', or 'auto'."
        )
    return aliases[value]


def _print_device_code(*args, **kwargs):
    if len(args) == 1 and hasattr(args[0], "verification_uri"):
        verification_uri = args[0].verification_uri
        user_code = args[0].user_code
    else:
        verification_uri = kwargs.get("verification_uri") or (
            args[0] if len(args) > 0 else "https://login.microsoft.com/device"
        )
        user_code = kwargs.get("user_code") or (
            args[1] if len(args) > 1 else "<code not supplied>"
        )
    print("\nSIGN IN REQUIRED", flush=True)
    print(f"Open: {verification_uri}", flush=True)
    print(f"Code: {user_code}\n", flush=True)


def _get_keyvault_credential(keyvault_tenant, auth_method=None):
    try:
        from azure.identity import DeviceCodeCredential, InteractiveBrowserCredential
    except ImportError as exc:
        raise ImportError(
            "Service-principal SQL access requires azure-identity. "
            "Install with: pip install azure-identity"
        ) from exc

    method = _normalize_keyvault_auth_method(auth_method)
    cache_key = (keyvault_tenant, method)
    cached = _KEYVAULT_CREDENTIAL_CACHE.get(cache_key)
    if cached is not None:
        return cached

    if method == "device_code":
        credential = DeviceCodeCredential(
            tenant_id=keyvault_tenant,
            prompt_callback=_print_device_code,
        )
        _KEYVAULT_CREDENTIAL_CACHE[cache_key] = credential
        return credential

    browser_credential = InteractiveBrowserCredential(
        tenant_id=keyvault_tenant,
        timeout=60,
    )
    if method == "browser":
        _KEYVAULT_CREDENTIAL_CACHE[cache_key] = browser_credential
        return browser_credential

    try:
        browser_credential.get_token("https://vault.azure.net/.default")
        _KEYVAULT_CREDENTIAL_CACHE[cache_key] = browser_credential
        return browser_credential
    except Exception as exc:
        print(
            "Browser login did not complete; using device-code login. "
            f"Reason: {type(exc).__name__}: {exc}",
            flush=True,
        )

    credential = DeviceCodeCredential(
        tenant_id=keyvault_tenant,
        prompt_callback=_print_device_code,
    )
    _KEYVAULT_CREDENTIAL_CACHE[cache_key] = credential
    return credential


def _get_service_principal_from_keyvault(sql_cfg, auth_method=None):
    try:
        from azure.keyvault.secrets import SecretClient
    except ImportError as exc:
        raise ImportError(
            "Service-principal SQL access requires azure-keyvault-secrets. "
            "Install with: pip install azure-keyvault-secrets"
        ) from exc

    credential = _get_keyvault_credential(sql_cfg["keyvault_tenant"], auth_method)
    names = sql_cfg["secret_names"]
    cache_key = (
        sql_cfg["vault_url"],
        sql_cfg["keyvault_tenant"],
        names["tenant_id"],
        names["client_id"],
        names["client_secret"],
    )
    cached = _SERVICE_PRINCIPAL_CACHE.get(cache_key)
    if cached is not None:
        return cached

    client = SecretClient(vault_url=sql_cfg["vault_url"], credential=credential)
    sp = {
        "tenant_id": client.get_secret(names["tenant_id"]).value,
        "client_id": client.get_secret(names["client_id"]).value,
        "client_secret": client.get_secret(names["client_secret"]).value,
    }
    _SERVICE_PRINCIPAL_CACHE[cache_key] = sp
    return sp


def _get_fabric_sql_token(sp):
    try:
        from azure.identity import ClientSecretCredential
    except ImportError as exc:
        raise ImportError(
            "Service-principal SQL access requires azure-identity. "
            "Install with: pip install azure-identity"
        ) from exc

    return ClientSecretCredential(
        tenant_id=sp["tenant_id"],
        client_id=sp["client_id"],
        client_secret=sp["client_secret"],
    ).get_token(FABRIC_SQL_SCOPE).token

def _pack_odbc_access_token(token):
    token_bytes = token.encode("utf-16-le")
    return struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)

def _build_sql_connection_string(server, database, odbc_driver):
    return (
        f"Driver={{{odbc_driver}}};"
        f"Server=tcp:{server},1433;"
        f"Database={database};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
    )

def _quote_sql_identifier(identifier):
    if identifier is None:
        raise ValueError("SQL identifier cannot be None")
    return "[" + str(identifier).replace("]", "]]") + "]"

def _format_sql_table_name(table_name):
    parts = [p for p in str(table_name).split(".") if p]
    if len(parts) == 1:
        parts.insert(0, "dbo")
    if len(parts) != 2:
        raise ValueError("table_name must be 'table' or 'schema.table'")
    return ".".join(_quote_sql_identifier(part) for part in parts)

def connect_to_fabric_sql(database=None, server=None, vault_url=None,
                          keyvault_tenant=None, odbc_driver="ODBC Driver 18 for SQL Server",
                          timeout=30, keyvault_auth_method="browser"):
    """Connect to Fabric SQL using SP credentials stored in Azure Key Vault.

    Researchers authenticate interactively to the Key Vault tenant. The service
    principal secret is retrieved at runtime and exchanged for a Fabric SQL
    access token. No service-principal secret is written locally.
    """
    try:
        import pyodbc
    except ImportError as exc:
        raise ImportError(
            "Fabric SQL access requires pyodbc and Microsoft ODBC Driver 18. "
            "Install with: pip install pyodbc"
        ) from exc

    sql_cfg = _get_sql_access_config(database, server, vault_url, keyvault_tenant)
    _require_sql_config(sql_cfg)
    sp = _get_service_principal_from_keyvault(sql_cfg, keyvault_auth_method)
    token = _get_fabric_sql_token(sp)
    conn_str = _build_sql_connection_string(
        sql_cfg["server"], sql_cfg["database"], odbc_driver
    )
    return pyodbc.connect(
        conn_str,
        attrs_before={SQL_ACCESS_TOKEN_ATTR: _pack_odbc_access_token(token)},
        timeout=timeout,
    )

def list_sql_tables(conn):
    """List schema-qualified tables from a Fabric SQL pyodbc connection."""
    import pandas as pd
    df = pd.read_sql_query(
        "SELECT TABLE_SCHEMA, TABLE_NAME "
        "FROM INFORMATION_SCHEMA.TABLES "
        "ORDER BY TABLE_SCHEMA, TABLE_NAME",
        conn,
    )
    return [f"{row.TABLE_SCHEMA}.{row.TABLE_NAME}" for row in df.itertuples(index=False)]

def query_sql(conn, sql):
    """Run SQL against a Fabric SQL pyodbc connection and return a DataFrame."""
    import pandas as pd
    return pd.read_sql_query(sql, conn)

def read_sql_table(conn, table_name, columns=None, top=None):
    """Read a Fabric SQL table into a pandas DataFrame."""
    cols = "*"
    if columns is not None:
        cols = ", ".join(_quote_sql_identifier(col) for col in columns)
    top_clause = ""
    if top is not None:
        top_clause = f"TOP {int(top)} "
    sql = f"SELECT {top_clause}{cols} FROM {_format_sql_table_name(table_name)}"
    return query_sql(conn, sql)


def _try_msal_device_code(tenant, resource):
    import sys

    url_base = f"https://login.microsoftonline.com/{tenant}"
    client_id = "1950a258-227b-4e31-a9cf-717495945fc2"
    data = urllib.parse.urlencode({
        "client_id": client_id,
        "scope": f"{resource}/.default offline_access",
    }).encode()
    req = urllib.request.Request(
        f"{url_base}/oauth2/v2.0/devicecode",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            flow = json.loads(resp.read().decode())
    except Exception:
        return None
    if "user_code" not in flow:
        return None

    print("\n====================  SIGN IN REQUIRED  ====================", file=sys.stderr)
    print("To access the Fabric Lakehouse, sign in with your email.", file=sys.stderr)
    print("This supports MFA (e.g. Outlook / Microsoft Authenticator).\n", file=sys.stderr)
    print(f"  Opening browser to: {flow['verification_uri']}", file=sys.stderr)
    print(f"  Enter code: {flow['user_code']}", file=sys.stderr)
    print("============================================================\n", file=sys.stderr)
    try:
        webbrowser.open(flow["verification_uri"])
    except Exception:
        pass

    interval = int(flow.get("interval", 5))
    deadline = _now() + int(flow.get("expires_in", 900))
    token_url = f"{url_base}/oauth2/v2.0/token"

    while _now() < deadline:
        time.sleep(interval)
        token_data = urllib.parse.urlencode({
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "client_id": client_id,
            "device_code": flow["device_code"],
        }).encode()
        token_req = urllib.request.Request(
            token_url,
            data=token_data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        try:
            with urllib.request.urlopen(token_req, timeout=30) as resp:
                tok = json.loads(resp.read().decode())
        except urllib.error.HTTPError as exc:
            try:
                tok = json.loads(exc.read().decode())
            except Exception:
                return None
            err = tok.get("error")
            if err == "authorization_pending":
                continue
            if err == "slow_down":
                interval += 5
                continue
            if err == "expired_token":
                print("Device code expired. Run FabricLakehouse() again to retry.", file=sys.stderr)
                return None
            if err == "access_denied":
                print("Authentication cancelled.", file=sys.stderr)
                return None
            return None
        except Exception:
            return None

        if "access_token" in tok:
            print("Authentication successful.\n", file=sys.stderr)
            return {
                "access_token": tok["access_token"],
                "refresh_token": tok.get("refresh_token"),
            }

    print("Authentication timed out. Run FabricLakehouse() again to retry.", file=sys.stderr)
    return None

class FabricLakehouse:
    def __init__(self, workspace_guid=None, lakehouse_guid=None,
                 lakehouse=None, lakehouse_name=None,
                 fabric_tenant=None, token=None, az_cmd=None):
        cfg = _load_config()
        self.workspace_guid = workspace_guid or cfg["workspace_guid"]
        self.fabric_tenant = fabric_tenant or cfg["fabric_tenant"]
        self.az_cmd = az_cmd or AZ_CMD
        self._explicit_token = _normalize_access_token(token, required=True)

        # lakehouse is a shorthand alias for lakehouse_name
        if lakehouse_name is None and lakehouse is not None:
            lakehouse_name = lakehouse

        if lakehouse_name is not None:
            lakehouse_guid = cfg.get("shortcuts", {}).get(lakehouse_name)
            if lakehouse_guid is None:
                lakes = FabricLakehouse.list_lakehouses(
                    workspace_guid=self.workspace_guid,
                    fabric_tenant=self.fabric_tenant,
                    token=token,
                    az_cmd=self.az_cmd
                )
                for l in lakes:
                    if l["displayName"] == lakehouse_name:
                        lakehouse_guid = l["id"]
                        break
                else:
                    raise ValueError(
                        f"Lakehouse '{lakehouse_name}' not found. "
                        "Use FabricLakehouse.list_lakehouses() to see available names."
                    )

        self.lakehouse_guid = lakehouse_guid or cfg["lakehouse_guid"]

    def _get_token(self, resource=STORAGE_RESOURCE):
        cache_key = f"{self.fabric_tenant}:{resource}"
        entry = _TOKEN_CACHE.get(cache_key)

        if entry is not None:
            if not _needs_refresh(entry):
                return entry["access_token"]
            if entry.get("refresh_token"):
                refreshed = _refresh_token(
                    self.fabric_tenant, entry["refresh_token"], resource
                )
                if refreshed is not None:
                    _TOKEN_CACHE[cache_key] = refreshed
                    return refreshed["access_token"]
            if _is_usable(entry):
                return entry["access_token"]

        if self._explicit_token:
            _TOKEN_CACHE[cache_key] = _make_entry(self._explicit_token)
            return self._explicit_token

        local_file_token = _try_local_token_file()
        if local_file_token:
            _TOKEN_CACHE[cache_key] = _make_entry(local_file_token)
            return local_file_token

        env_token = _try_env_var_token()
        if env_token:
            _TOKEN_CACHE[cache_key] = _make_entry(env_token)
            return env_token

        webhook_token = _try_webhook_token(self.fabric_tenant, resource)
        if webhook_token:
            _TOKEN_CACHE[cache_key] = _make_entry(webhook_token)
            return webhook_token

        msal_result = _try_msal_device_code(self.fabric_tenant, resource)
        if msal_result is not None:
            entry = _make_entry(
                msal_result["access_token"], msal_result["refresh_token"]
            )
            _TOKEN_CACHE[cache_key] = entry
            return entry["access_token"]

        cli_result = _try_azure_cli(self.fabric_tenant, resource, self.az_cmd)
        if cli_result:
            _TOKEN_CACHE[cache_key] = _make_entry(cli_result)
            return cli_result

        raise RuntimeError(
            "No authentication method available.\n"
            "  Options:\n"
            f"    1. Pass token= to FabricLakehouse()\n"
            f"    2. Set FABRIC_ACCESS_TOKEN env var\n"
            f"    3. Run 'az login --tenant {self.fabric_tenant} --use-device-code'\n"
            f"    4. Install msal (pip install msal) for interactive pop-up login"
        )

    def list_tables(self):
        token = self._get_token(resource=STORAGE_RESOURCE)
        url = (
            f"https://onelake.dfs.fabric.microsoft.com/{self.workspace_guid}/"
            f"{self.lakehouse_guid}/Tables"
            f"?recursive=true&maxResults=1000&resource=filesystem"
        )
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json;charset=utf-8",
            "x-ms-version": "2024-08-04"
        }, method="GET")
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
        tables = set()
        for entry in data.get("paths", []):
            name = entry.get("name", "")
            if "/Tables/" not in name:
                continue
            after = name.split("/Tables/", 1)[1]
            table = after.split("/", 1)[0]
            if table and not table.startswith("_"):
                tables.add(table)
        return sorted(tables)

    def read_table(self, table_name, columns=None):
        """Read a Delta table as a pyarrow Table.

        Parameters
        ----------
        table_name : str
            Table name (e.g. ``"dbo.aku_survey_responses_2026"``).
        columns : list of str, optional
            Column names to select (predicate pushdown). Reduces
            network transfer for large tables.

        Returns
        -------
        pyarrow.Table
        """
        from deltalake import DeltaTable
        token = self._get_token(resource=STORAGE_RESOURCE)
        storage_options = {
            "bearer_token": token,
            "use_fabric_endpoint": "true"
        }
        table_path = table_name.replace(".", "/")
        path = (
            f"abfss://{self.workspace_guid}@onelake.dfs.fabric.microsoft.com/"
            f"{self.lakehouse_guid}/Tables/{table_path}"
        )
        dt = DeltaTable(path, storage_options=storage_options)
        kwargs = {}
        if columns is not None:
            kwargs["columns"] = columns
        return dt.to_pyarrow_table(**kwargs)

    def to_pandas(self, table_name, columns=None):
        """Read a Delta table as a pandas DataFrame.

        Parameters
        ----------
        table_name : str
        columns : list of str, optional
            Column names to select (predicate pushdown).

        Returns
        -------
        pandas.DataFrame
        """
        table = self.read_table(table_name, columns=columns)
        return table.to_pandas()

    def sql(self, query, table_columns=None):
        """Run a SQL query on Lakehouse tables using DuckDB.

        Table names are auto-extracted from FROM and JOIN clauses.
        Requires duckdb package.

        Parameters
        ----------
        query : str
            SQL query. Use table names directly, e.g.
            "SELECT * FROM dimdate"
        table_columns : dict of str -> list of str, optional
            Column pruning per table, e.g.
            ``{"tablename": ["col1", "col2"]}``.
            Unlisted tables fetch all columns. Reduces data transfer
            for large tables.

        Returns
        -------
        pandas.DataFrame
        """
        import duckdb
        import re
        con = duckdb.connect()
        tables = set()
        # Extract table names from FROM (handles comma-separated) and JOIN
        for kw in ("FROM", "JOIN"):
            for m in re.finditer(rf"\b{kw}\s+([\w\s,]+?)(?:\s+(?:AS\s+)?\w+\s*(?:ON|\s|$)|\s+(?:WHERE|GROUP|ORDER|HAVING|LIMIT)|$)", query, re.IGNORECASE):
                parts = re.split(r"\s*,\s*", m.group(1).strip())
                for part in parts:
                    tbl = part.split()[0].strip()
                    if tbl and tbl.upper() not in ("SELECT", "WHERE", "AND", "OR", "ON", "AS"):
                        tables.add(tbl)
        for tbl in tables:
            cols = table_columns.get(tbl) if table_columns else None
            df = self.to_pandas(tbl, columns=cols)
            con.register(tbl, df)
        result = con.execute(query)
        return result.fetchdf()

    @staticmethod
    def cross_query(connections, query, table_columns=None):
        """Run a SQL query across multiple Lakehouses.

        Parameters
        ----------
        connections : dict of str -> FabricLakehouse
            Named connections, e.g. ``{"uzima": lh1, "hcw": lh2}``.
            Use names as schema prefixes in the query, e.g.
            ``"SELECT ... FROM uzima.dimenrolledparticipants JOIN hcw.fitbitdailydata"``.
        query : str
            SQL query with schema-prefixed table names.
        table_columns : dict of str -> list of str, optional
            Column pruning per qualified table name, e.g.
            ``{"uzima.dimenrolledparticipants": ["col1", "col2"]}``.

        Returns
        -------
        pandas.DataFrame
        """
        import duckdb
        import re
        con = duckdb.connect()
        tables = set()
        for kw in ("FROM", "JOIN"):
            for m in re.finditer(rf"\b{kw}\s+([\w.]+)", query, re.IGNORECASE):
                tables.add(m.group(1))
        for tbl_ref in tables:
            if "." in tbl_ref:
                schema, tbl = tbl_ref.split(".", 1)
            else:
                schema = None
                tbl = tbl_ref
            if len(connections) > 1 and schema is None:
                raise ValueError(
                    f"Table '{tbl_ref}' is not schema-qualified. "
                    "Use schema.tablename syntax for cross-lakehouse queries."
                )
            lh = connections.get(schema) if schema else list(connections.values())[0]
            if lh is None:
                raise ValueError(
                    f"No connection named '{schema}'. Available: {list(connections.keys())}"
                )
            cols = (table_columns or {}).get(tbl_ref)
            df = lh.to_pandas(tbl, columns=cols)
            if schema:
                safe_name = f"__{schema}__{tbl}"
                con.register(safe_name, df)
                con.execute(f'CREATE SCHEMA IF NOT EXISTS "{schema}"')
                con.execute(f'CREATE OR REPLACE VIEW "{schema}"."{tbl}" AS SELECT * FROM "{safe_name}"')
            else:
                con.register(tbl, df)
        result = con.execute(query)
        return result.fetchdf()

    @staticmethod
    def _get_fabric_api_token(fabric_tenant=None, token=None, az_cmd=None):
        ft = fabric_tenant or _load_config()["fabric_tenant"]
        cache_key = f"{ft}:{FABRIC_API_RESOURCE}"
        entry = _TOKEN_CACHE.get(cache_key)

        if entry is not None:
            if not _needs_refresh(entry):
                return entry["access_token"]
            if entry.get("refresh_token"):
                refreshed = _refresh_token(ft, entry["refresh_token"], FABRIC_API_RESOURCE)
                if refreshed is not None:
                    _TOKEN_CACHE[cache_key] = refreshed
                    return refreshed["access_token"]
            if _is_usable(entry):
                return entry["access_token"]

        if token:
            explicit_token = _normalize_access_token(token, required=True)
            _TOKEN_CACHE[cache_key] = _make_entry(explicit_token)
            return explicit_token

        local_file_token = _try_local_token_file()
        if local_file_token:
            _TOKEN_CACHE[cache_key] = _make_entry(local_file_token)
            return local_file_token

        env_token = _try_env_var_token()
        if env_token:
            _TOKEN_CACHE[cache_key] = _make_entry(env_token)
            return env_token

        webhook_token = _try_webhook_token(ft, FABRIC_API_RESOURCE)
        if webhook_token:
            _TOKEN_CACHE[cache_key] = _make_entry(webhook_token)
            return webhook_token

        msal_result = _try_msal_device_code(ft, FABRIC_API_RESOURCE)
        if msal_result is not None:
            entry = _make_entry(
                msal_result["access_token"], msal_result["refresh_token"]
            )
            _TOKEN_CACHE[cache_key] = entry
            return entry["access_token"]

        cli_result = _try_azure_cli(ft, FABRIC_API_RESOURCE, az_cmd or AZ_CMD)
        if cli_result:
            _TOKEN_CACHE[cache_key] = _make_entry(cli_result)
            return cli_result

        raise RuntimeError(
            "No authentication method available for Fabric API.\n"
            "  See FabricLakehouse() docs for options."
        )

    @staticmethod
    def list_lakehouses(workspace_guid=None, fabric_tenant=None, token=None, az_cmd=None):
        """Discover all Lakehouses in the workspace via Fabric REST API.

        Returns a list of dicts with keys: displayName, id.

        Parameters
        ----------
        workspace_guid : str, optional
        fabric_tenant : str, optional
        token : str, optional
            Existing access token for Fabric API.
        az_cmd : str, optional

        Returns
        -------
        list[dict]
        """
        cfg = _load_config()
        wg = workspace_guid or cfg["workspace_guid"]
        t = FabricLakehouse._get_fabric_api_token(
            fabric_tenant=fabric_tenant, token=token, az_cmd=az_cmd
        )
        url = f"https://api.fabric.microsoft.com/v1/workspaces/{wg}/items"
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {t}"
        }, method="GET")
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
        lakes = [item for item in data.get("value", [])
                 if item.get("type") == "Lakehouse"]
        for l in lakes:
            l.pop("type", None)
        return lakes
