# UZIMA Fabric Data Access

This package helps approved researchers read UZIMA study data from Microsoft Fabric while staying inside the approved research VM.

**Data access is VM-only.** Fabric inbound access restrictions ensure data can only be read from the approved VM.

## What Researchers Can Do

- Sign in from the approved VM
- See the lakehouses and tables they have access to
- Read tables into R or Python for analysis
- Read only the columns they need
- SQL queries across tables and lakehouses

## Authentication

The package supports two authentication paths, selected automatically:

### AKU researchers (normal)

No setup needed. Call `connect_to_fabric()` — a browser opens for device-code sign-in with your @aku.edu account.

```r
library(fabriconnect)
conn <- connect_to_fabric()
```

### External researchers (delegated token)

Approved external collaborators (e.g. University of Michigan) use an admin-provisioned token via an Azure Automation webhook. **No browser sign-in, no codes to copy** — the package calls the auth service automatically.

**One-time setup — set your email:**
```bash
setx FABRIC_RESEARCHER_EMAIL your.email@umich.edu
```

Then use Python as normal — the package contacts the auth service in the background:

```python
from fabricpy import FabricLakehouse
lh = FabricLakehouse()
lh.list_tables()          # Authenticated as your.email@umich.edu
df = lh.to_pandas("dimenrolledparticipants")
```

**How it works:**
1. The package calls the Azure Automation webhook with your email
2. The runbook validates your email against the approved whitelist in Key Vault
3. Returns a short-lived Fabric access token
4. The package caches the token and refreshes it before expiry

See [Runbooks/RESEARCHER-GUIDE.md](Runbooks/RESEARCHER-GUIDE.md) for full instructions or [docs/PROCESS_FLOW.md](docs/PROCESS_FLOW.md) for the architecture diagram.

The `FABRIC_WEBHOOK_URL` is pre-configured on the VM. If you need to set it manually:

```bash
setx FABRIC_WEBHOOK_URL https://a28ba9ca-fccc-4d71-8568-1d6340b357d7.webhook.ne.azure-automation.net/webhooks?token=UIVQO89cW8jEi0CMiTp2XFVC4kArToEMjI8HZBPsSlk%3d
```

## Install in R

```r
remotes::install_github(
  "AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect",
  force = TRUE,
  upgrade_dependencies = FALSE
)
```

## Install in Python

```bash
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall --no-cache-dir
```

## First Use

Run this from the approved VM.

```r
library(fabriconnect)
conn <- connect_to_fabric()
list_tables(conn)
```

```python
from fabricpy import FabricLakehouse
lh = FabricLakehouse()
lh.list_tables()
```

## Read a Table

```r
df <- read_table(conn, "dimenrolledparticipants")
```

```python
df = lh.to_pandas("dimenrolledparticipants")
```

Tables in schemas use dot notation:

```r
list_tables(conn)                # "dbo.survey_responses_2026"
df <- read_table(conn, "dbo.survey_responses_2026")
```

```python
lh.list_tables()                 # "dbo.survey_responses_2026"
df = lh.to_pandas("dbo.survey_responses_2026")
```

## Read Only Selected Columns

Recommended for large tables.

```r
df <- read_table(
  conn, "dimenrolledparticipants",
  columns = c("ParticipantIdentifier", "Gender", "Age")
)
```

```python
df = lh.to_pandas(
  "dimenrolledparticipants",
  columns=["ParticipantIdentifier", "Gender", "Age"]
)
```

## Choose a Lakehouse

Default is `uzima_db_backup`. Available lakehouses:

- `uzima_db_backup`
- `HCW_fitbit_data`
- `Qualtrics`
- `CDIOUZIMA_Azure_Storage_Accounts_Data`
- `azu_cdiouzima`
- `LS_Fabric_Lakehouse`
- `StagingLakehouseForDataflows_20251110175852`

```r
conn <- connect_to_fabric(lakehouse = "HCW_fitbit_data")
```

```python
lh = FabricLakehouse(lakehouse="HCW_fitbit_data")
```

## SQL Queries

```r
query_tables(conn, "SELECT COUNT(*) FROM dimenrolledparticipants")
```

```python
lh.sql("SELECT COUNT(*) FROM dimenrolledparticipants")
```

Cross-lakehouse queries:

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

## Token Refresh

The package caches access tokens and refreshes them before expiry. For delegated-token mode, an Azure Automation Runbook refreshes the admin's token every 50 minutes.

## For Administrators

See [Runbooks/README.md](Runbooks/README.md) for deploying the token broker system:

- Azure Automation webhook for email/IP validation
- Key Vault for secure token storage
- Scheduled refresh every 50 minutes
- Whitelist management for external researchers

## Common Issues

### I cannot connect from my laptop

Expected. Fabric inbound access is restricted to the approved VM.

### list_tables returns table names like "dbo.survey_responses_2026"

Some lakehouses organise tables under SQL schemas (like `dbo`). Use the full dotted name when reading: `read_table(conn, "dbo.survey_responses_2026")`.

### I see a sign-in prompt

AKU researchers: sign in with your @aku.edu account. External researchers: set `FABRIC_RESEARCHER_EMAIL` first.

### I get a permission or forbidden message

Confirm your account (or webhook setup) has access to the correct workspace and lakehouse.

### A table is very large

Read only the columns you need. This reduces memory and speeds up analysis.

### GitHub install fails with a rate-limit message

Wait and try again, or install with a GitHub personal access token.

## Support

Contact the UZIMA/CDIO data team if access fails from the approved VM or if your account needs to be added.

## License

Apache 2.0
