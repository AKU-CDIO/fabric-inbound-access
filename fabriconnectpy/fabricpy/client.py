import subprocess
import json
import urllib.request

AZ_CMD = "az.cmd"
FABRIC_TENANT = "a5d4252a-02f9-4e60-96f0-9733baae4919"
WORKSPACE_GUID = "67f69cc9-00c9-4c9c-a85b-38fc30774b7b"
WORKSPACE_NAME = "cdiofabric"
LAKEHOUSE_GUID = "67596566-8ea9-4fd6-a451-ca9654aa4f10"
LAKEHOUSE_NAME = "uzima_db_backup"
STORAGE_RESOURCE = "https://storage.azure.com"

class FabricLakehouse:
    def __init__(self, workspace_guid=None, lakehouse_guid=None,
                 fabric_tenant=None, az_cmd=None):
        self.workspace_guid = workspace_guid or WORKSPACE_GUID
        self.lakehouse_guid = lakehouse_guid or LAKEHOUSE_GUID
        self.fabric_tenant = fabric_tenant or FABRIC_TENANT
        self.az_cmd = az_cmd or AZ_CMD

    def _get_token(self):
        result = subprocess.run(
            f"{self.az_cmd} account get-access-token "
            f"--resource {STORAGE_RESOURCE} "
            f"--tenant {self.fabric_tenant} "
            f"--query accessToken -o tsv",
            capture_output=True, text=True, timeout=30, shell=True
        )
        if result.returncode != 0:
            raise RuntimeError(f"Auth failed: {result.stderr}")
        token = result.stdout.strip()
        if not token:
            raise RuntimeError("Empty token returned from Azure CLI")
        return token

    def list_tables(self):
        token = self._get_token()
        url = (
            f"https://onelake.dfs.fabric.microsoft.com/{WORKSPACE_NAME}/"
            f"{LAKEHOUSE_NAME}.Lakehouse/Tables"
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

    def read_table(self, table_name):
        from deltalake import DeltaTable
        token = self._get_token()
        storage_options = {
            "bearer_token": token,
            "use_fabric_endpoint": "true"
        }
        path = (
            f"abfss://{self.workspace_guid}@onelake.dfs.fabric.microsoft.com/"
            f"{self.lakehouse_guid}/Tables/{table_name}"
        )
        dt = DeltaTable(path, storage_options=storage_options)
        return dt.to_pyarrow_table()

    def to_pandas(self, table_name):
        table = self.read_table(table_name)
        return table.to_pandas()

    def sql(self, query):
        """Run a SQL query on Lakehouse tables using DuckDB.

        Table names are auto-extracted from FROM and JOIN clauses.
        Requires duckdb package.

        Parameters
        ----------
        query : str
            SQL query. Use table names directly, e.g.
            "SELECT * FROM dimdate"

        Returns
        -------
        pandas.DataFrame
        """
        import duckdb
        import re
        con = duckdb.connect()
        tables = set()
        for kw in ("FROM", "JOIN"):
            for m in re.finditer(rf"\b{kw}\s+(\w+)", query, re.IGNORECASE):
                tables.add(m.group(1))
        for tbl in tables:
            df = self.to_pandas(tbl)
            con.register(tbl, df)
        result = con.execute(query)
        return result.fetchdf()
