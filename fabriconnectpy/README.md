# fabricpy — Python package

Read Delta tables from Microsoft Fabric Lakehouses via OneLake HTTPS. Works through restricted IP firewalls that block TDS (1433).

## Azure login (device code)

```bash
az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
```

## Install

```bash
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall
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

# Connect (default: uzima_db_backup)
lh = FabricLakehouse()

# Connect by name (auto-resolves to GUID)
lh = FabricLakehouse(lakehouse_name="HCW_fitbit_data")

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

# Discover Lakehouses
lakes = FabricLakehouse.list_lakehouses()
```

## Configuration

IDs are in `fabricpy/config.json` and loaded automatically. Override:

```python
lh = FabricLakehouse(
    workspace_guid="your-workspace-guid",
    lakehouse_guid="your-lakehouse-guid",
    lakehouse_name="HCW_fitbit_data",  # alternative to lakehouse_guid
    fabric_tenant="your-tenant-id"
)
```
