# UZIMA Fabric Data Access - External Researcher Guide

**Version:** 1.4
**Date:** August 2026
**Contact:** Derick Imbati - derick.imbati@aku.edu

---

## 1. What This Guide Is For

This guide is for approved external researchers who need to access UZIMA Microsoft Fabric data from a personal Windows or Mac computer.

The access flow is:

1. Open RStudio on your personal computer.
2. Install the UZIMA R package directly from GitHub.
3. Sign in interactively with your approved account.
4. The package retrieves service-principal credentials from Azure Key Vault.
5. The package connects to the Microsoft Fabric SQL endpoint.
6. You list tables, read tables, or run read-only SQL queries.
7. You close the connection when finished.

You do not need to run `az login`. You should not save or paste service-principal credentials anywhere.

## 2. Before You Start

Confirm these items before installing the package.

### Account Access

You need an approved account that has been added to the AKU Azure tenant and granted access to the UZIMA Key Vault.

The Key Vault sign-in tenant is:

```text
4fde8ff3-4dd5-42e1-a25a-e42905610d66
```

### Software

You need:

- R 4.1 or later
- RStudio
- Microsoft ODBC Driver 18 for SQL Server
- Internet access

Mac users also need `unixODBC`.

Install it with Homebrew:

```bash
brew install unixodbc
```

## 3. Install The R Package

Open RStudio.

In the Console, run these lines once:

```r
install.packages(c("DBI", "odbc", "httr", "jsonlite", "dplyr", "remotes"))

remotes::install_github(
  "AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect",
  force = TRUE,
  upgrade_dependencies = FALSE
)
```

Restart RStudio after installation.

Then confirm the package version:

```r
library(fabriconnect)
packageVersion("fabriconnect")
```

Expected version:

```text
0.1.1
```

## 4. Connect To The Default UZIMA Lakehouse

The default database/lakehouse is:

```text
uzima_db_backup
```

Run this in RStudio:

```r
library(fabriconnect)

con <- connect_to_fabric_sql(auth = "sp_vault")
```

A Microsoft sign-in page should open. Complete the sign-in with your approved account and complete MFA.

If the browser does not open automatically, RStudio will print a device-code message similar to this:

```text
SIGN IN REQUIRED
Open: https://login.microsoft.com/device
Code: XXXXXXXX
```

Open the printed URL in your browser and enter the printed code.

Keep the same `con` object open while you work. Do not call `connect_to_fabric_sql()` again for every table or query, because that can ask you to authenticate again.

## 5. List Available Tables

After the connection succeeds, list the tables:

```r
tables <- list_tables(con)
print(tables)
```

Table names may include a schema such as `dbo`. Use the full name when reading a table, for example `dbo.dimenrolledparticipants`.

## 6. Read A Small Table Sample

Start with a small sample before loading a large table.

```r
participants <- read_table(
  con,
  "dbo.dimenrolledparticipants",
  columns = c("ParticipantIdentifier", "Gender", "Age")
)

print(head(participants))
```

## 7. Run A Read-Only SQL Query

Use `query_tables()` for SQL queries.

```r
participant_count <- query_tables(
  con,
  "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants"
)

print(participant_count)
```

Only read-only `SELECT` queries are allowed by the package helpers.

## 8. Work With Large Tables Safely

For large tables, select only the columns you need and filter before loading data into R.

```r
fitbit_sample <- query_tables(con, "
  SELECT TOP 100
    ParticipantIdentifier,
    date,
    steps
  FROM dbo.factfitbitdailydata
  WHERE date >= '2023-01-01'
")

print(head(fitbit_sample))
```

## 9. Connect To A Different Lakehouse Or Database

Use the `database` argument when you need a different lakehouse/database.

Available options include:

| Database | Use For |
|---|---|
| `uzima_db_backup` | Main UZIMA data, participants, surveys, Fitbit facts |
| `HCW_fitbit_data` | HCW Fitbit daily data, activity logs, sleep logs, devices, profiles |
| `Qualtrics` | Qualtrics survey response data |

Close the current connection before switching to a different database.

```r
DBI::dbDisconnect(con)
```

### Connect To `HCW_fitbit_data`

```r
library(fabriconnect)

con <- connect_to_fabric_sql(database = "HCW_fitbit_data", auth = "sp_vault")

tables <- list_tables(con)
print(tables)

sleep_sample <- query_tables(con, "
  SELECT TOP 100
    participantidentifier,
    date,
    totalsleepminutes,
    efficiency
  FROM dbo.fitbitsleeplogdetails
  WHERE totalsleepminutes > 0
")

print(head(sleep_sample))

DBI::dbDisconnect(con)
```

### Connect To `Qualtrics`

```r
library(fabriconnect)

con <- connect_to_fabric_sql(database = "Qualtrics", auth = "sp_vault")

tables <- list_tables(con)
print(tables)

survey_sample <- query_tables(con, "
  SELECT TOP 100 *
  FROM dbo.aku_survey_responses_2026
")

print(head(survey_sample))

DBI::dbDisconnect(con)
```

### Return To The Default UZIMA Database

```r
library(fabriconnect)

con <- connect_to_fabric_sql(auth = "sp_vault")

tables <- list_tables(con)
print(tables)

DBI::dbDisconnect(con)
```

## 10. Single RStudio Test Block

Use this single R Markdown chunk to test installation, interactive Key Vault sign-in, table listing, table reading, and a read-only SQL query.

```{r echo=TRUE}
#install.packages(c("DBI", "odbc", "httr", "jsonlite", "dplyr", "remotes"))
remotes::install_github("AKU-CDIO/fabric-inbound-access", subdir = "fabriconnect", force = TRUE, upgrade_dependencies = FALSE)

library(fabriconnect)

con <- connect_to_fabric_sql(auth = "sp_vault")

tables <- list_tables(con)
print(tables)

df <- read_table(con, "dbo.dimenrolledparticipants", columns = c("ParticipantIdentifier", "Gender", "Age"))
print(head(df))

summary <- query_tables(con, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants")
print(summary)

#DBI::dbDisconnect(con)
```

When you are done testing, close the connection:

```r
DBI::dbDisconnect(con)
```

## 11. Important Working Rules

- Connect once at the start of your script.
- Reuse the same `con` object for all reads and queries.
- Disconnect once at the end with `DBI::dbDisconnect(con)`.
- Do not call `connect_to_fabric_sql()` before every query.
- Do not print, save, or share Key Vault secret values.
- Do not put service-principal credentials in notebooks or scripts.
- Use selected columns, `TOP`, and `WHERE` filters for large tables.

## 12. Troubleshooting

### `unused argument (keyvault_auth_method = ...)`

RStudio is using an old loaded version of `fabriconnect`.

Restart RStudio and reinstall from GitHub:

```r
remove.packages("fabriconnect")

install.packages(c("DBI", "odbc", "httr", "jsonlite", "dplyr", "remotes"))

remotes::install_github(
  "AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect",
  force = TRUE,
  upgrade_dependencies = FALSE
)

library(fabriconnect)
packageVersion("fabriconnect")
```

Expected version:

```text
0.1.1
```

Then connect with the simple call:

```r
con <- connect_to_fabric_sql(auth = "sp_vault")
```

### Browser Login Does Not Open

Copy the printed `https://login.microsoft.com/device` URL into your browser and enter the printed code.

### Microsoft Authenticator Shows No Code

This is usually an account, tenant, or MFA provisioning issue rather than a Mac or RStudio issue.

Ask the AKU admin to confirm:

- Your account exists in the AKU tenant.
- Your account can complete MFA for tenant `4fde8ff3-4dd5-42e1-a25a-e42905610d66`.
- Your MFA method is allowed by Conditional Access.
- Your account has Key Vault access.

### Key Vault Forbidden

Ask the admin to confirm you have the `Key Vault Secrets User` role on the UZIMA Key Vault.

### ODBC Driver Error

Install Microsoft ODBC Driver 18 for SQL Server.

Mac users should also install `unixODBC`:

```bash
brew install unixodbc
```

### Fabric SQL Login Fails

Ask the admin to confirm the service principal has read access to the required Fabric workspace and lakehouse/database.

### A Table Name Fails

Run `list_tables(con)` first and copy the exact table name from the output. If the table includes `dbo.`, include `dbo.` in your query or `read_table()` call.

## 13. Security Notes

The package includes these guardrails:

- It does not print Key Vault secret values.
- It retrieves service-principal values at runtime.
- It does not ask researchers to put credentials in notebooks.
- It sets `ApplicationIntent=ReadOnly` on the SQL connection.
- It blocks non-SELECT statements in `query_tables()`.

These package guardrails do not replace Azure/Fabric permissions. Admins must still enforce read-only Fabric access, rotate the service-principal secret before expiry, and review Key Vault audit logs.

---

*Document version 1.4 - August 2026*