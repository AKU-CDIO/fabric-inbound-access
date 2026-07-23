# UZIMA Fabric Data Access

Access UZIMA study data from Microsoft Fabric on the approved VM — **no login, no setup needed**.

**Data access is VM-only.** Fabric inbound access restrictions ensure data can only be read from the approved VM (`uzima`).

## Quick Start

**R / RStudio** — just paste this in any R Markdown chunk:

```r
library(fabriconnect)
conn <- connect_to_fabric()
tables <- list_tables(conn)
df <- read_table(conn, "registeredparticipants")
```

**Python** — in a terminal or notebook:

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
| `uzima_db_backup` | 31 | Primary — Fitbit, surveys, participants, agents |
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

## How Authentication Works (for reference)

1. An admin authenticates once to the Fabric tenant via device code
2. Tokens are AES-encrypted and stored on the VM, bound to the machine's hardware key
3. R and Python packages decrypt them on-the-fly via PowerShell — no credentials touch the network
4. An Azure Automation runbook refreshes the tokens in the cloud every 50 minutes
5. As a fallback, the webhook path works via `az rest` if the Azure CLI is signed in

Researchers never need to authenticate. All steps happen automatically in the background.

## External Access (SP via Key Vault)

For **external researchers** outside the approved VM, use `auth = "sp_vault"`:

```r
library(fabriconnect)
conn <- connect_to_fabric(auth = "sp_vault")
list_tables(conn)
df <- read_table(conn, "dimenrolledparticipants")
```

This uses a Service Principal stored in Azure Key Vault. Requires:
- `az login` (interactive device code)
- ODBC Driver 18 for SQL Server
- R packages: `odbc`, `processx`

Works with full T-SQL (cross-database joins, `dbo.` schema, etc.):

```r
query_tables(conn, "SELECT * FROM uzima_db_backup.dbo.dimenrolledparticipants")
```

## Architecture

```
┌──────────────────────┐     ┌──────────────────┐
│  Azure Automation     │────▶│  Key Vault       │
│  (refresh every 50m)  │     │  (encrypted      │
│                       │     │   master token)  │
└──────────┬───────────┘     └──────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────┐
│  Approved VM (uzima)                              │
│  ├── C:\ProgramData\UZIMA\FabricTokenBroker\      │
│  │   ├── access-token.enc   (AES, machine-bound)  │
│  │   ├── refresh-token.enc                         │
│  │   ├── get-token.ps1      (decrypt helper)      │
│  │   ├── researchers.json   (email whitelist)     │
│  │   └── fabriconnect-patch.R                     │
│  ├── R:  fabriconnect (auto-config via Rprofile)  │
│  └── Python: fabricpy (auto via _try_local_token) │
└──────────────────────────────────────────────────┘
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
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall --no-cache-dir
```

> **Note:** On the approved VM, both packages are pre-installed and pre-configured.

## For Administrators

See [Runbooks/README.md](Runbooks/README.md) for deploying the token broker system:

- `deploy-token-broker.ps1 -Mode LocalVM` — initial setup (admin device-code auth)
- `deploy-token-broker.ps1 -Mode AzureAutomation` — cloud refresh setup
- `vm-token-client.ps1` / `vm-token-client-local.ps1` — client utilities
- `C:\ProgramData\UZIMA\FabricTokenBroker\researchers.json` — manage approved researcher emails

## Common Issues

### I cannot connect from my laptop

Expected. Fabric inbound access is restricted to the approved VM (`uzima`).

### I get "No authentication method available"

Run the test script to verify: `python test_delegated_access.py` or `source("Runbooks/test-r-access.R")` in RStudio. If it fails, contact the admin to re-deploy the token broker.

### A table is very large

Read only the columns you need with the `columns` parameter. This reduces memory and speeds up analysis.

### list_tables shows a schema name (e.g. "dbo")

Use the full dotted name: `read_table(conn, "dbo.aku_survey_responses_2026")`.

### GitHub install fails with a rate-limit message

Wait and try again, or install with a GitHub personal access token.

## Support

Contact Derick Imbati — derick.imbati@aku.edu

## License

Apache 2.0
