# fabriconnect / fabricpy

R and Python packages for reading Microsoft Fabric Lakehouse data — from the **UZIMA study VM only**

> **Important:** Access to Fabric is restricted to the study VM only.
> See [fabric-inbound-access](https://github.com/AKU-CDIO/fabric-inbound-access.git) for the firewall configuration that enforces this.

---

## Before you start

- **Workspace access** — your Azure AD identity must have at least **Contributor**
  role on the Fabric workspace. **Viewer** role alone will **not** work (you'll get a
  `403 Forbidden` error). If your team must use Viewer, ask the workspace admin to
  enable **OneLake data access → Viewers can read OneLake data** in workspace settings.
- **Network** — you must be on the **UZIMA VM**. That's the only place the connection
  will work.
- **GitHub rate limit** — unauthenticated installs are limited to 60 requests/hour.
  If installing on a shared VM, use the ZIP install command (see Troubleshooting)
  or set a `GITHUB_PAT` environment variable.

---

## Authentication

### Interactive sign-in (default — no extra setup needed)

Just call `connect_to_fabric()` or `FabricLakehouse()` with no arguments. A browser
opens automatically — sign in with your email. MFA (Microsoft Authenticator, etc.)
is fully supported. The token is cached for the session, so you won't be prompted
again on subsequent calls.

```r
conn <- connect_to_fabric()
```

```python
lh = FabricLakehouse()
```

### Other authentication methods

If you can't use interactive sign-in (e.g., automated scripts), the package also
supports these alternatives:

**Environment variable** — for CI / headless / delegated-token access:

```bash
export FABRIC_ACCESS_TOKEN="<your-token>"
```

For delegated tokens issued to external or non-AKU-domain collaborators, use:

```bash
export FABRIC_DELEGATED_ACCESS_TOKEN="<delegated-token>"
```

The token can be either the raw JWT or `Bearer <token>`. The signed-in
identity must still be granted access to the Fabric workspace (usually as an
external/guest user in the AKU tenant).

**Pass token directly in code:**

```r
conn <- connect_to_fabric(access_token = "<your-token>")
```

```python
lh = FabricLakehouse(token = "<your-token>")
```

**Azure CLI** (advanced / legacy automation):

```bash
az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
```

---

## Installation

### R

```r
remotes::install_github("AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect", force = TRUE, upgrade_dependencies = FALSE)
```

### Python

```bash
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall --no-cache-dir
```

---

## Quick start

### Default Lakehouse (uzima_db_backup)

```r
library(fabriconnect)
conn <- connect_to_fabric()
list_tables(conn)
df <- read_table(conn, "dimenrolledparticipants")
```

```python
from fabricpy import FabricLakehouse
lh = FabricLakehouse()
lh.list_tables()
df = lh.to_pandas("dimenrolledparticipants")
```

### Connect to a specific Lakehouse

```r
conn <- connect_to_fabric(lakehouse = "HCW_fitbit_data")
list_tables(conn)
```

```python
lh = FabricLakehouse(lakehouse = "HCW_fitbit_data")
```

---

## Available Lakehouses

Seven Lakehouses in the `cdiofabric` workspace:

| Name | Contents |
|------|----------|
| `uzima_db_backup` *(default)* | 31 tables — enrolled participants, sleep logs, date dimension |
| `HCW_fitbit_data` | 5 tables — activity logs, daily data, devices |
| `Qualtrics` | Survey data |
| `CDIOUZIMA_Azure_Storage_Accounts_Data` | Azure storage metadata |
| `azu_cdiouzima` | Azure data |
| `LS_Fabric_Lakehouse` | Linked services |
| `StagingLakehouseForDataflows_20251110175852` | Dataflow staging |

Discover programmatically:

```r
list_lakehouses()
```

```python
FabricLakehouse.list_lakehouses()
```

---

## Common tasks

### Read a table

```r
df <- read_table(conn, "dimenrolledparticipants")
```

```python
df = lh.to_pandas("dimenrolledparticipants")
```

### Read only the columns you need (faster for large tables)

```r
df <- read_table(conn, "dimenrolledparticipants",
  columns = c("ParticipantIdentifier", "Gender", "Age"))
```

```python
df = lh.to_pandas("dimenrolledparticipants",
  columns = ["ParticipantIdentifier", "Gender", "Age"])
```

### Run SQL queries

Requires `duckdb` (`install.packages("duckdb")` or `pip install duckdb`).

```r
query_tables(conn, "SELECT count(*) FROM dimenrolledparticipants")
```

```python
lh.sql("SELECT count(*) FROM dimenrolledparticipants")
```

### Multi-table SQL with column pruning

```r
result <- query_tables(conn, "
  SELECT p.ParticipantIdentifier,
         COUNT(*)              AS sleep_logs,
         AVG(s.MinutesAsleep)  AS avg_min_asleep
  FROM dimenrolledparticipants p
  JOIN factfitbitsleeplogs s ON p.ParticipantIdentifier = s.ParticipantIdentifier
  GROUP BY p.ParticipantIdentifier",
  table_columns = list(
    dimenrolledparticipants = c("ParticipantIdentifier"),
    factfitbitsleeplogs     = c("ParticipantIdentifier", "MinutesAsleep")
  ))
```

```python
df = lh.sql("""
  SELECT p.ParticipantIdentifier,
         COUNT(*)              AS sleep_logs,
         AVG(s.MinutesAsleep)  AS avg_min_asleep
  FROM dimenrolledparticipants p
  JOIN factfitbitsleeplogs s ON p.ParticipantIdentifier = s.ParticipantIdentifier
  GROUP BY p.ParticipantIdentifier""",
  table_columns = {
    "dimenrolledparticipants": ["ParticipantIdentifier"],
    "factfitbitsleeplogs":     ["ParticipantIdentifier", "MinutesAsleep"]
  })
```

### Join tables across different Lakehouses

```r
conn1 <- connect_to_fabric(lakehouse = "uzima_db_backup")
conn2 <- connect_to_fabric(lakehouse = "HCW_fitbit_data")

result <- query_tables(
  list(uzima = conn1, hcw = conn2),
  "SELECT p.ParticipantIdentifier, f.ActivityDate, f.Steps
   FROM uzima.dimenrolledparticipants p
   JOIN hcw.fitbitdailydata f
     ON p.ParticipantIdentifier = f.ParticipantIdentifier
   LIMIT 10")
```

```python
lh1 = FabricLakehouse(lakehouse = "uzima_db_backup")
lh2 = FabricLakehouse(lakehouse = "HCW_fitbit_data")

result = FabricLakehouse.cross_query(
  {"uzima": lh1, "hcw": lh2},
  "SELECT p.ParticipantIdentifier, f.ActivityDate, f.Steps
   FROM uzima.dimenrolledparticipants p
   JOIN hcw.fitbitdailydata f
     ON p.ParticipantIdentifier = f.ParticipantIdentifier
   LIMIT 10")
```

### Demographics summary

```r
demo <- query_tables(conn, "
  SELECT Gender, COUNT(*) AS total, AVG(Age) AS avg_age
  FROM dimenrolledparticipants
  WHERE Gender IS NOT NULL
  GROUP BY Gender")
```

```python
demo = lh.sql("""
  SELECT Gender, COUNT(*) AS total, AVG(Age) AS avg_age
  FROM dimenrolledparticipants
  WHERE Gender IS NOT NULL
  GROUP BY Gender""")
```

---

## Working with large tables

If a table has hundreds of columns, only request the ones you need. The columns
you leave out never get sent over the network, so your query runs faster.

---

## Configuration

The bundled `config.json` provides sensible defaults. Override any parameter:

```r
connect_to_fabric(
  workspace_id  = "67f69cc9-00c9-4c9c-a85b-38fc30774b7b",
  lakehouse     = "HCW_fitbit_data",
  fabric_tenant = "a5d4252a-02f9-4e60-96f0-9733baae4919"
)
```

```python
FabricLakehouse(
  workspace_guid = "67f69cc9-00c9-4c9c-a85b-38fc30774b7b",
  lakehouse      = "HCW_fitbit_data",
  fabric_tenant  = "a5d4252a-02f9-4e60-96f0-9733baae4919"
)
```

---

## Updating

### R

```r
library(fabriconnect)
update_fabriconnect()
```

Or restart R and re-run the install command.

### Python

```bash
pip install --force-reinstall --no-cache-dir "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy"
```

---

## Troubleshooting

| Problem | Likely cause | What to do |
|---------|-------------|------------|
| "SIGN IN REQUIRED" prompt loops on every call | Token not cached | Update to the latest version — tokens are now cached per session |
| `401 Unauthorized` | Token expired | Re-run `connect_to_fabric()` — you'll be prompted to sign in again |
| `Could not connect to server login.microsoftonline.com` | Network / firewall blocking Microsoft login | Make sure `login.microsoftonline.com` is reachable on port 443 |
| `No parquet files found` | Table name is wrong | Check the name with `list_tables()`. Names are case-sensitive. |
| `duckdb` not found | DuckDB not installed | `install.packages("duckdb")` (R) or `pip install duckdb` (Python) |
| Package install says `...is in use` | R session has locked files | Restart R and re-run the install command |
| `Failed to install 'unknown package' from GitHub: HTTP error 403` | GitHub rate limit (60 req/hr) | Set a GitHub PAT (`usethis::create_github_token()`, then `gitcreds::gitcreds_set()`), or install from ZIP: `install.packages("https://github.com/AKU-CDIO/fabric-inbound-access/archive/main.zip", repos = NULL, type = "source")` |
| `msal` import error (Python) | Missing `msal` package | `pip install msal` |
| Browser does not open automatically | No default browser or headless environment | Manually visit the URL printed in the console and enter the code shown |

---

## Repository structure

```
fabriconnect/              # R package source
  inst/config.json
  R/
fabriconnectpy/            # Python package source
  fabricpy/config.json
  fabricpy/client.py
  fabricpy/__init__.py
examples/                  # Runnable R examples
install_fabriconnect.bat   # Double-click installer for Windows
docs/                      # Supplementary documentation
```

---

## Testing the delegated token flow from end to end

**1. Generate a token** (via Azure CLI if you have access):

```bash
az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
az account get-access-token --resource https://storage.azure.com --query accessToken -o tsv
```

Or via Python (MSAL device code, no Azure CLI needed):

```python
import msal
app = msal.PublicClientApplication(
    "1950a258-227b-4e31-a9cf-717495945fc2",
    authority="https://login.microsoftonline.com/a5d4252a-02f9-4e60-96f0-9733baae4919"
)
flow = app.initiate_device_flow(["https://storage.azure.com/.default"])
print(flow['message'])   # visit this URL and enter the code
result = app.acquire_token_by_device_flow(flow)
print(result['access_token'])
```

**2. Set the token as a delegated token:**

```bash
set FABRIC_DELEGATED_ACCESS_TOKEN="<token-from-step-1>"
```

**3. Connect and verify:**

```python
from fabricpy import FabricLakehouse
lh = FabricLakehouse()
print(lh.list_tables())
```

```r
library(fabriconnect)
conn <- connect_to_fabric()
list_tables(conn)
```

If you see your tables listed, the delegated token flow is working.

---

## License

Apache 2.0

**Author:** CDIO, AKU
**Contact:** Derick Imbati — derick.imbati@aku.edu
