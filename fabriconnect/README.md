# fabriconnect — R package

Read Delta tables from Microsoft Fabric Lakehouses via the OneLake HTTPS API.
Supports listing, reading, and SQL queries via DuckDB.

## Install

```r
install.packages(c("AzureStor", "arrow", "DBI"))
install.packages("duckdb")   # optional — for SQL queries
install.packages("fabriconnect/", repos = NULL, type = "source")
```

## Functions

| Function | Description |
|----------|-------------|
| `connect_to_fabric()` | Authenticate and return a connection object |
| `list_tables(conn)` | List all user tables in the Lakehouse |
| `read_table(conn, name)` | Read a table as data.frame |
| `query_tables(conn, sql)` | Run SQL across tables via DuckDB |

## Usage

```r
library(fabriconnect)
conn <- connect_to_fabric()

# List tables
tables <- list_tables(conn)

# Read a table
df <- read_table(conn, "dimenrolledparticipants")

# SQL with JOIN
result <- query_tables(conn, "
    SELECT p.ParticipantIdentifier, count(s.Skey) AS n
    FROM dimenrolledparticipants p
    JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
    GROUP BY p.ParticipantIdentifier
")
```

## Configuration

```r
conn <- connect_to_fabric(
    workspace_id  = "your-workspace-guid",
    lakehouse_id  = "your-lakehouse-guid",
    fabric_tenant = "your-tenant-id"
)
```

## How it works

1. Calls `az.cmd` to get an OAuth2 token for `https://storage.azure.com`
2. Uses `AzureStor` to connect to OneLake's ADLS Gen2 endpoint
3. Downloads parquet files and reads them with `arrow::read_parquet()`
4. For SQL: loads tables into DuckDB in-memory

No ODBC/TDS needed — all traffic is HTTPS (port 443).
