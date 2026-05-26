# fabriconnect / fabricpy

**Read Delta tables from Microsoft Fabric Lakehouses via HTTPS — no TDS/ODBC required.**

Bypasses the [known Fabric bug](docs/BUG_WORKSPACE_IP_FIREWALL_TDS.md) where workspace-level IP firewall rules incorrectly block TDS (port 1433) connections even for allowed IPs. Since all traffic is HTTPS (port 443), the firewall evaluates it correctly.

Two packages are provided — one for **R** (`fabriconnect`) and one for **Python** (`fabricpy`), both with identical capabilities.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [R Package Usage](#r-package-usage)
  - [Connect](#connect)
  - [List Tables](#list-tables)
  - [Read a Table](#read-a-table)
  - [SQL Queries via DuckDB](#sql-queries-via-duckdb)
  - [Configuration](#configuration)
- [Python Package Usage](#python-package-usage)
  - [Connect](#connect-1)
  - [List Tables](#list-tables-1)
  - [Read a Table](#read-a-table-1)
  - [SQL Queries via DuckDB](#sql-queries-via-duckdb-1)
  - [Configuration](#configuration-1)
- [Which Lakehouse Does It Connect To?](#which-lakehouse-does-it-connect-to)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Repository Structure](#repository-structure)
- [License](#license)

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Azure CLI** | Installed and logged in. Run `az login` and authenticate with your credentials. |
| **Fabric access** | Your account must have access (Viewer or above) to the target Fabric workspace. |
| **Network** | HTTPS (port 443) to `onelake.dfs.fabric.microsoft.com` and `onelake.blob.fabric.microsoft.com`. |
| **IP firewall** | The workspace must be set to **"Allow all connections"** or your machine's IP must be in the allowlist. |

Check your Azure CLI login:

```bash
az account show
```

If not logged in:

```bash
az login
```

---

## Installation

### R Package (from GitHub)

```r
# Install dependencies
install.packages(c("AzureStor", "arrow", "DBI", "httr"))

# Optional: for SQL queries
install.packages("duckdb")

# Install fabriconnect from GitHub
install.packages("remotes")
remotes::install_github("AKU-CDIO/fabric-inbound-access", subdir = "fabriconnect")
```

### Python Package (from GitHub)

```bash
# Base install
pip install git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy

# With pandas support
pip install "fabricpy[pandas] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy"

# With SQL query support (duckdb)
pip install "fabricpy[sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy"

# Full install
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy"
```

---

## Quick Start

### R

```r
library(fabriconnect)

conn <- connect_to_fabric()
tables <- list_tables(conn)
df <- read_table(conn, "dimenrolledparticipants")
head(df)
```

### Python

```python
from fabricpy import FabricLakehouse

lh = FabricLakehouse()
tables = lh.list_tables()
df = lh.to_pandas("dimenrolledparticipants")
print(df.head())
```

---

## R Package Usage

### Connect

The function `connect_to_fabric()` authenticates via Azure CLI and returns a connection object.

```r
library(fabriconnect)

# Connect with defaults (uzima_db_backup Lakehouse)
conn <- connect_to_fabric()
```

### List Tables

```r
# List all user tables
tables <- list_tables(conn)
print(tables)
#  [1] "agents"                    "dimdate"
#  [3] "dimenrolledparticipants"   "dimsleepdetailslogs"
#  [5] "dimsurveydictionary"       "dimsurveyquestionresult"
#  ...
```

### Read a Table

```r
# Read entire table into a data.frame
df <- read_table(conn, "dimenrolledparticipants")
cat("Rows:", nrow(df), "Cols:", ncol(df), "\n")
head(df[, 1:6])

# Read a large table
sleep <- read_table(conn, "factfitbitsleeplogs")
cat("Sleep logs:", nrow(sleep), "rows\n")

# Read a small dimension table
dates <- read_table(conn, "dimdate")
names(dates)
```

### SQL Queries via DuckDB

The `query_tables()` function automatically extracts table names from your SQL, fetches them from OneLake, and runs the query via DuckDB.

```r
# Simple count
result <- query_tables(conn, "
    SELECT count(1) AS n
    FROM dimenrolledparticipants
")
print(result)

# JOIN two tables with aggregation
result <- query_tables(conn, "
    SELECT p.ParticipantIdentifier,
           p.Gender,
           p.Age,
           count(s.Skey)          AS sleep_logs,
           avg(s.MinutesAsleep)   AS avg_min_asleep,
           avg(s.MinutesInBed)    AS avg_min_in_bed
    FROM dimenrolledparticipants p
    JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
    GROUP BY p.ParticipantIdentifier, p.Gender, p.Age
    ORDER BY sleep_logs DESC
")
head(result, 10)

# Filter and aggregate
result <- query_tables(conn, "
    SELECT Gender,
           count(*)          AS total,
           avg(Age)          AS avg_age,
           min(Age)          AS min_age,
           max(Age)          AS max_age
    FROM dimenrolledparticipants
    WHERE Gender IS NOT NULL
    GROUP BY Gender
")
print(result)
```

> **Note:** `query_tables()` fetches the full table into memory before querying. For very large tables (>10M rows), consider filtering in DuckDB after registration, or using Python's `deltalake` with pushdown predicates.

### Configuration

Override the default workspace or Lakehouse:

```r
conn <- connect_to_fabric(
    workspace_id  = "your-workspace-guid",
    lakehouse_id  = "your-lakehouse-guid",
    fabric_tenant = "your-fabric-tenant-id"
)
```

To discover Lakehouse GUIDs, use `list_lakehouses()`:

```r
lakes <- list_lakehouses()
print(lakes)
```

Or find them via the [Fabric portal](https://app.fabric.microsoft.com).

---

## Python Package Usage

### Connect

```python
from fabricpy import FabricLakehouse

lh = FabricLakehouse()
```

### List Tables

```python
tables = lh.list_tables()
print(tables)
# ['agents', 'dimdate', 'dimenrolledparticipants', ...]
```

### Read a Table

```python
# As pyarrow Table (zero-copy, efficient)
table = lh.read_table("dimenrolledparticipants")
print(f"{table.num_rows} rows, {table.num_columns} cols")
print(table.column_names)

# As pandas DataFrame
df = lh.to_pandas("factfitbitdailydata")
print(df.shape)
print(df.head())
```

### SQL Queries via DuckDB

The `sql()` method auto-extracts table names from your SQL, fetches them, and runs the query via DuckDB.

```python
# Simple count
df = lh.sql("SELECT count(1) AS n FROM dimenrolledparticipants")
print(df)

# JOIN with aggregation
df = lh.sql("""
    SELECT p.ParticipantIdentifier,
           p.Gender,
           p.Age,
           count(s.Skey)          AS sleep_logs,
           avg(s.MinutesAsleep)   AS avg_min_asleep,
           avg(s.MinutesInBed)    AS avg_min_in_bed
    FROM dimenrolledparticipants p
    JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
    GROUP BY p.ParticipantIdentifier, p.Gender, p.Age
    ORDER BY sleep_logs DESC
""")
print(df.head(10))

# Filter and group
df = lh.sql("""
    SELECT Gender,
           count(*)     AS total,
           avg(Age)     AS avg_age
    FROM dimenrolledparticipants
    WHERE Gender IS NOT NULL
    GROUP BY Gender
""")
print(df)
```

### Configuration

```python
lh = FabricLakehouse(
    workspace_guid="your-workspace-guid",
    lakehouse_guid="your-lakehouse-guid",
    fabric_tenant="your-fabric-tenant-id"
)
```

To discover Lakehouse GUIDs, call `list_lakehouses()`:

```python
lakes = FabricLakehouse.list_lakehouses()
for l in lakes:
    print(f"{l['displayName']}: {l['id']}")
```

---

## Which Lakehouse Does It Connect To?

By default, both packages connect to the **`uzima_db_backup`** Lakehouse in the **`cdiofabric`** workspace:

| Parameter | Default GUID | Description |
|-----------|-------------|-------------|
| Workspace | `67f69cc9-00c9-4c9c-a85b-38fc30774b7b` | Fabric workspace `cdiofabric` |
| Lakehouse | `67596566-8ea9-4fd6-a451-ca9654aa4f10` | Lakehouse `uzima_db_backup` |
| Tenant | `a5d4252a-02f9-4e60-96f0-9733baae4919` | Fabric Microsoft Entra tenant |

### All Lakehouses in the cdiofabric Workspace

The workspace contains **7 Lakehouses**. Connect to any of them by passing the appropriate GUID:

| Lakehouse Name | GUID |
|----------------|------|
| `uzima_db_backup` | `67596566-8ea9-4fd6-a451-ca9654aa4f10` |
| `CDIOUZIMA_Azure_Storage_Accounts_Data` | `7de09c85-b39d-49e4-873d-e683b671448b` |
| `azu_cdiouzima` | `07d783b9-d533-42f3-a9b7-bc16c18a5376` |
| `HCW_fitbit_data` | `65058b40-a60c-4267-a882-9263e0ba0617` |
| `Qualtrics` | `8bb92d0b-3f94-4bd1-94d4-b31b088e9061` |
| `LS_Fabric_Lakehouse` | `1ad04079-7636-4ce6-ac32-d99aede44c14` |
| `StagingLakehouseForDataflows_20251110175852` | `4cab7880-8c60-4bb6-a714-55cbe20f4326` |

Use `list_lakehouses()` (R) or `FabricLakehouse.list_lakehouses()` (Python) to discover these programmatically.

### Available Tables (31 user tables in uzima_db_backup)

```
agents, dimdate, dimenrolledparticipants, dimsleepdetailslogs,
dimsurveydictionary, dimsurveyquestionresult, dimsurveyresults,
dimsurveyresults_old, dimsurveystepresults, dimsurveytask,
factfitbitactivitieslogs, factfitbitdailydata, factfitbitintraday,
factfitbitintradaycombined, factfitbitintradaycombinedmm,
factfitbitintraminbymin, factfitbitintraminutebyminute,
factfitbitrestingheartrates, factfitbitsleeplogs,
qualtrics_hcw_student_survey, qualtrics_hcw_student_survey_sharepoint,
registeredparticipants, registeredparticipants_51, surveydata,
sysdiagrams, t_4747_..., t_4850_..., t_5109_..., t_8952_...,
tablelogs, users_logonaudit
```

---

## How It Works

```
Your machine                    OneLake (HTTPS:443)           Fabric SQL Endpoint (TDS:1433)
    |                                |                                |
    |--- GET /token (az.cmd) ------>|                                |
    |<--- Bearer token -------------|                                |
    |                                |                                |
    |--- GET /Tables (DFS API) ---->|                                |
    |<--- table list ---------------|                                |
    |                                |                                |
    |--- GET /Tables/X/*.parquet -->|                                |
    |<--- parquet data -------------|                                |
    |                                |                                |
    |  arrow::read_parquet()         |                                |
    |  or deltalake::DeltaTable()    |                                |
    |                                |                                |
    |  duckdb.sql(query)             |                                |
```

1. **Authentication**: Gets an Azure AD OAuth2 token for `https://storage.azure.com` from the Fabric tenant, using `az.cmd`.
2. **Discovery**: Lists Delta table directories via the OneLake ADLS Gen2 REST API (`GET /Tables?resource=filesystem`).
3. **Reading**: Downloads parquet files (for R) or uses the `deltalake` Rust library (for Python) to read Delta tables.
4. **SQL**: Loads tables into DuckDB in-memory and runs SQL queries.

All communication is **HTTPS (port 443)** — the IP firewall allows it.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Failed to obtain Azure access token` | Run `az login` and ensure you have access to the Fabric tenant. |
| `401 Unauthorized` | Your token expired or is from the wrong tenant. Re-run `az login`. |
| `No parquet files found` | The table name might be wrong. Check spelling with `list_tables()`. |
| `duckdb package not found` | Install DuckDB: `install.packages("duckdb")` (R) or `pip install duckdb` (Python). |
| `Azure CLI not found` | Install Azure CLI from https://aka.ms/installazurecliwindows |
| Package returns empty results | Ensure the workspace network setting allows your IP. Check the portal. |

---

## Repository Structure

```
connectToFabricVM/
├── README.md                          # This file
├── .gitignore
├── fabriconnect/                      # R package (R CMD INSTALL)
│   ├── DESCRIPTION, NAMESPACE, LICENSE
│   ├── README.md
│   └── R/  (connect.R, list_tables.R, read_table.R, query_tables.R, list_lakehouses.R)
├── fabriconnectpy/                    # Python package (pip install)
│   ├── pyproject.toml, README.md
│   └── fabricpy/  (__init__.py, client.py)
├── examples/
│   └── test_fabriconnect.R            # Runnable example with SQL JOIN
├── docs/
│   ├── BUG_WORKSPACE_IP_FIREWALL_TDS.md   # Bug report
│   ├── WORKAROUNDS.md                      # Workaround options
│   └── documentations.md                   # Technical deep-dive
├── onelake_delta_access.py            # Standalone Python reference script
└── connect_to_fabric_vm_only.py       # Original ODBC script (requires TDS)
```

---

## License

MIT
