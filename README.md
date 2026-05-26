# fabriconnect / fabricpy

Read Microsoft Fabric Lakehouse data from machines where the TDS/IP firewall blocks port 1433. All traffic uses HTTPS (port 443).

---

## Quick start

### 1. Login (once per session)

```bash
az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
```

### 2. Install

**R** — copy-paste into R or RStudio console:

```r
remotes::install_github("AKU-CDIO/fabric-inbound-access", subdir = "fabriconnect", force = TRUE, upgrade_dependencies = FALSE)
```

**Python** — paste into terminal/cmd:

```bash
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall --no-cache-dir
```

### 3. Connect and read

**R:**
```r
library(fabriconnect)
conn <- connect_to_fabric()                       # defaults to uzima_db_backup
list_tables(conn)                                 # 31 tables
read_table(conn, "dimenrolledparticipants")       # read all columns
```

**Python:**
```python
from fabricpy import FabricLakehouse
lh = FabricLakehouse()                            # defaults to uzima_db_backup
lh.list_tables()
lh.to_pandas("dimenrolledparticipants")
```

---

## Which Lakehouse has which tables

| Lakehouse | Tables |
|-----------|--------|
| `uzima_db_backup` *(default)* | 31 tables — `dimenrolledparticipants`, `factfitbitsleeplogs`, `dimdate`, `fac*`... |
| `HCW_fitbit_data` | 5 tables — `fitbitactivitylogs`, `fitbitdailydata`, `fitbitdevices`, `fitbitbodyweightlog`, `fitbitfiles` |
| `Qualtrics` | *(survey data)* |
| `CDIOUZIMA_Azure_Storage_Accounts_Data` | *(Azure storage data)* |
| `azu_cdiouzima` | *(Azure data)* |
| `LS_Fabric_Lakehouse` | *(Linked services)* |
| `StagingLakehouseForDataflows_20251110175852` | *(staging)* |

Connect by name:
```r
conn <- connect_to_fabric(lakehouse = "HCW_fitbit_data")
list_tables(conn)
read_table(conn, "fitbitdailydata")
```

---

## Updating the package

**If it's already loaded** — restart R first, then run the install command again.

Or use the helper (no restart needed):
```r
library(fabriconnect)
update_fabriconnect()
```

---

## Examples

### R — column pruning (less data transfer)

```r
library(fabriconnect)
conn <- connect_to_fabric()

# Read only 2 columns instead of all 13
read_table(conn, "dimenrolledparticipants",
           columns = c("ParticipantIdentifier", "Gender"))

# SQL with column pruning on large tables
query_tables(conn, "
  SELECT p.ParticipantIdentifier, count(s.Skey) AS n
  FROM dimenrolledparticipants p
  JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
  GROUP BY p.ParticipantIdentifier",
  table_columns = list(
    dimenrolledparticipants = c("Skey", "ParticipantIdentifier"),
    factfitbitsleeplogs     = c("Skey", "ParticipantKey")
  ))
```

### Python

```python
from fabricpy import FabricLakehouse

lh = FabricLakehouse()

# Column pruning
lh.to_pandas("dimenrolledparticipants",
             columns=["ParticipantIdentifier", "Gender"])

# SQL with column pruning
lh.sql("""
  SELECT p.ParticipantIdentifier, count(s.Skey) AS n
  FROM dimenrolledparticipants p
  JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
  GROUP BY p.ParticipantIdentifier""",
  table_columns={
    "dimenrolledparticipants": ["Skey", "ParticipantIdentifier"],
    "factfitbitsleeplogs":     ["Skey", "ParticipantKey"]
  })
```

### Override workspace / Lakehouse / tenant

```r
conn <- connect_to_fabric(
    workspace_id  = "67f69cc9-00c9-4c9c-a85b-38fc30774b7b",
    lakehouse     = "HCW_fitbit_data",
    fabric_tenant = "a5d4252a-02f9-4e60-96f0-9733baae4919"
)
```

```python
lh = FabricLakehouse(
    workspace_guid="67f69cc9-00c9-4c9c-a85b-38fc30774b7b",
    lakehouse="HCW_fitbit_data",
    fabric_tenant="a5d4252a-02f9-4e60-96f0-9733baae4919"
)
```

### List all Lakehouses in the workspace

```r
list_lakehouses()
```

```python
FabricLakehouse.list_lakehouses()
```

---

## Large tables (>500 GB)

Use `columns` / `table_columns` to fetch only the columns you need. Python's `deltalake` does predicate pushdown at the storage layer — only requested bytes cross the network. R reads parquet in-memory via `arrow::read_parquet()`.

| R | Python |
|---|--------|
| `read_table(conn, "t", columns = c("a", "b"))` | `lh.to_pandas("t", columns=["a", "b"])` |
| `query_tables(conn, sql, table_columns = list(...))` | `lh.sql(query, table_columns={...})` |

---

## Notes

- No temp files written to disk (R reads parquet into memory via `httr::GET()` + `arrow::read_parquet()`).
- SQL queries run in DuckDB (install with `install.packages("duckdb")`).
- Token obtained via `az.cmd` for `https://storage.azure.com` (Fabric tenant).
- All communication is HTTPS (443) — no TDS (1433) needed.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Failed to obtain Azure access token` | Re-run `az login --tenant a5d4252a-... --use-device-code` |
| `401 Unauthorized` | Token expired. Re-login. |
| `No parquet files found` | Check table name with `list_tables()` |
| `duckdb` not found | `install.packages("duckdb")` (R) or `pip install duckdb` (Python) |
| Package install says `...is in use and will not be installed` | Restart R and install again |
