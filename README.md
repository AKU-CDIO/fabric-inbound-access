# fabriconnect / fabricpy

Two R/Python packages to read Microsoft Fabric Lakehouse data from machines with restricted outbound rules, bypassing the workspace IP firewall bug that blocks TDS port 1433. All traffic is HTTPS (port 443).

---

## Prerequisites

### Azure login (device code)

Since this VM and the Fabric workspace are in **different tenants**, log in with the Fabric tenant explicitly:

```bash
az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
```

Follow the browserless device-code flow (copy the URL + code into any browser). Verify:

```bash
az account show
```

Your access must include at least **Viewer** role on the target Fabric workspace, and the workspace must allow your IP (or be set to "Allow all connections").

---

## Installation

### R

**If the package is broken (missing DESCRIPTION)**, use a **fresh R process** from the command line:

```bash
Rscript -e "remotes::install_github('AKU-CDIO/fabric-inbound-access', subdir = 'fabriconnect', force = TRUE, upgrade_dependencies = FALSE)"
```

If the package is already loaded and working, call from within R:

```r
# Restart R first, then in a fresh session:
library(fabriconnect)
update_fabriconnect()   # installs via a sub-process, no DLL lock
```

Installs all dependencies (`arrow`, `DBI`, `httr`, `jsonlite`) automatically. `duckdb` is optional for SQL queries.

### Python (one-liner)

```bash
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall --no-cache-dir
```

---

## R Package

```r
library(fabriconnect)

# Connect (IDs read from bundled config.json)
conn <- connect_to_fabric()

# Connect by Lakehouse name (auto-resolves to GUID)
conn <- connect_to_fabric(lakehouse = "HCW_fitbit_data")

# List tables
tables <- list_tables(conn)

# Read a table (temp dir cleaned before each call, overwrite=TRUE)
df <- read_table(conn, "dimenrolledparticipants")

# Read only specific columns — less data transferred, less memory
df <- read_table(conn, "factfitbitsleeplogs",
                 columns = c("ParticipantKey", "MinutesAsleep", "MinutesInBed"))

# SQL with JOIN — table_columns prunes large tables
result <- query_tables(conn, "
    SELECT p.ParticipantIdentifier, count(s.Skey) AS n
    FROM dimenrolledparticipants p
    JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
    GROUP BY p.ParticipantIdentifier",
  table_columns = list(
    dimenrolledparticipants = c("Skey", "ParticipantIdentifier"),
    factfitbitsleeplogs     = c("Skey", "ParticipantKey")
  ))

# Discover all Lakehouses
lakes <- list_lakehouses()
```

### Override defaults

```r
conn <- connect_to_fabric(
    workspace_id   = "your-workspace-guid",
    lakehouse_id   = "your-lakehouse-guid",
    lakehouse      = "HCW_fitbit_data",
    fabric_tenant  = "your-tenant-id"
)
```

---

## Python Package

```python
from fabricpy import FabricLakehouse

lh = FabricLakehouse()

# Connect by Lakehouse name
lh = FabricLakehouse(lakehouse="HCW_fitbit_data")

# List tables
tables = lh.list_tables()

# Read all columns
df = lh.to_pandas("dimenrolledparticipants")

# Read only specific columns (pushdown — no unnecessary transfer)
df = lh.to_pandas("factfitbitsleeplogs",
                   columns=["ParticipantKey", "MinutesAsleep", "MinutesInBed"])

# SQL with column pruning
df = lh.sql("""
    SELECT p.ParticipantIdentifier, count(s.Skey) AS n
    FROM dimenrolledparticipants p
    JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
    GROUP BY p.ParticipantIdentifier""",
  table_columns={
    "dimenrolledparticipants": ["Skey", "ParticipantIdentifier"],
    "factfitbitsleeplogs":     ["Skey", "ParticipantKey"]
  })

# Discover all Lakehouses
lakes = FabricLakehouse.list_lakehouses()
```

### Override defaults

```python
lh = FabricLakehouse(
    workspace_guid="your-workspace-guid",
    lakehouse_guid="your-lakehouse-guid",
    lakehouse="HCW_fitbit_data",
    fabric_tenant="your-tenant-id"
)
```

---

## Working with Large Tables (>500 GB)

| Strategy | R | Python |
|----------|---|--------|
| **Column pruning** | `read_table(conn, "table", columns = c("col1", "col2"))` | `lh.to_pandas("table", columns=["col1", "col2"])` |
| **SQL column pruning** | `query_tables(conn, sql, table_columns = list(...))` | `lh.sql(query, table_columns={...})` |
| **Disk usage** | In-memory via `download_blob(dest=NULL)`; falls back to unique tempfile + auto-delete | Reads directly from OneLake (no disk) |
| **Memory** | Full table loaded into R's memory | Full table loaded into Python memory |
| **Temp file cleanup** | Automatic — `unlink()` before each `read_table()` call | No temp files |

**For the largest tables:** Python's `deltalake` library reads directly from OneLake without downloading to disk. The `columns` parameter enables **predicate pushdown** — only the requested bytes cross the network. R's `AzureStor` downloads parquet files first (deleted before each subsequent call) and then reads with `arrow`.

---

## Available Lakehouses (cdiofabric workspace)

| Name | GUID |
|------|------|
| `uzima_db_backup` | `67596566-8ea9-4fd6-a451-ca9654aa4f10` |
| `CDIOUZIMA_Azure_Storage_Accounts_Data` | `7de09c85-b39d-49e4-873d-e683b671448b` |
| `azu_cdiouzima` | `07d783b9-d533-42f3-a9b7-bc16c18a5376` |
| `HCW_fitbit_data` | `65058b40-a60c-4267-a882-9263e0ba0617` |
| `Qualtrics` | `8bb92d0b-3f94-4bd1-94d4-b31b088e9061` |
| `LS_Fabric_Lakehouse` | `1ad04079-7636-4ce6-ac32-d99aede44c14` |
| `StagingLakehouseForDataflows_20251110175852` | `4cab7880-8c60-4bb6-a714-55cbe20f4326` |

The default is `uzima_db_backup` (31 user tables). Use `list_lakehouses()` or `FabricLakehouse.list_lakehouses()` to discover them programmatically.

---

## How it works

1. `az.cmd` gets an OAuth2 token for `https://storage.azure.com` (Fabric tenant)
2. OneLake ADLS Gen2 REST API lists Delta table directories
3. **R**: Downloads parquet files (temp dir cleaned each run) → `arrow::read_parquet()`
   **Python**: Reads Delta tables directly via `deltalake` with `use_fabric_endpoint=true` (no disk)
4. SQL queries run in DuckDB in-memory after fetching tables

All communication is HTTPS (443) — no TDS (1433) needed.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Failed to obtain Azure access token` | Re-run `az login --tenant a5d4252a-... --use-device-code` |
| `401 Unauthorized` | Token expired or wrong tenant. Re-login. |
| `No parquet files found` | Check table name spelling with `list_tables()` |
| `duckdb not found` | `install.packages("duckdb")` (R) or `pip install duckdb` (Python) |
| Empty results | Check workspace IP firewall — your IP must be allowed |

---

## Repository structure

```
fabriconnect/          # R package
  inst/config.json     # workspace/Lakehouse GUIDs
  R/                   # connect, list_tables, read_table, query_tables, list_lakehouses
fabriconnectpy/        # Python package
  fabricpy/config.json # workspace/Lakehouse GUIDs
  fabricpy/client.py   # FabricLakehouse class
examples/
docs/
```

---

## License

MIT
