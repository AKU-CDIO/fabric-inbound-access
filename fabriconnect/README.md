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

### AKU researchers
```r
library(fabriconnect)

# Default Lakehouse (uzima_db_backup)
conn <- connect_to_fabric()

# Or connect by name
conn <- connect_to_fabric(lakehouse = "HCW_fitbit_data")
```

### External researchers (delegated token)
Approved external collaborators (e.g. University of Michigan) use an admin-provisioned token via an Azure Automation webhook.

**One-time setup — set your email:**
```bash
setx FABRIC_RESEARCHER_EMAIL your.email@umich.edu
```

Then connect as normal:
```r
library(fabriconnect)
conn <- connect_to_fabric()   # Authenticated as your.email@umich.edu
list_tables(conn)
read_table(conn, "dimenrolledparticipants")
```

The `FABRIC_WEBHOOK_URL` is pre-configured in the package. If you need to set it manually:
```bash
setx FABRIC_WEBHOOK_URL https://a28ba9ca-fccc-4d71-8568-1d6340b357d7.webhook.ne.azure-automation.net/webhooks?token=UIVQO89cW8jEi0CMiTp2XFVC4kArToEMjI8HZBPsSlk%3d
```

### External researchers (service principal via Key Vault)

Approved researchers can connect from personal laptops using Azure AD/MFA and Azure Key Vault. On first connect, R opens a browser/device-code prompt; no `az login` command is required.

```r
library(fabriconnect)
con <- connect_to_fabric_sql(auth = "sp_vault")
list_tables(con)
read_table(con, "dbo.dimenrolledparticipants")
DBI::dbDisconnect(con)
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
  SELECT p.ParticipantIdentifier, count(*) AS n
  FROM dimenrolledparticipants p
  JOIN factfitbitsleeplogs s ON p.ParticipantIdentifier = s.ParticipantIdentifier
  GROUP BY p.ParticipantIdentifier",
  table_columns = list(
    dimenrolledparticipants = c("ParticipantIdentifier"),
    factfitbitsleeplogs     = c("ParticipantIdentifier")
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
