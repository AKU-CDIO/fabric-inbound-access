# fabricpy - Python package

Read Microsoft Fabric Lakehouse data and connect to Fabric SQL endpoints.

## Personal Laptop Install

Use a dedicated virtual environment. Do not install into Anaconda `base` or another shared Python environment.

Mac/Linux:

```bash
python3 -m venv .venv
./.venv/bin/python -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
```

Windows PowerShell:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
```

## Service Principal SQL Access

Approved researchers can connect from personal laptops through Azure Key Vault. Python signs in interactively when `connect_to_fabric_sql()` is first called: by default it prints one device-code prompt instead of trying browser login first. Call it once, reuse the same `conn` for all reads/queries, then close it once in `finally`.

```python
from fabricpy import connect_to_fabric_sql, list_sql_tables, read_sql_table, query_sql

conn = connect_to_fabric_sql(keyvault_auth_method="device_code")
try:
    print(list_sql_tables(conn))
    df = read_sql_table(conn, "dbo.dimenrolledparticipants", top=10)
    print(df.head())
    summary = query_sql(conn, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants")
    print(summary)
finally:
    conn.close()
```

This follows the Azure AD + MFA -> Key Vault -> service principal -> Fabric SQL flow.

## OneLake / FabricLakehouse Access

The original `FabricLakehouse` API is still available for approved VM/OneLake workflows.

```python
from fabricpy import FabricLakehouse

lh = FabricLakehouse()
tables = lh.list_tables()
df = lh.read_table("dimenrolledparticipants").to_pandas()
```

For OneLake reads, install the OneLake extras in a dedicated environment:

```bash
python3 -m venv .venv
./.venv/bin/python -m pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
```

On Windows PowerShell, use `.\.venv\Scripts\python.exe` instead of `./.venv/bin/python`.