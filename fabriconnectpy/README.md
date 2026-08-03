# fabricpy - Python package

Read Microsoft Fabric Lakehouse data and connect to Fabric SQL endpoints.

## Personal Laptop Install

Install or update directly with pip into your Python user site; no virtual environment is required.

Mac/Linux:

```bash
python3 -m pip install --user "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --upgrade --no-cache-dir
```

Windows PowerShell:

```powershell
py -3 -m pip install --user "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --upgrade --no-cache-dir
```

## Service Principal SQL Access

Approved researchers can connect from personal laptops through Azure Key Vault. Python opens a browser for Key Vault login when `connect_to_fabric_sql(auth="sp_vault")` is first called. Call it once, reuse the same `conn` for all reads/queries, then close it with `conn.close()`.

```python
from fabricpy import connect_to_fabric_sql, list_sql_tables, read_sql_table, query_sql

conn = connect_to_fabric_sql(auth="sp_vault")
print(list_sql_tables(conn))
df = read_sql_table(conn, "dbo.dimenrolledparticipants", top=10)
print(df.head())
summary = query_sql(conn, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants")
print(summary)
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

For OneLake-only reads, install the optional OneLake extras if an admin asks you to use that legacy path:

```bash
python3 -m pip install --user "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --upgrade --no-cache-dir
```