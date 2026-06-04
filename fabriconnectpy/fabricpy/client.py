import subprocess
import json
import urllib.request
import os

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

_TOKEN_CACHE = {}

def _try_env_var_token():
    token = os.environ.get("FABRIC_ACCESS_TOKEN") or os.environ.get("AZURE_ACCESS_TOKEN")
    return token.strip() if token else None

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
    token = result.stdout.strip()
    return token if token else None

def _try_msal_device_code(tenant, resource):
    try:
        import msal
    except ImportError:
        return None
    import sys
    import threading
    app = msal.PublicClientApplication(
        "1950a258-227b-4e31-a9cf-717495945fc2",
        authority=f"https://login.microsoftonline.com/{tenant}"
    )
    flow = app.initiate_device_flow(scopes=[f"{resource}/.default"])
    if "user_code" not in flow:
        return None
    print(f"Open {flow['verification_uri']} and enter code {flow['user_code']}", file=sys.stderr)
    result = {"token": None}
    def acquire():
        r = app.acquire_token_by_device_flow(flow)
        if "access_token" in r:
            result["token"] = r["access_token"]
    t = threading.Thread(target=acquire, daemon=True)
    t.start()
    t.join(timeout=120)
    return result["token"]

class FabricLakehouse:
    def __init__(self, workspace_guid=None, lakehouse_guid=None,
                 lakehouse=None, lakehouse_name=None,
                 fabric_tenant=None, token=None, az_cmd=None):
        cfg = _load_config()
        self.workspace_guid = workspace_guid or cfg["workspace_guid"]
        self.fabric_tenant = fabric_tenant or cfg["fabric_tenant"]
        self.az_cmd = az_cmd or AZ_CMD
        self._explicit_token = token

        # lakehouse is a shorthand alias for lakehouse_name
        if lakehouse_name is None and lakehouse is not None:
            lakehouse_name = lakehouse

        if lakehouse_name is not None:
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
        if cache_key in _TOKEN_CACHE:
            return _TOKEN_CACHE[cache_key]

        # Strategy 1: explicitly provided token
        if self._explicit_token:
            _TOKEN_CACHE[cache_key] = self._explicit_token
            return self._explicit_token

        # Strategy 2: environment variable
        env_token = _try_env_var_token()
        if env_token:
            _TOKEN_CACHE[cache_key] = env_token
            return env_token

        # Strategy 3: Azure CLI (non-interactive, widely available)
        cli_token = _try_azure_cli(self.fabric_tenant, resource, self.az_cmd)
        if cli_token:
            _TOKEN_CACHE[cache_key] = cli_token
            return cli_token

        # Strategy 4: MSAL device code (interactive pop-up — users sign in with email/password)
        msal_token = _try_msal_device_code(self.fabric_tenant, resource)
        if msal_token:
            _TOKEN_CACHE[cache_key] = msal_token
            return msal_token

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
            parts = name.split("/Tables/", 1)[1]
            table = parts.split("/")[0]
            if table and not table.startswith("_"):
                tables.add(table)
        return sorted(tables)

    def read_table(self, table_name, columns=None):
        """Read a Delta table as a pyarrow Table.

        Parameters
        ----------
        table_name : str
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
        path = (
            f"abfss://{self.workspace_guid}@onelake.dfs.fabric.microsoft.com/"
            f"{self.lakehouse_guid}/Tables/{table_name}"
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
            for m in re.finditer(rf"\b{kw}\s+([\w\s,]+?)(?:\s+(?:AS\s+)?\w+\s*(?:ON|\s|$)|$|\s+(?:WHERE|GROUP|ORDER|HAVING|LIMIT))", query, re.IGNORECASE):
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
        if cache_key in _TOKEN_CACHE:
            return _TOKEN_CACHE[cache_key]

        if token:
            _TOKEN_CACHE[cache_key] = token
            return token

        env_token = _try_env_var_token()
        if env_token:
            _TOKEN_CACHE[cache_key] = env_token
            return env_token

        cli_token = _try_azure_cli(ft, FABRIC_API_RESOURCE, az_cmd or AZ_CMD)
        if cli_token:
            _TOKEN_CACHE[cache_key] = cli_token
            return cli_token

        msal_token = _try_msal_device_code(ft, FABRIC_API_RESOURCE)
        if msal_token:
            _TOKEN_CACHE[cache_key] = msal_token
            return msal_token

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
