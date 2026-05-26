# fabricpy — Python package

Read Delta tables from Microsoft Fabric Lakehouses via the OneLake HTTPS API.
Supports listing, reading (pyarrow + pandas), and SQL queries via DuckDB.

## Install (from GitHub)

```bash
# Base install
pip install git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy

# With pandas
pip install "fabricpy[pandas] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy"

# With SQL queries (duckdb)
pip install "fabricpy[sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy"

# Full (pandas + SQL)
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy"
```

## API

| Method | Returns | Description |
|--------|---------|-------------|
| `list_tables()` | `list[str]` | All user table names |
| `read_table(name)` | `pyarrow.Table` | Full table as Arrow table |
| `to_pandas(name)` | `pd.DataFrame` | Full table as pandas DataFrame |
| `sql(query)` | `pd.DataFrame` | Run SQL across tables via DuckDB |
| `list_lakehouses()` (static) | `list[dict]` | Discover all Lakehouses in the workspace |

## Usage

```python
from fabricpy import FabricLakehouse

lh = FabricLakehouse()

# List tables
tables = lh.list_tables()

# Read as pandas
df = lh.to_pandas("dimenrolledparticipants")

# SQL with JOIN
df = lh.sql("""
    SELECT p.ParticipantIdentifier, count(s.Skey) AS n
    FROM dimenrolledparticipants p
    JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
    GROUP BY p.ParticipantIdentifier
""")

# Discover all Lakehouses in the workspace
lakes = FabricLakehouse.list_lakehouses()
for l in lakes:
    print(f"{l['displayName']}: {l['id']}")
```

## Configuration

```python
lh = FabricLakehouse(
    workspace_guid="your-workspace-guid",
    lakehouse_guid="your-lakehouse-guid",
    fabric_tenant="your-tenant-id"
)
```

## How it works

1. Calls `az.cmd` to get an OAuth2 token for `https://storage.azure.com`
2. Uses `deltalake` with `bearer_token` + `use_fabric_endpoint=true` to read Delta tables
3. For SQL: loads tables into DuckDB in-memory

No ODBC/TDS needed — all traffic is HTTPS (port 443).
