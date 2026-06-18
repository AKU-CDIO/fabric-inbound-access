# fabriconnect / fabricpy

R and Python packages for reading Microsoft Fabric Lakehouse data over HTTPS,
bypassing the TDS/IP firewall port-1433 restriction. All traffic uses port 443.

---

## Prerequisites

- **Workspace access** — your Azure AD identity must have at least **Contributor**
  role on the target Fabric workspace. **Viewer** role alone does **not** grant
  OneLake data access (you will see a `403 Forbidden` error). If your team must
  use Viewer, ask the workspace admin to enable
  **OneLake data access → Viewers can read OneLake data** in workspace settings.
- **Network** — the workspace IP firewall must allow your IP or be set to
  **Allow all connections**.
- **GitHub rate limit** — unauthenticated installs are limited to 60 requests/hour.
  If installing on a shared VM, use the ZIP install command (see Troubleshooting)
  or set a `GITHUB_PAT` environment variable.

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

## Authentication

The packages try these methods in order, falling through automatically:

| Priority | Method | Use case |
|----------|--------|----------|
| 1 | Explicit `access_token` / `token` parameter | Caller provides a token |
| 2 | `FABRIC_ACCESS_TOKEN`, `FABRIC_DELEGATED_ACCESS_TOKEN`, or `AZURE_ACCESS_TOKEN` env var | CI / headless / delegated-token access |
| 3 | Interactive device-code sign-in | Desktop — works like ODBC, MFA supported |
| 4 | Azure CLI (`az login`) | Advanced / legacy automation |

### Interactive sign-in (recommended)

Call `connect_to_fabric()` or `FabricLakehouse()` with no arguments. A browser
opens automatically prompting you to sign in with your email. MFA (Microsoft
Authenticator, etc.) is fully supported — no Azure CLI installation required.
The token is cached for the session; subsequent calls do not re-prompt.

```r
conn <- connect_to_fabric()
```

```python
lh = FabricLakehouse()
```

### Environment variable (CI / headless)

```bash
export FABRIC_ACCESS_TOKEN="<your-token>"
```

For delegated tokens issued to external or non-AKU-domain collaborators, use:

```bash
export FABRIC_DELEGATED_ACCESS_TOKEN="<delegated-token>"
```

The token may be provided as either the raw JWT or `Bearer <token>`. The signed-in
identity must still be granted access to the Fabric workspace, usually as an
external/guest user in the AKU tenant.

### Explicit token (in code)

```r
conn <- connect_to_fabric(access_token = "<your-token>")
```

```python
lh = FabricLakehouse(token = "<your-token>")
```

### Azure CLI (advanced)

```bash
az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
```

---

## Available Lakehouses

Seven Lakehouses in the `cdiofabric` workspace:

| Name | GUID | Contents |
|------|------|----------|
| `uzima_db_backup` *(default)* | `67596566-...` | 31 tables — enrolled participants, sleep logs, date dimension |
| `HCW_fitbit_data` | `65058b40-...` | 5 tables — activity logs, daily data, devices |
| `Qualtrics` | `8bb92d0b-...` | Survey data |
| `CDIOUZIMA_Azure_Storage_Accounts_Data` | `7de09c85-...` | Azure storage metadata |
| `azu_cdiouzima` | `07d783b9-...` | Azure data |
| `LS_Fabric_Lakehouse` | `1ad04079-...` | Linked services |
| `StagingLakehouseForDataflows_20251110175852` | `4cab7880-...` | Dataflow staging |

Discover programmatically:

```r
list_lakehouses()
```

```python
FabricLakehouse.list_lakehouses()
```

---

## Examples

### Read a table

```r
df <- read_table(conn, "dimenrolledparticipants")
```

```python
df = lh.to_pandas("dimenrolledparticipants")
```

### Column pruning

Fetch only the columns you need to reduce data transfer:

```r
df <- read_table(conn, "dimenrolledparticipants",
  columns = c("ParticipantIdentifier", "Gender", "Age"))
```

```python
df = lh.to_pandas("dimenrolledparticipants",
  columns = ["ParticipantIdentifier", "Gender", "Age"])
```

### SQL queries

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

### Cross-lakehouse queries

Join tables across different Lakehouses by passing named connections. Use
schema prefixes to reference tables in SQL:

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

## Large tables (>500 GB)

Use `columns` or `table_columns` to fetch only required columns. Python's
`deltalake` performs predicate pushdown at the OneLake storage layer — only
requested bytes traverse the network. R reads parquet payloads in-memory via
`httr::GET()` + `arrow::read_parquet()` with no disk writes.

| Task | R | Python |
|------|---|--------|
| Column pruning | `read_table(conn, "tbl", columns = c("a", "b"))` | `lh.to_pandas("tbl", columns = ["a", "b"])` |
| SQL pruning | `query_tables(conn, sql, table_columns = list(...))` | `lh.sql(query, table_columns = {...})` |

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

## Architecture

```
┌─────────────┐     ┌─────────────────────────────────────┐     ┌──────────┐
│  R / Python │────▶│  OneLake ADLS Gen2 DFS REST API     │────▶│  Fabric  │
│  (your code)│     │  onelake.dfs.fabric.microsoft.com   │     │ Lakehouse │
└──────┬──────┘     └─────────────────────────────────────┘     └──────────┘
       │
       │  HTTPS (port 443) — no TDS (port 1433)
       │
       ▼
┌──────────────┐
│ Authentication │
│                │
│  1. Device-code│  Microsoft identity platform
│     flow       │  (email + MFA, like ODBC)
│  2. Azure CLI  │  (fallback)
└────────────────┘
```

1. **Authentication** — Microsoft identity platform device-code flow obtains an
   OAuth2 token for `https://storage.azure.com`. The browser opens
   automatically; you sign in with email and MFA. The token is cached for the
   session.
2. **Metadata** — OneLake ADLS Gen2 DFS REST API
   (`onelake.dfs.fabric.microsoft.com`) lists Delta table directories.
3. **Data** — Parquet files fetched over HTTPS and read in-memory:
   - **R**: `httr::GET()` → `arrow::read_parquet(raw)` — no disk writes.
   - **Python**: `deltalake` via `use_fabric_endpoint=true`.
4. **SQL** — Queries execute in DuckDB after loading required tables.

All communication is HTTPS (443). No TDS (1433) is used.

---

## Troubleshooting

| Problem | Likely cause | Resolution |
|---------|-------------|------------|
| "SIGN IN REQUIRED" prompt loops on every call | Token not cached | Update to latest version — tokens are now cached per session |
| `401 Unauthorized` | Token expired | Re-run `connect_to_fabric()` — you will be prompted to sign in again |
| `Could not connect to server login.microsoftonline.com` | Network / firewall blocking Microsoft identity platform | Ensure `login.microsoftonline.com` is reachable on port 443 |
| `No parquet files found` | Table name incorrect | Verify with `list_tables()`. Names are case-sensitive. |
| `duckdb` not found | Missing DuckDB | `install.packages("duckdb")` (R) or `pip install duckdb` (Python) |
| Package install says `...is in use and will not be installed` | R session holds locked DLLs | Restart R and re-run the install command |
| `Failed to install 'unknown package' from GitHub: HTTP error 403` | GitHub API rate limit (60 req/hr unauthenticated) | Set a GitHub PAT: `usethis::create_github_token()`, then `gitcreds::gitcreds_set()`, or install from zip: `install.packages("https://github.com/AKU-CDIO/fabric-inbound-access/archive/main.zip", repos = NULL, type = "source")` |
| `msal` import error (Python) | Missing `msal` package | `pip install msal` |
| Browser does not open automatically | Headless environment or no default browser | Manually visit the URL printed in the console and enter the code shown |

---

## Repository structure

```
fabriconnect/              # R package source
  inst/config.json         # Workspace / Lakehouse GUIDs
  R/                       # connect, list_tables, read_table,
                           # query_tables, list_lakehouses, update_fabriconnect
fabriconnectpy/            # Python package source
  fabricpy/config.json     # Workspace / Lakehouse GUIDs
  fabricpy/client.py       # FabricLakehouse class
  fabricpy/__init__.py     # Package init
examples/                  # Runnable R examples
install_fabriconnect.bat   # Double-click installer for Windows
docs/                      # Supplementary documentation
```

---

## License

Apache 2.0

**Author:** CDIO, AKU
**Contact:** Derick Imbati — derick.imbati@aku.edu
