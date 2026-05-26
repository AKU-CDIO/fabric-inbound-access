# fabricpy — Python package

Read Delta tables from Microsoft Fabric Lakehouses via the OneLake HTTPS API.

## Install

```bash
pip install ./fabriconnectpy/
# With pandas support:
pip install "./fabriconnectpy[pandas]"
```

## Usage

```python
from fabricpy import FabricLakehouse

lh = FabricLakehouse()

# List tables
tables = lh.list_tables()
print(tables)

# Read as pyarrow Table
table = lh.read_table("factfitbitdailydata")
print(f"{table.num_rows} rows, {table.num_columns} cols")

# Read as pandas DataFrame
df = lh.to_pandas("dimenrolledparticipants")
```

## API

| Method | Returns | Description |
|--------|---------|-------------|
| `list_tables()` | `list[str]` | All user table names |
| `read_table(name)` | `pyarrow.Table` | Full table as Arrow table |
| `to_pandas(name)` | `pd.DataFrame` | Full table as pandas DataFrame |

## Parameters

Override defaults via the constructor:

```python
lh = FabricLakehouse(
    workspace_guid="67f69cc9-00c9-4c9c-a85b-38fc30774b7b",
    lakehouse_guid="67596566-8ea9-4fd6-a451-ca9654aa4f10",
    fabric_tenant="a5d4252a-02f9-4e60-96f0-9733baae4919"
)
```

## How it works

1. Calls `az.cmd` to get an OAuth2 token for `https://storage.azure.com`
2. Uses the `deltalake` library to read Delta tables from OneLake
3. Storage options: `bearer_token` + `use_fabric_endpoint=true`

No ODBC/TDS needed — all traffic is HTTPS (port 443).
