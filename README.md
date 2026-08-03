# UZIMA Fabric Data Access

Access UZIMA study data from Microsoft Fabric on the approved VM â€” **no login, no setup needed**.

**Data access is VM-only.** Fabric inbound access restrictions ensure data can only be read from the approved VM (`uzima`).

## Quick Start

**R / RStudio** â€” just paste this in any R Markdown chunk:

```r
library(fabriconnect)
conn <- connect_to_fabric()
tables <- list_tables(conn)
df <- read_table(conn, "registeredparticipants")
```

**Python** â€” in a terminal or notebook:

```python
from fabricpy import FabricLakehouse
lh = FabricLakehouse()
tables = lh.list_tables()
df = lh.read_table("agents").to_pandas()
```

That's it. No sign-in, no tokens, no env vars. See [`UZIMA_Instructions.docx`](UZIMA_Instructions.docx) for a printable quick-start guide.

## Available Lakehouses

| Lakehouse | Tables | Description |
|---|---|---|
| `uzima_db_backup` | 31 | Primary â€” Fitbit, surveys, participants, agents |
| `HCW_fitbit_data` | 5 | fitbitactivitylogs, fitbitdailydata, fitbitdevices, etc. |
| `Qualtrics` | 1 | `dbo.aku_survey_responses_2026` (256 columns) |

Default is `uzima_db_backup`. To use another:

```r
conn <- connect_to_fabric(lakehouse = "HCW_fitbit_data")
```

```python
lh = FabricLakehouse(lakehouse="HCW_fitbit_data")
# or by GUID:
lh = FabricLakehouse(lakehouse_guid="65058b40-a60c-4267-a882-9263e0ba0617")
```

## Read Only Selected Columns

Recommended for large tables.

```r
df <- read_table(conn, "dimenrolledparticipants",
                 columns = c("ParticipantIdentifier", "Gender", "Age"))
```

```python
df = lh.read_table("dimenrolledparticipants",
                   columns=["ParticipantIdentifier", "Gender", "Age"]).to_pandas()
```

## SQL Queries

```r
query_tables(conn, "SELECT COUNT(*) FROM dimenrolledparticipants")
```

```python
lh.sql("SELECT COUNT(*) FROM dimenrolledparticipants")
```

Cross-lakehouse:

```python
uzima = FabricLakehouse(lakehouse="uzima_db_backup")
hcw = FabricLakehouse(lakehouse="HCW_fitbit_data")

FabricLakehouse.cross_query(
  {"uzima": uzima, "hcw": hcw},
  "SELECT p.ParticipantIdentifier, f.StepCount
   FROM uzima.dimenrolledparticipants p
   JOIN hcw.fitbitdailydata f ON p.ParticipantIdentifier = f.Id"
)
```

## Service Principal Access via Key Vault

For approved researchers on personal laptops, use the Key Vault service-principal SQL flow. Install the Python package directly with pip into your Python user site; no virtual environment is required.

Windows PowerShell install:

```powershell
py -3 -m pip install --user "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --upgrade --no-cache-dir
```

macOS/Linux install:

```bash
python3 -m pip install --user "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --upgrade --no-cache-dir
```

Python usage: authenticate once, reuse the same `conn` for all reads/queries, and close it once at the end.

```python
from fabricpy import connect_to_fabric_sql, list_sql_tables, query_sql, read_sql_table

conn = connect_to_fabric_sql()

tables = list_sql_tables(conn)
print(tables[:10])

df = read_sql_table(conn, "dbo.dimenrolledparticipants", top=10)
print(df.head())

summary = query_sql(conn, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants")
print(summary)

conn.close()
```

R usage follows the same pattern: connect once, run all reads/queries, then disconnect once.

```r
library(fabriconnect)
con <- connect_to_fabric_sql(auth = "sp_vault")
list_tables(con)
read_table(con, "dbo.dimenrolledparticipants")
query_tables(con, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants")
DBI::dbDisconnect(con)
```

See [docs/FABRIC_SP_ACCESS_SETUP.md](docs/FABRIC_SP_ACCESS_SETUP.md) for setup, admin RBAC, and troubleshooting.

## How Authentication Works (for reference)

1. An admin authenticates once to the Fabric tenant via device code
2. Tokens are AES-encrypted and stored on the VM, bound to the machine's hardware key
3. R and Python packages decrypt them on-the-fly via PowerShell â€” no credentials touch the network
4. An Azure Automation runbook refreshes the tokens in the cloud every 50 minutes
5. As a fallback, the webhook path works via `az rest` if the Azure CLI is signed in

Researchers never need to authenticate. All steps happen automatically in the background.

## External Access (SP via Key Vault)

For **external researchers** outside the approved VM, use the Key Vault service-principal SQL flow.

**Works on Windows and Mac.** On first connect, R opens an interactive browser/device-code prompt for Key Vault login. No `az login` command is required.

### Prerequisites

1. **R packages** - installed by the setup command below
2. **Microsoft ODBC Driver 18 for SQL Server**
3. **Mac only:** `unixODBC`

### Step 1: Install

```r
install.packages(c("DBI", "odbc", "httr", "jsonlite", "dplyr", "remotes"))
remotes::install_github(
  "AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect",
  force = TRUE,
  upgrade_dependencies = FALSE
)
```

### Step 2: Connect

```r
library(fabriconnect)

con <- connect_to_fabric_sql(auth = "sp_vault")
```

### Step 3: List Tables

```r
tables <- list_tables(con)
print(tables)
```

### Step 4: Read Data

```r
df <- read_table(con, "dbo.dimenrolledparticipants", columns = c("ParticipantIdentifier", "Gender", "Age"))
print(head(df))
```

### Step 5: SQL Queries

```r
summary <- query_tables(con, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants")
print(summary)

by_gender <- query_tables(con, "
  SELECT Gender, COUNT(*) AS total
  FROM dbo.dimenrolledparticipants
  GROUP BY Gender
")
print(by_gender)
```

### Step 6: Disconnect

```r
DBI::dbDisconnect(con)
```

### Complete Examples

**Example 1: Participant demographics**

```r
library(fabriconnect)
con <- connect_to_fabric_sql(auth = "sp_vault")

df <- query_tables(con, "
  SELECT ParticipantIdentifier, Gender, DateOfBirth, PostalCode
  FROM dbo.dimenrolledparticipants
  WHERE Gender IS NOT NULL
")

summary(df)
table(df$Gender)
DBI::dbDisconnect(con)
```

**Example 2: Fitbit sleep analysis**

```r
library(fabriconnect)
con <- connect_to_fabric_sql(database = "HCW_fitbit_data", auth = "sp_vault")

sleep <- query_tables(con, "
  SELECT participantidentifier, date, totalsleepminutes, efficiency
  FROM dbo.fitbitsleeplogdetails
  WHERE totalsleepminutes > 0
")

summary(sleep$totalsleepminutes)
DBI::dbDisconnect(con)
```

**Example 3: Qualtrics survey data**

```r
library(fabriconnect)
con <- connect_to_fabric_sql(database = "Qualtrics", auth = "sp_vault")

surveys <- query_tables(con, "
  SELECT TOP 100 *
  FROM dbo.aku_survey_responses_2026
")

head(surveys)
DBI::dbDisconnect(con)
```

**Example 4: Join tables**

```r
library(fabriconnect)
con <- connect_to_fabric_sql(auth = "sp_vault")

joined <- query_tables(con, "
  SELECT p.ParticipantIdentifier, p.Gender, f.date, f.steps
  FROM dbo.dimenrolledparticipants p
  JOIN dbo.factfitbitdailydata f
    ON p.ParticipantIdentifier = f.participantidentifier
")

head(joined)
DBI::dbDisconnect(con)
```

## Architecture

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”     â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚  Azure Automation     â”‚â”€â”€â”€â”€â–¶â”‚  Key Vault       â”‚
â”‚  (refresh every 50m)  â”‚     â”‚  (encrypted      â”‚
â”‚                       â”‚     â”‚   master token)  â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜     â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
           â”‚
           â–¼
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚  Approved VM (uzima)                              â”‚
â”‚  â”œâ”€â”€ C:\ProgramData\UZIMA\FabricTokenBroker\      â”‚
â”‚  â”‚   â”œâ”€â”€ access-token.enc   (AES, machine-bound)  â”‚
â”‚  â”‚   â”œâ”€â”€ refresh-token.enc                         â”‚
â”‚  â”‚   â”œâ”€â”€ get-token.ps1      (decrypt helper)      â”‚
â”‚  â”‚   â”œâ”€â”€ researchers.json   (email whitelist)     â”‚
â”‚  â”‚   â””â”€â”€ fabriconnect-patch.R                     â”‚
â”‚  â”œâ”€â”€ R:  fabriconnect (auto-config via Rprofile)  â”‚
â”‚  â””â”€â”€ Python: fabricpy (auto via _try_local_token) â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

## Install

### R

```r
remotes::install_github(
  "AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect",
  force = TRUE,
  upgrade_dependencies = FALSE
)
```

### Python

```bash
py -3 -m pip install --user "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --upgrade --no-cache-dir
```

> **Note:** On the approved VM, both packages are pre-installed and pre-configured.

## For Administrators

See [Runbooks/README.md](Runbooks/README.md) for deploying the token broker system:

- `deploy-token-broker.ps1 -Mode LocalVM` â€” initial setup (admin device-code auth)
- `deploy-token-broker.ps1 -Mode AzureAutomation` â€” cloud refresh setup
- `vm-token-client.ps1` / `vm-token-client-local.ps1` â€” client utilities
- `C:\ProgramData\UZIMA\FabricTokenBroker\researchers.json` â€” manage approved researcher emails

## Common Issues

### I cannot connect from my laptop

Expected. Fabric inbound access is restricted to the approved VM (`uzima`).

Use `auth = "sp_vault"` for external access (works on Windows, Mac, and Linux).

### I get "No authentication method available"

Run the test script to verify: `python test_delegated_access.py` or `source("Runbooks/test-r-access.R")` in RStudio. If it fails, contact the admin to re-deploy the token broker.

### A table is very large

Read only the columns you need and filter in SQL before loading data into R. This reduces memory and speeds up analysis.

```r
# Selected columns
small <- read_table(con, "dbo.factfitbitdailydata", columns = c("participantidentifier", "date", "steps"))

# SQL TOP limit
limited <- query_tables(con, "SELECT TOP 1000 participantidentifier, date, steps FROM dbo.factfitbitdailydata")

# SQL WHERE filter
filtered <- query_tables(con, "
  SELECT participantidentifier, date, steps
  FROM dbo.factfitbitdailydata
  WHERE participantidentifier = 'P-AKU-11-22'
")
```

### list_tables shows a schema name (e.g. "dbo")

Use the full dotted name: `read_table(conn, "dbo.aku_survey_responses_2026")`.

### Azure CLI login fails (optional VM/admin path)

```bash
# Windows — use full path
"C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd" login

# Or if az is in PATH
az login
```

### Mac: sp_vault auth opens browser/device-code prompt

This is expected. On first connect, Python opens a browser for Key Vault login; R opens a browser/device-code prompt when `keyvault_auth_method = "device_code"`. The SP credentials are then used to access Fabric.

### GitHub install fails with a rate-limit message

Wait and try again, or install with a GitHub personal access token.

### ODBC Driver not found (Windows only)

Install ODBC Driver 18 from https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server

## Table Reference

### uzima_db_backup (default)

| Table | Description |
|---|---|
| `dimenrolledparticipants` | Participant demographics (Gender, Age, PostalCode) |
| `dimsurveyresults` | Survey responses |
| `dimsurveydictionary` | Survey question definitions |
| `factfitbitdailydata` | Daily Fitbit metrics (steps, calories, sleep) |
| `factfitbitsleeplogs` | Sleep session logs |
| `factfitbitactivitieslogs` | Activity logs |
| `factfitbitrestingheartrates` | Resting heart rate readings |
| `registeredparticipants` | Registration data |
| `agents` | Research agent info |

### HCW_fitbit_data

| Table | Description |
|---|---|
| `fitbitdailydata` | Daily metrics (66 columns: steps, calories, HR, SpO2, HRV) |
| `fitbitsleeplogdetails` | Detailed sleep sessions |
| `fitbitactivitylogs` | Activity records |
| `fitbitdevices` | Device metadata |
| `fitbitprofiles` | User profiles |

### Qualtrics

| Table | Description |
|---|---|
| `dbo.aku_survey_responses_2026` | Full survey responses (256 columns) |

## Support

Contact Derick Imbati â€” derick.imbati@aku.edu

## License

Apache 2.0
