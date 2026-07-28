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

For approved researchers on personal laptops, use the Key Vault service-principal SQL flow. Install Python into a dedicated `.venv`; do not install into Anaconda `base` or another shared environment.

Windows PowerShell install:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
```

macOS/Linux install:

```bash
python3 -m venv .venv
./.venv/bin/python -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
```

Python usage: authenticate once, reuse the same `conn` for all reads/queries, and close it once at the end.

```python
from fabricpy import connect_to_fabric_sql, list_sql_tables, query_sql, read_sql_table

conn = connect_to_fabric_sql()
try:
    tables = list_sql_tables(conn)
    print(tables[:10])

    df = read_sql_table(conn, "dbo.dimenrolledparticipants", top=10)
    print(df.head())

    summary = query_sql(conn, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants")
    print(summary)
finally:
    conn.close()
```

R usage follows the same pattern: connect once, run all reads/queries, then disconnect once.

```r
library(fabriconnect)
con <- connect_to_fabric_sql()
tryCatch({
  list_tables(con)
  read_table(con, "dbo.dimenrolledparticipants")
  query_tables(con, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants")
}, finally = {
  DBI::dbDisconnect(con)
})
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

For **external researchers** outside the approved VM, use `auth = "sp_vault"`.

**Works on Windows, Mac, and Linux.** On first connect, Python uses one device-code prompt to access Key Vault. Browser login is opt-in only.

### Prerequisites

1. **R packages** — `processx` (installed automatically)
2. **Windows only:** Azure CLI + ODBC Driver 18 (for full SQL access)
3. **Mac / Linux:** No extra installs needed

### Step 1: Connect

```r
library(fabriconnect)

# Default database (uzima_db_backup)
conn <- connect_to_fabric(auth = "sp_vault")

# Or specify a different database
conn <- connect_to_fabric(auth = "sp_vault", lakehouse_name = "HCW_fitbit_data")
conn <- connect_to_fabric(auth = "sp_vault", database = "Qualtrics")
```

### Step 2: List Tables

```r
tables <- list_tables(conn)
tables
#  [1] "dimenrolledparticipants"    "factfitbitsleeplogs"
#  [3] "dimsurveyresults"           "dimsurveydictionary"
#  ...
```

### Step 3: Read Data

```r
# Full table (small tables only)
df <- read_table(conn, "dimenrolledparticipants")
head(df)

# Large tables — use SQL LIMIT
df <- DBI::dbGetQuery(conn, "SELECT TOP 100 * FROM fitbitdailydata")

# Specific columns only
df <- DBI::dbGetQuery(conn, "
  SELECT participantidentifier, date, steps, calories
  FROM fitbitdailydata
")

# Filtered
df <- DBI::dbGetQuery(conn, "
  SELECT * FROM dimenrolledparticipants
  WHERE Gender = 'Female'
")
```

### Step 4: SQL Queries

```r
# Count rows
DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM dimenrolledparticipants")

# Aggregation
DBI::dbGetQuery(conn, "
  SELECT Gender, COUNT(*) AS n
  FROM dimenrolledparticipants
  GROUP BY Gender
")

# Cross-database join (SP connection only)
conn_hcw <- connect_to_fabric(auth = "sp_vault", lakehouse_name = "HCW_fitbit_data")
df <- DBI::dbGetQuery(conn_hcw, "
  SELECT p.ParticipantIdentifier, f.date, f.steps
  FROM uzima_db_backup.dbo.dimenrolledparticipants p
  JOIN HCW_fitbit_data.dbo.fitbitdailydata f
    ON p.ParticipantIdentifier = f.participantidentifier
")
```

### Step 5: Disconnect

```r
DBI::dbDisconnect(conn)
```

### Complete Examples

**Example 1: Participant demographics**

```r
library(fabriconnect)
conn <- connect_to_fabric(auth = "sp_vault")

df <- DBI::dbGetQuery(conn, "
  SELECT ParticipantIdentifier, Gender, DateOfBirth, PostalCode
  FROM dimenrolledparticipants
  WHERE Gender IS NOT NULL
")

summary(df)
table(df$Gender)
```

**Example 2: Fitbit sleep analysis**

```r
conn <- connect_to_fabric(auth = "sp_vault", lakehouse_name = "HCW_fitbit_data")

sleep <- DBI::dbGetQuery(conn, "
  SELECT participantidentifier, date, totalsleepminutes, efficiency
  FROM fitbitsleeplogdetails
  WHERE totalsleepminutes > 0
")

hist(sleep$totalsleepminutes, breaks = 30,
     main = "Sleep Duration Distribution",
     xlab = "Minutes")
```

**Example 3: Survey responses**

```r
conn <- connect_to_fabric(auth = "sp_vault", database = "Qualtrics")

surveys <- DBI::dbGetQuery(conn, "
  SELECT TOP 100 *
  FROM dbo.aku_survey_responses_2026
")

names(surveys)
```

**Example 4: Join participants with Fitbit data**

```r
conn <- connect_to_fabric(auth = "sp_vault")

# Get participant list
participants <- DBI::dbGetQuery(conn, "
  SELECT ParticipantIdentifier, Gender
  FROM dimenrolledparticipants
")

# Get step counts
steps <- DBI::dbGetQuery(conn, "
  SELECT participantidentifier, SUM(steps) AS total_steps
  FROM factfitbitdailydata
  GROUP BY participantidentifier
")

# Merge
df <- merge(participants, steps, by.x = "ParticipantIdentifier",
            by.y = "participantidentifier", all.x = TRUE)

head(df)
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
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
```

> **Note:** For personal laptops, install Python into a dedicated `.venv`; do not install into Anaconda `base`. On the approved VM, both packages are pre-installed and pre-configured.

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

Read only the columns you need with the `columns` parameter. This reduces memory and speeds up analysis.

```r
# Option 1: columns parameter (OneLake)
df <- read_table(conn, "fitbitdailydata",
                 columns = c("participantidentifier", "date", "steps"))

# Option 2: SQL LIMIT (Windows: sp_vault)
df <- DBI::dbGetQuery(conn, "SELECT TOP 1000 * FROM fitbitdailydata")

# Option 3: SQL WHERE filter (Windows: sp_vault)
df <- DBI::dbGetQuery(conn, "
  SELECT participantidentifier, date, steps
  FROM fitbitdailydata
  WHERE participantidentifier = 'P-AKU-11-22'
")
```

### list_tables shows a schema name (e.g. "dbo")

Use the full dotted name: `read_table(conn, "dbo.aku_survey_responses_2026")`.

### az login fails

```bash
# Windows — use full path
"C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd" login

# Or if az is in PATH
az login
```

### Mac: sp_vault auth prompts for device code

This is expected. On first connect, Python prints one device-code prompt for Key Vault. The SP credentials are then used to access Fabric. If you see browser login followed by device code, update the package and make sure FABRIC_KEYVAULT_AUTH_METHOD is not set to `auto`.

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
