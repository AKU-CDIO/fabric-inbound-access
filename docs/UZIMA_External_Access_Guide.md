# UZIMA Fabric Data Access — External Researcher Setup Guide

**Version:** 1.0
**Date:** July 2026
**Contact:** Derick Imbati — derick.imbati@aku.edu

---

## Overview

This guide explains how to access UZIMA study data from Microsoft Fabric on your personal computer. You can connect from **Windows** or **Mac** — no VPN or VM access required.

**What you need:**
- A Windows or Mac computer
- R and RStudio installed
- Internet connection

**One connection method for all platforms:**

Use `auth = "sp_vault"` — it works on both Windows and Mac:
- **Windows:** Uses ODBC for full SQL access
- **Mac:** Uses Fabric REST API with SP credentials

---

## Step 1: Install Prerequisites

### 1.1 Install R and RStudio

If you don't have R and RStudio installed:

1. Download R from: https://cran.r-project.org/bin/windows/base/ (Windows) or https://cran.r-project.org/bin/macosx/ (Mac)
2. Download RStudio from: https://posit.co/download/rstudio-desktop/
3. Install both (accept default settings)

### 1.2 Install Azure CLI (Windows only — optional, for faster auth)

**Windows users only:** If you want faster authentication without browser prompts:

1. Download from: https://aka.ms/installazurecli
2. Run the installer (accept default settings)
3. Restart your computer after installation

**Mac users:** Skip this step — you'll authenticate via browser on first connect.

### 1.3 Verify Azure CLI (Windows only)

Open **Command Prompt** or **PowerShell** and run:

```bash
az --version
```

You should see version information. If not, restart your computer and try again.

---

## Step 2: Install the R Package

Open **RStudio** and run this command in the Console:

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

---

## Step 3: Sign In to Azure

### Windows users (optional — for faster auth)

If you installed Azure CLI, open **Command Prompt** or **PowerShell** and run:

```bash
az login
```

A browser window will open. Sign in with your AKU email address and complete the MFA process.

**Note:** You must sign in once per session. If you restart your computer, you'll need to sign in again.

### Mac users

No sign-in needed — you'll authenticate when you first connect from R.

---

## Step 4: Connect to Fabric

### All platforms (Windows and Mac)

```r
library(fabriconnect)

# Connect to the main database
conn <- connect_to_fabric(auth = "sp_vault")
```

**Note:** On first connect, you may be prompted to sign in via browser (device code). This authenticates to Key Vault to fetch SP credentials.

---

## Step 5: Explore the Data

### List all tables

```r
tables <- list_tables(conn)
tables
```

### Read a table

```r
# Small table — read full data
df <- read_table(conn, "dimenrolledparticipants")
head(df)

# Large table — use SQL LIMIT
df <- DBI::dbGetQuery(conn, "SELECT TOP 100 * FROM factfitbitdailydata")
head(df)
```

### Run SQL queries

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

---

## Step 6: Access Different Databases

### HCW Fitbit Data

```r
conn_hcw <- connect_to_fabric(auth = "sp_vault", lakehouse_name = "HCW_fitbit_data")
tables_hcw <- list_tables(conn_hcw)
tables_hcw

df_hcw <- DBI::dbGetQuery(conn_hcw, "SELECT TOP 10 * FROM fitbitdailydata")
head(df_hcw)
```

### Qualtrics Surveys

```r
conn_qualtrics <- connect_to_fabric(auth = "sp_vault", database = "Qualtrics")
df_surveys <- DBI::dbGetQuery(conn_qualtrics, "SELECT TOP 100 * FROM dbo.aku_survey_responses_2026")
head(df_surveys)
```

---

## Step 7: Common Tasks

### Filter data

**Windows (SQL):**
```r
df <- DBI::dbGetQuery(conn, "
  SELECT ParticipantIdentifier, Gender, DateOfBirth
  FROM dimenrolledparticipants
  WHERE Gender = 'Female'
")
```

**Mac (R filtering):**
```r
df <- read_table(conn, "dimenrolledparticipants")
df <- df[df$Gender == "Female", ]
```

### Select specific columns

**Windows (SQL):**
```r
df <- DBI::dbGetQuery(conn, "
  SELECT ParticipantIdentifier, Gender, PostalCode
  FROM dimenrolledparticipants
")
```

**Mac (columns parameter):**
```r
df <- read_table(conn, "dimenrolledparticipants",
                 columns = c("ParticipantIdentifier", "Gender", "PostalCode"))
```

### Join tables (Windows: SQL)

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

### Join tables (Mac: R merge)

```r
participants <- read_table(conn, "dimenrolledparticipants")
steps <- read_table(conn, "factfitbitdailydata")

# Aggregate steps by participant
steps_agg <- aggregate(steps ~ participantidentifier, data = steps, FUN = sum)

df <- merge(participants, steps_agg,
            by.x = "ParticipantIdentifier",
            by.y = "participantidentifier",
            all.x = TRUE")
head(df)
```

### Cross-database join (Windows: SQL only)

```r
# Connect to both databases
conn_main <- connect_to_fabric(auth = "sp_vault")
conn_hcw <- connect_to_fabric(auth = "sp_vault", lakehouse_name = "HCW_fitbit_data")

# Run cross-database query
df <- DBI::dbGetQuery(conn_main, "
  SELECT p.ParticipantIdentifier, p.Gender, f.date, f.steps
  FROM uzima_db_backup.dbo.dimenrolledparticipants p
  JOIN HCW_fitbit_data.dbo.fitbitdailydata f
    ON p.ParticipantIdentifier = f.participantidentifier
")
head(df)
```

---

## Step 8: Disconnect

When you're done, always disconnect:

```r
DBI::dbDisconnect(conn)
```

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
| `fitbitsleeplogdetails` | Detailed sleep sessions |
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
remotes::install_github("AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect", force = TRUE)
```

### Both: "Failed to get Fabric token from SP credentials"

The SP credentials may be invalid. Contact the admin to verify:
- `fabric-sp-tenant-id`
- `fabric-sp-client-id`
- `fabric-sp-client-secret`

### Both: Table not found

Table names are case-insensitive. Try:

```r
tables <- list_tables(conn)
grep("fitbit", tables, ignore.case = TRUE)
```

### Both: Query is slow

Large tables (like `fitbitdailydata`) may take time. Use SQL filters (Windows) or R filtering (Mac):

```r
# Windows (SQL)
df <- DBI::dbGetQuery(conn, "
  SELECT * FROM fitbitdailydata
  WHERE participantidentifier = 'P-AKU-11-22'
  AND date >= '2023-01-01'
")

# Mac (R)
df <- read_table(conn, "fitbitdailydata")
df <- df[df$participantidentifier == "P-AKU-11-22" & df$date >= "2023-01-01", ]
```

### Mac: First connect is slow

First connect may take 10-15 seconds as it authenticates to Key Vault and fetches SP credentials. Subsequent connects are faster.

---

## Quick Reference Card

### All platforms (Windows, Mac, Linux)

```r
# Load library
library(fabriconnect)

# Connect
conn <- connect_to_fabric(auth = "sp_vault")
conn_hcw <- connect_to_fabric(auth = "sp_vault", lakehouse_name = "HCW_fitbit_data")

# List tables
list_tables(conn)
list_tables(conn_hcw)

# Read table
df <- read_table(conn, "dimenrolledparticipants")

# SQL query (Windows only — uses ODBC)
df <- DBI::dbGetQuery(conn, "SELECT * FROM dimenrolledparticipants")

# Disconnect (Windows only — ODBC connections)
DBI::dbDisconnect(conn)
DBI::dbDisconnect(conn_hcw)
```

### Windows: Full SQL access

```r
# Connect
conn <- connect_to_fabric(auth = "sp_vault")

# Cross-database query
df <- DBI::dbGetQuery(conn, "
  SELECT p.ParticipantIdentifier, f.date, f.steps
  FROM uzima_db_backup.dbo.dimenrolledparticipants p
  JOIN HCW_fitbit_data.dbo.fitbitdailydata f
    ON p.ParticipantIdentifier = f.participantidentifier
")

# Disconnect
DBI::dbDisconnect(conn)
```

### Mac: Table access via REST API

```r
# Connect
conn <- connect_to_fabric(auth = "sp_vault")

# List and read tables
tables <- list_tables(conn)
df <- read_table(conn, "dimenrolledparticipants")

# Filter in R
df <- df[df$Gender == "Female", ]
```

---

## Support

If you have questions or encounter issues:

1. Check the troubleshooting section above
2. Email Derick Imbati: derick.imbati@aku.edu
3. Include the error message and what you were trying to do

---

*Document version 1.0 — July 2026*
