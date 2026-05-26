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
remotes::install_github("AKU-CDIO/fabric-inbound-access", subdir = "fabriconnect")
```

## Functions

| Function | Description |
|----------|-------------|
| `connect_to_fabric()` | Authenticate and return a connection object |
| `list_tables(conn)` | List all user tables in the Lakehouse |
| `read_table(conn, name)` | Read a table as data.frame |
| `query_tables(conn, sql)` | Run SQL across tables via DuckDB |
| `list_lakehouses()` | Discover all Lakehouses in the workspace |

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

# Discover all Lakehouses
lakes <- list_lakehouses()
print(lakes)
# Connect to a different Lakehouse
conn2 <- connect_to_fabric(lakehouse_id = lakes$id[2])
```

## Configuration

IDs are in `inst/config.json` and loaded automatically. Override:

```r
conn <- connect_to_fabric(
    workspace_id  = "your-workspace-guid",
    lakehouse_id  = "your-lakehouse-guid",
    fabric_tenant = "your-tenant-id"
)
```
