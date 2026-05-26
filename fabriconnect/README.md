# fabriconnect — R package

Read Delta tables from Microsoft Fabric Lakehouses via the OneLake HTTPS API.

## Install

```r
# Dependencies
install.packages(c("AzureStor", "arrow"))

# fabriconnect from source
install.packages("fabriconnect/", repos = NULL, type = "source")
```

## Usage

```r
library(fabriconnect)

# Connect (uses Azure CLI for authentication)
conn <- connect_to_fabric()

# List tables
tables <- list_tables(conn)

# Read a table
df <- read_table(conn, "factfitbitdailydata")
head(df)
```

## Functions

| Function | Description |
|----------|-------------|
| `connect_to_fabric(workspace_id, lakehouse_id, fabric_tenant)` | Authenticates and returns a connection object |
| `list_tables(conn)` | Returns all user table names in the Lakehouse |
| `read_table(conn, table_name)` | Downloads parquet files and returns a data.frame |

## Parameters

All have sensible defaults for the `uzima_db_backup` Lakehouse:

| Parameter | Default |
|-----------|---------|
| `workspace_id` | `67f69cc9-00c9-4c9c-a85b-38fc30774b7b` |
| `lakehouse_id` | `67596566-8ea9-4fd6-a451-ca9654aa4f10` |
| `fabric_tenant` | `a5d4252a-02f9-4e60-96f0-9733baae4919` |

Override them to connect to other Lakehouses:

```r
conn <- connect_to_fabric(
  workspace_id = "your-workspace-guid",
  lakehouse_id = "your-lakehouse-guid",
  fabric_tenant = "your-tenant-id"
)
```

## How it works

1. Calls `az.cmd` to get an OAuth2 token for `https://storage.azure.com`
2. Uses `AzureStor` to connect to OneLake's ADLS Gen2 endpoint
3. Lists Delta table directories and downloads parquet files
4. Reads parquet files with `arrow::read_parquet()`

No ODBC/TDS needed — all traffic is HTTPS (port 443).
