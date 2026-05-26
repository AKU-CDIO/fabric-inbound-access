# fabriconnect — R package for Microsoft Fabric Lakehouse

Read Fabric Lakehouse data over HTTPS (port 443). No TDS (port 1433) needed.

**Author:** CDIO, AKU — Derick Imbati (derick.imbati@aku.edu)  
**License:** Apache 2.0

## Install

```r
remotes::install_github("AKU-CDIO/fabric-inbound-access", subdir = "fabriconnect", force = TRUE, upgrade_dependencies = FALSE)
```

## Update

Restart R first, then run the install command again. Or:

```r
library(fabriconnect)
update_fabriconnect()
```

## Connect

```r
library(fabriconnect)

# Default Lakehouse (uzima_db_backup)
conn <- connect_to_fabric()

# Or connect by name
conn <- connect_to_fabric(lakehouse = "HCW_fitbit_data")
```

## List tables

```r
list_tables(conn)
```

## Read data

```r
# All columns
read_table(conn, "dimenrolledparticipants")

# Specific columns (less transfer)
read_table(conn, "dimenrolledparticipants",
           columns = c("ParticipantIdentifier", "Gender"))
```

## SQL with DuckDB (optional)

```r
query_tables(conn, "SELECT count(*) FROM dimenrolledparticipants")

# JOIN with column pruning
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

## All Lakehouses

```r
list_lakehouses()
```

## Override defaults

```r
connect_to_fabric(
  workspace_id  = "your-workspace-guid",
  lakehouse     = "HCW_fitbit_data",
  fabric_tenant = "your-tenant-id"
)
```
