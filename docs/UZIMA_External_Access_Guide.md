# UZIMA Fabric Data Access — External Researcher Setup Guide

**Version:** 1.0
**Date:** July 2026
**Contact:** Derick Imbati — derick.imbati@aku.edu

---

## Overview

This guide explains how to access UZIMA study data from Microsoft Fabric on your personal PC. You will connect using a Service Principal (SP) stored in Azure Key Vault — no VPN, no VM access required.

**What you need:**
- A Windows PC (Windows 10 or later)
- R and RStudio installed
- Internet connection

**What you'll get:**
- Direct SQL access to UZIMA databases
- Full T-SQL support (joins, aggregations, filters)
- Read-only access to study data

---

## Step 1: Install Prerequisites

### 1.1 Install R and RStudio

If you don't have R and RStudio installed:

1. Download R from: https://cran.r-project.org/bin/windows/base/
2. Download RStudio from: https://posit.co/download/rstudio-desktop/
3. Install both (accept default settings)

### 1.2 Install Azure CLI

1. Download from: https://aka.ms/installazurecli
2. Run the installer (accept default settings)
3. Restart your computer after installation

### 1.3 Verify Azure CLI

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

Open **Command Prompt** or **PowerShell** and run:

```bash
az login
```

A browser window will open. Sign in with your AKU email address (derick.imbati@aku.edu) and complete the MFA process.

**Important:** You must sign in once per session. If you restart your computer, you'll need to sign in again.

---

## Step 4: Connect to Fabric

Open **RStudio** and run:

```r
library(fabriconnect)

# Connect to the main database
conn <- connect_to_fabric(auth = "sp_vault")
```

**Note:** The first time you run this, it may take 10-15 seconds to authenticate.

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

```r
df <- DBI::dbGetQuery(conn, "
  SELECT ParticipantIdentifier, Gender, DateOfBirth
  FROM dimenrolledparticipants
  WHERE Gender = 'Female'
")
```

### Select specific columns

```r
df <- DBI::dbGetQuery(conn, "
  SELECT ParticipantIdentifier, Gender, PostalCode
  FROM dimenrolledparticipants
")
```

### Join tables

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

### Cross-database join

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

### "az: command not found"

Azure CLI is not installed or not in PATH. Reinstall from https://aka.ms/installazurecli and restart your computer.

### "ODBC Driver 18 for SQL Server not found"

Install the ODBC driver from: https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server

### "Failed to get Key Vault token"

Run `az login` again in Command Prompt or PowerShell.

### "Environment variable is not set"

This should not happen with `auth = "sp_vault"`. If you see this, make sure you're using the correct syntax:

```r
conn <- connect_to_fabric(auth = "sp_vault")
```

### Table not found

Table names are case-insensitive. Try:

```r
tables <- list_tables(conn)
grep("fitbit", tables, ignore.case = TRUE)
```

### Query is slow

Large tables (like `fitbitdailydata`) may take time. Use SQL filters:

```r
df <- DBI::dbGetQuery(conn, "
  SELECT * FROM fitbitdailydata
  WHERE participantidentifier = 'P-AKU-11-22'
  AND date >= '2023-01-01'
")
```

---

## Quick Reference Card

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

# SQL query
df <- DBI::dbGetQuery(conn, "SELECT * FROM dimenrolledparticipants")

# Disconnect
DBI::dbDisconnect(conn)
DBI::dbDisconnect(conn_hcw)
```

---

## Support

If you have questions or encounter issues:

1. Check the troubleshooting section above
2. Email Derick Imbati: derick.imbati@aku.edu
3. Include the error message and what you were trying to do

---

*Document version 1.0 — July 2026*
