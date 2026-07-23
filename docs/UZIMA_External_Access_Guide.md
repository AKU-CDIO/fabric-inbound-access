# UZIMA Fabric Data Access — External Researcher Setup Guide

**Version:** 1.1
**Date:** July 2026
**Contact:** Derick Imbati — derick.imbati@aku.edu

---

## Overview

This guide explains how to access UZIMA study data from Microsoft Fabric on your personal computer. You can connect from **Windows** or **Mac** — no VPN or VM access required.

**What you need:**
- A Windows or Mac computer
- **R and RStudio** OR **Python and Jupyter Notebook**
- Internet connection

**Works on both platforms:**

| Language | Install | Auth |
|---|---|---|
| R | `remotes::install_github(...)` | `auth = "sp_vault"` |
| Python | `pip install ...` | `FabricLakehouse()` |

---

## Step 1: Install Prerequisites

### Option A: R and RStudio

1. Download R from: https://cran.r-project.org/bin/windows/base/ (Windows) or https://cran.r-project.org/bin/macosx/ (Mac)
2. Download RStudio from: https://posit.co/download/rstudio-desktop/
3. Install both (accept default settings)

### Option B: Python

1. Download Python from: https://www.python.org/downloads/ (Windows/Mac)
2. Or install Anaconda: https://www.anaconda.com/download
3. Open Terminal (Mac) or Command Prompt (Windows)

---

## Step 2: Install the Package

### R

Open **RStudio** and run:

```r
remotes::install_github(
  "AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect",
  force = TRUE,
  upgrade_dependencies = FALSE
)
```

If you get an error about `remotes`, install it first:

```r
install.packages("remotes")
```

### Python

Open **Terminal** (Mac) or **Command Prompt** (Windows) and run:

```bash
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall --no-cache-dir
```

---

## Step 3: Sign In to Azure

### Windows users (optional — for faster auth)

If you installed Azure CLI, open **Command Prompt** or **PowerShell** and run:

```bash
az login --tenant 4fde8ff3-4dd5-42e1-a25a-e42905610d66
```

A browser window will open. Sign in with your AKU/UMICH email address and complete the MFA process.

**Note:** You must sign in once per session. If you restart your computer, you'll need to sign in again.

### Mac users

No sign-in needed — you'll authenticate when you first connect.

---

## Step 4: Connect to Fabric

### R

```r
library(fabriconnect)

# Connect to the main database
conn <- connect_to_fabric(auth = "sp_vault")
```

### Python

```python
from fabricpy import FabricLakehouse

# Connect — opens browser for login
lh = FabricLakehouse()
```

**Note:** On first connect, a browser window will open for sign-in (device code flow). This authenticates you to Fabric.

---

## Step 5: Explore the Data

### List all tables

**R:**
```r
tables <- list_tables(conn)
tables
```

**Python:**
```python
tables = lh.list_tables()
print(tables)
```

### Read a table

**R:**
```r
# Small table — read full data
df <- read_table(conn, "dimenrolledparticipants")
head(df)

# Large table — use SQL LIMIT (Windows only)
df <- DBI::dbGetQuery(conn, "SELECT TOP 100 * FROM factfitbitdailydata")
head(df)
```

**Python:**
```python
# Small table
df = lh.read_table("dimenrolledparticipants").to_pandas()
print(df.head())

# Large table — use SQL
df = lh.sql("SELECT TOP 100 * FROM factfitbitdailydata").to_pandas()
print(df.head())
```

### Run SQL queries

**R:**
```r
# Count participants
DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM dimenrolledparticipants")

# Group by gender
DBI::dbGetQuery(conn, "
  SELECT Gender, COUNT(*) AS n
  FROM dimenrolledparticipants
  GROUP BY Gender
")
```

**Python:**
```python
# Count participants
df = lh.sql("SELECT COUNT(*) AS n FROM dimenrolledparticipants").to_pandas()
print(df)

# Group by gender
df = lh.sql("SELECT Gender, COUNT(*) AS n FROM dimenrolledparticipants GROUP BY Gender").to_pandas()
print(df)
```

---

## Step 6: Access Different Databases

### HCW Fitbit Data

**R:**
```r
conn_hcw <- connect_to_fabric(auth = "sp_vault", lakehouse_name = "HCW_fitbit_data")
tables_hcw <- list_tables(conn_hcw)
tables_hcw

df_hcw <- DBI::dbGetQuery(conn_hcw, "SELECT TOP 10 * FROM fitbitdailydata")
head(df_hcw)
```

**Python:**
```python
lh_hcw = FabricLakehouse(lakehouse="HCW_fitbit_data")
tables_hcw = lh_hcw.list_tables()
print(tables_hcw)

df_hcw = lh_hcw.sql("SELECT TOP 10 * FROM fitbitdailydata").to_pandas()
print(df_hcw.head())
```

### Qualtrics Surveys

**R:**
```r
conn_qualtrics <- connect_to_fabric(auth = "sp_vault", database = "Qualtrics")
df_surveys <- DBI::dbGetQuery(conn_qualtrics, "SELECT TOP 100 * FROM dbo.aku_survey_responses_2026")
head(df_surveys)
```

**Python:**
```python
lh_qualtrics = FabricLakehouse(lakehouse="Qualtrics")
df_surveys = lh_qualtrics.sql("SELECT TOP 100 * FROM dbo.aku_survey_responses_2026").to_pandas()
print(df_surveys.head())
```

---

## Step 7: Common Tasks

### Filter data

**R (Windows — SQL):**
```r
df <- DBI::dbGetQuery(conn, "
  SELECT ParticipantIdentifier, Gender, DateOfBirth
  FROM dimenrolledparticipants
  WHERE Gender = 'Female'
")
```

**R (Mac — R filtering):**
```r
df <- read_table(conn, "dimenrolledparticipants")
df <- df[df$Gender == "Female", ]
```

**Python:**
```python
df = lh.sql("SELECT * FROM dimenrolledparticipants WHERE Gender = 'Female'").to_pandas()
print(df.head())
```

### Select specific columns

**R (Windows — SQL):**
```r
df <- DBI::dbGetQuery(conn, "
  SELECT ParticipantIdentifier, Gender, PostalCode
  FROM dimenrolledparticipants
")
```

**R (Mac — columns parameter):**
```r
df <- read_table(conn, "dimenrolledparticipants",
                 columns = c("ParticipantIdentifier", "Gender", "PostalCode"))
```

**Python:**
```python
df = lh.read_table("dimenrolledparticipants",
                   columns=["ParticipantIdentifier", "Gender", "PostalCode"]).to_pandas()
print(df.head())
```

### Join tables

**R (Windows — SQL):**
```r
participants <- DBI::dbGetQuery(conn, "
  SELECT ParticipantIdentifier, Gender
  FROM dimenrolledparticipants
")

steps <- DBI::dbGetQuery(conn, "
  SELECT participantidentifier, SUM(steps) AS total_steps
  FROM factfitbitdailydata
  GROUP BY participantidentifier
")

df <- merge(participants, steps,
            by.x = "ParticipantIdentifier",
            by.y = "participantidentifier",
            all.x = TRUE")
head(df)
```

**R (Mac — R merge):**
```r
participants <- read_table(conn, "dimenrolledparticipants")
steps <- read_table(conn, "factfitbitdailydata")

steps_agg <- aggregate(steps ~ participantidentifier, data = steps, FUN = sum)

df <- merge(participants, steps_agg,
            by.x = "ParticipantIdentifier",
            by.y = "participantidentifier",
            all.x = TRUE")
head(df)
```

**Python:**
```python
participants = lh.read_table("dimenrolledparticipants").to_pandas()
steps = lh.read_table("factfitbitdailydata").to_pandas()

steps_agg = steps.groupby("participantidentifier")["steps"].sum().reset_index()

df = participants.merge(steps_agg,
                        left_on="ParticipantIdentifier",
                        right_on="participantidentifier",
                        how="left")
print(df.head())
```

### Cross-database join

**R (Windows — SQL only):**
```r
conn_main <- connect_to_fabric(auth = "sp_vault")
conn_hcw <- connect_to_fabric(auth = "sp_vault", lakehouse_name = "HCW_fitbit_data")

df <- DBI::dbGetQuery(conn_main, "
  SELECT p.ParticipantIdentifier, p.Gender, f.date, f.steps
  FROM uzima_db_backup.dbo.dimenrolledparticipants p
  JOIN HCW_fitbit_data.dbo.fitbitdailydata f
    ON p.ParticipantIdentifier = f.participantidentifier
")
head(df)
```

**Python:**
```python
from fabricpy import FabricLakehouse

uzima = FabricLakehouse(lakehouse="uzima_db_backup")
hcw = FabricLakehouse(lakehouse="HCW_fitbit_data")

df = FabricLakehouse.cross_query(
    {"uzima": uzima, "hcw": hcw},
    """SELECT p.ParticipantIdentifier, p.Gender, f.date, f.steps
       FROM uzima.dimenrolledparticipants p
       JOIN hcw.fitbitdailydata f
         ON p.ParticipantIdentifier = f.participantidentifier"""
).to_pandas()
print(df.head())
```

---

## Step 8: Disconnect

### R

```r
DBI::dbDisconnect(conn)
```

### Python

No explicit disconnect needed — the connection closes automatically.

---

## Available Tables

### uzima_db_backup (default)

| Table | Description |
|---|---|
| `dimenrolledparticipants` | Participant demographics |
| `dimsurveyresults` | Survey responses |
| `dimsurveydictionary` | Survey question definitions |
| `factfitbitdailydata` | Daily Fitbit metrics |
| `factfitbitsleeplogs` | Sleep session logs |
| `factfitbitactivitieslogs` | Activity logs |
| `factfitbitrestingheartrates` | Resting heart rate readings |
| `registeredparticipants` | Registration data |
| `agents` | Research agent info |

### HCW_fitbit_data

| Table | Description |
|---|---|
| `fitbitdailydata` | Daily metrics (66 columns) |
| `fitbitsleepdetails` | Detailed sleep sessions |
| `fitbitactivitylogs` | Activity records |
| `fitbitdevices` | Device metadata |
| `fitbitprofiles` | User profiles |

### Qualtrics

| Table | Description |
|---|---|
| `dbo.aku_survey_responses_2026` | Full survey responses (256 columns) |

---

## Troubleshooting

### Windows: "az: command not found"

Azure CLI is not installed or not in PATH. Reinstall from https://aka.ms/installazurecli and restart your computer.

### Windows: "ODBC Driver 18 for SQL Server not found"

Install the ODBC driver from: https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server

### Windows: "Failed to get Key Vault token"

Run `az login` again in Command Prompt or PowerShell.

### Mac/Linux: Device code auth not working

Make sure you're using the latest version of the package:

```r
# R
remotes::install_github("AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect", force = TRUE)
```

```bash
# Python
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall
```

### Both: "Failed to get Fabric token from SP credentials"

The SP credentials may be invalid. Contact the admin to verify:
- `fabric-sp-tenant-id`
- `fabric-sp-client-id`
- `fabric-sp-client-secret`

### Both: Table not found

Table names are case-insensitive. Try:

```r
# R
tables <- list_tables(conn)
grep("fitbit", tables, ignore.case = TRUE)
```

```python
# Python
tables = lh.list_tables()
print([t for t in tables if "fitbit" in t.lower()])
```

### Both: Query is slow

Large tables (like `fitbitdailydata`) may take time. Use filters:

```r
# R (Windows — SQL)
df <- DBI::dbGetQuery(conn, "
  SELECT * FROM fitbitdailydata
  WHERE participantidentifier = 'P-AKU-11-22'
  AND date >= '2023-01-01'
")
```

```python
# Python
df = lh.sql("""
  SELECT * FROM fitbitdailydata
  WHERE participantidentifier = 'P-AKU-11-22'
  AND date >= '2023-01-01'
""").to_pandas()
```

### Mac: First connect is slow

First connect may take 10-15 seconds as it authenticates to Key Vault and fetches SP credentials. Subsequent connects are faster.

---

## Quick Reference Card

### R

```r
library(fabriconnect)

# Connect
conn <- connect_to_fabric(auth = "sp_vault")
conn_hcw <- connect_to_fabric(auth = "sp_vault", lakehouse_name = "HCW_fitbit_data")

# List tables
list_tables(conn)
list_tables(conn_hcw)

# Read table
df <- read_table(conn, "dimenrolledparticipants")

# SQL query (Windows only)
df <- DBI::dbGetQuery(conn, "SELECT * FROM dimenrolledparticipants")

# Disconnect
DBI::dbDisconnect(conn)
DBI::dbDisconnect(conn_hcw)
```

### Python

```python
from fabricpy import FabricLakehouse

# Connect
lh = FabricLakehouse()
lh_hcw = FabricLakehouse(lakehouse="HCW_fitbit_data")

# List tables
print(lh.list_tables())
print(lh_hcw.list_tables())

# Read table
df = lh.read_table("dimenrolledparticipants").to_pandas()
print(df.head())

# SQL query
df = lh.sql("SELECT * FROM dimenrolledparticipants").to_pandas()
print(df.head())

# No explicit disconnect needed
```

---

## Support

If you have questions or encounter issues:

1. Check the troubleshooting section above
2. Email Derick Imbati: derick.imbati@aku.edu
3. Include the error message and what you were trying to do

---

*Document version 1.1 — July 2026*
