import subprocess
import json
import urllib.request
import urllib.error
import sys

# Configuration
WORKSPACE_GUID = "67f69cc9-00c9-4c9c-a85b-38fc30774b7b"
WORKSPACE_NAME = "cdiofabric"
LAKEHOUSE_GUID = "67596566-8ea9-4fd6-a451-ca9654aa4f10"
LAKEHOUSE_NAME = "uzima_db_backup"
FABRIC_TENANT = "a5d4252a-02f9-4e60-96f0-9733baae4919"
STORAGE_RESOURCE = "https://storage.azure.com"
AZ_CMD = "az.cmd"

def get_token():
    result = subprocess.run(
        f"{AZ_CMD} account get-access-token --resource {STORAGE_RESOURCE} "
        f"--tenant {FABRIC_TENANT} --query accessToken -o tsv",
        capture_output=True, text=True, timeout=30, shell=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to get token: {result.stderr}")
    token = result.stdout.strip()
    if not token:
        raise RuntimeError("Empty token returned")
    return token

def list_tables():
    token = get_token()
    url = ("https://onelake.dfs.fabric.microsoft.com/cdiofabric/"
           f"{LAKEHOUSE_NAME}.Lakehouse/Tables?recursive=true&maxResults=1000&resource=filesystem")
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

def read_table(table_name):
    from deltalake import DeltaTable
    token = get_token()
    storage_options = {
        "bearer_token": token,
        "use_fabric_endpoint": "true"
    }
    path = f"abfss://{WORKSPACE_GUID}@onelake.dfs.fabric.microsoft.com/{LAKEHOUSE_GUID}/Tables/{table_name}"
    dt = DeltaTable(path, storage_options=storage_options)
    return dt.to_pyarrow_table()

if __name__ == "__main__":
    tables = list_tables()
    print(f"Found {len(tables)} tables in Lakehouse:")
    for t in tables:
        print(f"  - {t}")

    if tables:
        sample = tables[4]
        print(f"\nReading '{sample}'...")
        tbl = read_table(sample)
        print(f"  {tbl.num_rows} rows, {tbl.num_columns} cols")
        print(f"  Columns: {tbl.column_names}")
