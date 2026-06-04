# fabricpy — Python package

Read Delta tables from Microsoft Fabric Lakehouses via OneLake HTTPS. Works through restricted IP firewalls that block TDS (1433).

## Azure login (device code)

```bash
az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
```

## Install (one-liner)

```bash
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall --no-cache-dir
```

## API

| Method | Returns | Description |
|--------|---------|-------------|
| `list_tables()` | `list[str]` | All user table names |
| `read_table(name, columns=None)` | `pyarrow.Table` | Full table as Arrow table (with column pushdown) |
| `to_pandas(name, columns=None)` | `pd.DataFrame` | Full table as pandas DataFrame |
| `sql(query, table_columns=None)` | `pd.DataFrame` | Run SQL across tables via DuckDB |
| `list_lakehouses()` (static) | `list[dict]` | Discover all Lakehouses in the workspace |

## Usage

```python
from fabricpy import FabricLakehouse

lh = FabricLakehouse()

# Read all columns
df = lh.to_pandas("dimenrolledparticipants")

# Read only needed columns (predicate pushdown — less network)
df = lh.to_pandas("factfitbitsleeplogs",
                   columns=["ParticipantIdentifier", "MinutesAsleep"])

# SQL with column pruning
df = lh.sql("""
    SELECT p.ParticipantIdentifier, count(*) AS n
    FROM dimenrolledparticipants p
    JOIN factfitbitsleeplogs s ON p.ParticipantIdentifier = s.ParticipantIdentifier
    GROUP BY p.ParticipantIdentifier""",
  table_columns={
    "dimenrolledparticipants": ["ParticipantIdentifier"],
    "factfitbitsleeplogs":     ["ParticipantIdentifier"]
  })

# Discover and connect by name
lakes = FabricLakehouse.list_lakehouses()
lh2 = FabricLakehouse(lakehouse="HCW_fitbit_data")
```

## Configuration

IDs are in `fabricpy/config.json` and loaded automatically. Override:

```python
lh = FabricLakehouse(
    workspace_guid="your-workspace-guid",
    lakehouse_guid="your-lakehouse-guid",
    lakehouse="HCW_fitbit_data",
    fabric_tenant="your-tenant-id"
)
```

## Large tables

- `deltalake` reads directly from OneLake (no disk download)
- Use `columns=` for predicate pushdown — only requested bytes cross the network
- No temp files, no accumulation
