# fabriconnect / fabricpy

R and Python packages for reading Microsoft Fabric Lakehouse data over HTTPS, bypassing the TDS/IP firewall port-1433 restriction. All traffic uses port 443 only.

## Prerequisites

- **Workspace access** — your Azure AD identity must have at least **Viewer** role on the target Fabric workspace.
- **Network** — the workspace IP firewall must allow your IP or be set to allow all connections.

### Authentication (choose one)

The packages try these methods in order: explicit token → `FABRIC_ACCESS_TOKEN` env var → Fabric CLI → Azure CLI.

**1. Azure CLI** (recommended if you have Azure access):

```bash
az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
```

**2. Fabric CLI** (for Fabric BI portal users without Azure):

```bash
# https://github.com/microsoft/fabric-cli
fab login
```

**3. Environment variable** (CI / headless):

```bash
export FABRIC_ACCESS_TOKEN="<your-token>"
```

**4. Pass token directly** (in code):

```python
lh = FabricLakehouse(token="<your-token>")
```

```r
conn <- connect_to_fabric(access_token = "<your-token>")
```

**5. Interactive pop-up** (requires `pip install msal`):

If no other method works, `fabricpy` will prompt via browser-based device code login automatically.

---

## Installation

### R

```r
remotes::install_github("AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect", force = TRUE, upgrade_dependencies = FALSE)
```

### Python

```bash
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall --no-cache-dir
```

---

## Quick start

### Default Lakehouse (uzima_db_backup)

```r
library(fabriconnect)

conn <- connect_to_fabric()

list_tables(conn)
# 31 tables: dimenrolledparticipants, factfitbitsleeplogs, dimdate, ...

df <- read_table(conn, "dimenrolledparticipants")
```

```python
from fabricpy import FabricLakehouse

lh = FabricLakehouse()

lh.list_tables()

df = lh.to_pandas("dimenrolledparticipants")
```

### Connect to a specific Lakehouse

```r
conn <- connect_to_fabric(lakehouse = "HCW_fitbit_data")
list_tables(conn)
# 5 tables: fitbitactivitylogs, fitbitdailydata, fitbitdevices, ...
```

```python
lh = FabricLakehouse(lakehouse = "HCW_fitbit_data")
```

---

## Available Lakehouses

All seven Lakehouses in the `cdiofabric` workspace:

| Name | GUID | Tables |
|------|------|--------|
| `uzima_db_backup` *(default)* | `67596566-...` | 31 — `dimenrolledparticipants`, `factfitbitsleeplogs`, `dimdate`, ... |
| `HCW_fitbit_data` | `65058b40-...` | 5 — `fitbitactivitylogs`, `fitbitdailydata`, `fitbitdevices`, ... |
| `Qualtrics` | `8bb92d0b-...` | Survey data |
| `CDIOUZIMA_Azure_Storage_Accounts_Data` | `7de09c85-...` | Azure storage metadata |
| `azu_cdiouzima` | `07d783b9-...` | Azure data |
| `LS_Fabric_Lakehouse` | `1ad04079-...` | Linked services |
| `StagingLakehouseForDataflows_20251110175852` | `4cab7880-...` | Dataflow staging |

Discover programmatically:

```r
list_lakehouses()
```

```python
FabricLakehouse.list_lakehouses()
```

---

## Key examples

### Read a table (all columns)

```r
df <- read_table(conn, "dimenrolledparticipants")
```

### Column pruning — reduced data transfer

```r
df <- read_table(conn, "dimenrolledparticipants",
  columns = c("ParticipantIdentifier", "Gender", "Age"))
```

### SQL queries (requires `duckdb`)

```r
query_tables(conn, "SELECT count(*) FROM dimenrolledparticipants")
```

### Multi-table SQL with column pruning

```r
result <- query_tables(conn, "
  SELECT p.ParticipantIdentifier,
         COUNT(*)              AS sleep_logs,
         AVG(s.MinutesAsleep)  AS avg_min_asleep
  FROM dimenrolledparticipants p
  JOIN factfitbitsleeplogs s ON p.ParticipantIdentifier = s.ParticipantIdentifier
  GROUP BY p.ParticipantIdentifier",
  table_columns = list(
    dimenrolledparticipants = c("ParticipantIdentifier"),
    factfitbitsleeplogs     = c("ParticipantIdentifier", "MinutesAsleep")
  ))
```

### Cross-lakehouse queries

Join tables across different Lakehouses by passing a named list of connections. Tables are referenced with a schema prefix in the SQL:

```r
conn1 <- connect_to_fabric(lakehouse = "uzima_db_backup")
conn2 <- connect_to_fabric(lakehouse = "HCW_fitbit_data")

result <- query_tables(
  list(uzima = conn1, hcw = conn2),
  "SELECT p.ParticipantIdentifier, f.ActivityDate, f.Steps
   FROM uzima.dimenrolledparticipants p
   JOIN hcw.fitbitdailydata f
     ON p.ParticipantIdentifier = f.ParticipantIdentifier
   LIMIT 10")
```

```python
lh1 = FabricLakehouse(lakehouse="uzima_db_backup")
lh2 = FabricLakehouse(lakehouse="HCW_fitbit_data")

result = FabricLakehouse.cross_query(
  {"uzima": lh1, "hcw": lh2},
  "SELECT p.ParticipantIdentifier, f.ActivityDate, f.Steps
   FROM uzima.dimenrolledparticipants p
   JOIN hcw.fitbitdailydata f
     ON p.ParticipantIdentifier = f.ParticipantIdentifier
   LIMIT 10")
```

### Demographics summary

```r
demo <- query_tables(conn, "
  SELECT Gender, COUNT(*) AS total, AVG(Age) AS avg_age
  FROM dimenrolledparticipants
  WHERE Gender IS NOT NULL
  GROUP BY Gender")
```

### Python equivalents

```python
# All columns
df = lh.to_pandas("dimenrolledparticipants")

# Column pruning
df = lh.to_pandas("dimenrolledparticipants",
  columns=["ParticipantIdentifier", "Gender", "Age"])

# SQL with pruning
df = lh.sql("SELECT ...",
  table_columns={"dimenrolledparticipants": ["Skey", "ParticipantIdentifier"]})
```

---

## Large tables (>500 GB)

Use the `columns` or `table_columns` parameters to fetch only required columns. Python's `deltalake` performs predicate pushdown at the OneLake storage layer — only requested bytes traverse the network. R reads parquet payloads in-memory via `httr::GET()` + `arrow::read_parquet()` with no disk writes.

| Task | R | Python |
|------|---|--------|
| Column pruning | `read_table(conn, "t", columns = c("a", "b"))` | `lh.to_pandas("t", columns=["a", "b"])` |
| SQL pruning | `query_tables(conn, sql, table_columns = list(...))` | `lh.sql(query, table_columns={...})` |

---

## Configuration

The bundled `config.json` provides sensible defaults. Override any parameter:

```r
connect_to_fabric(
  workspace_id  = "67f69cc9-00c9-4c9c-a85b-38fc30774b7b",
  lakehouse     = "HCW_fitbit_data",
  fabric_tenant = "a5d4252a-02f9-4e60-96f0-9733baae4919"
)
```

```python
FabricLakehouse(
  workspace_guid = "67f69cc9-00c9-4c9c-a85b-38fc30774b7b",
  lakehouse      = "HCW_fitbit_data",
  fabric_tenant  = "a5d4252a-02f9-4e60-96f0-9733baae4919"
)
```

---

## Updating

Restart R, then re-run the install command. Alternatively:

```r
library(fabriconnect)
update_fabriconnect()   # uses a fresh R sub-process; no restart needed
```

---

## Architecture

1. **Authentication** — `az.cmd` obtains an OAuth2 token for `https://storage.azure.com` scoped to the Fabric tenant.
2. **Metadata** — OneLake ADLS Gen2 DFS REST API (`onelake.dfs.fabric.microsoft.com`) lists Delta table directories.
3. **Data** — Parquet files are fetched over HTTPS and read in-memory:
   - **R**: `httr::GET()` → `arrow::read_parquet(raw)` — no temp files.
   - **Python**: `deltalake` reads directly from OneLake via `use_fabric_endpoint=true`.
4. **SQL** — Queries execute in DuckDB after loading required tables.

All communication is HTTPS (443). No TDS (1433) is used.

---

## Troubleshooting

| Problem | Resolution |
|---------|------------|
| `Failed to obtain Azure access token` | Re-authenticate: `az login --tenant a5d4252a-... --use-device-code` |
| `401 Unauthorized` | Token expired. Re-run `az login`. |
| `No parquet files found` | Verify table name with `list_tables()`. Table names are case-sensitive. |
| Package install says `...is in use and will not be installed` | Restart R and re-run the install command. |
| `duckdb` not found | Install it: `install.packages("duckdb")` (R) or `pip install duckdb` (Python). |

---

## Repository structure

```
fabriconnect/              # R package source
  inst/config.json         # workspace / Lakehouse GUIDs
  R/                       # connect, list_tables, read_table, query_tables, list_lakehouses, update_fabriconnect
fabriconnectpy/            # Python package source
  fabricpy/config.json     # workspace / Lakehouse GUIDs
  fabricpy/client.py       # FabricLakehouse class
examples/test_fabriconnect.R  # Runnable R example with SQL JOIN
install_fabriconnect.bat   # Double-click installer for Windows
docs/                      # Supplementary documentation
```

---

## License

Apache 2.0

**Author:** CDIO, AKU  
**Contact:** Derick Imbati — derick.imbati@aku.edu
