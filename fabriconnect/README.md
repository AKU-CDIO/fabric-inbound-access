# fabriconnect — R package

Read Delta tables from Microsoft Fabric Lakehouses via OneLake HTTPS. Works through restricted IP firewalls that block TDS (1433).

## Azure login (device code)

```bash
az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
```

## Install

```r
install.packages(c("AzureStor", "arrow", "DBI", "httr", "jsonlite"))
install.packages("duckdb")   # optional — for SQL queries
install.packages("remotes")

# If "destination file exists", uncomment:
# remove.packages("fabriconnect")

remotes::install_github("AKU-CDIO/fabric-inbound-access", subdir = "fabriconnect",
                        upgrade = "always", force = TRUE)
```

## Functions

| Function | Description |
|----------|-------------|
| `connect_to_fabric()` | Authenticate and return a connection object |
| `list_tables(conn)` | List all user tables in the Lakehouse |
| `read_table(conn, name, columns = NULL)` | Read a table as data.frame (columns prunes large tables) |
| `query_tables(conn, sql, table_columns = NULL)` | Run SQL across tables via DuckDB |
| `list_lakehouses()` | Discover all Lakehouses in the workspace |

## Usage

```r
library(fabriconnect)
conn <- connect_to_fabric()

# Read all columns
df <- read_table(conn, "dimenrolledparticipants")

# Read only needed columns (less network/memory)
df <- read_table(conn, "factfitbitsleeplogs",
                 columns = c("ParticipantKey", "MinutesAsleep"))

# SQL with column pruning for large tables
result <- query_tables(conn, "
    SELECT p.ParticipantIdentifier, count(s.Skey) AS n
    FROM dimenrolledparticipants p
    JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
    GROUP BY p.ParticipantIdentifier",
  table_columns = list(
    dimenrolledparticipants = c("Skey", "ParticipantIdentifier"),
    factfitbitsleeplogs     = c("Skey", "ParticipantKey")
  ))

# Discover and connect by name
lakes <- list_lakehouses()
conn2 <- connect_to_fabric(lakehouse = "HCW_fitbit_data")
```

## Configuration

IDs are in `inst/config.json` and loaded automatically. Override:

```r
conn <- connect_to_fabric(
    workspace_id   = "your-workspace-guid",
    lakehouse_id   = "your-lakehouse-guid",
    lakehouse      = "HCW_fitbit_data",
    fabric_tenant  = "your-tenant-id"
)
```

## Large tables

- Use `columns =` to select only the columns you need — data is pruned at the parquet level
- Temp files are deleted before each `read_table()` call (no accumulation)
- For >100 GB prefer Python's `deltalake` which reads directly from OneLake (no disk)
