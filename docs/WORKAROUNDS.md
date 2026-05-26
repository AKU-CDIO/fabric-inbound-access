# Workarounds for TDS Blocked by IP Firewall Bug

## Context
Workspace-level IP firewall rules block TDS (port 1433) but allow HTTPS (port 443).
These workarounds use HTTPS-based APIs to access Fabric data.

---

## Option 1: Read Delta Tables via OneLake ADLS Gen2 API

**✅ Working for `uzima_db_backup` Lakehouse — 31 tables with data available.**

Read directly from OneLake using the `deltalake` Python library or `AzureStor` + `arrow` in R over HTTPS. Two packages are provided:

### Python: `fabricpy`
```bash
pip install ./fabriconnectpy/
```
```python
from fabricpy import FabricLakehouse
lh = FabricLakehouse()
df = lh.to_pandas("factfitbitdailydata")
```

### R: `fabriconnect`
```r
R CMD INSTALL fabriconnect/
```
```r
library(fabriconnect)
conn <- connect_to_fabric()
df <- read_table(conn, "factfitbitdailydata")
```

### Low-level example (Python):

```python
from deltalake import DeltaTable
from azure.identity import DefaultAzureCredential

token = DefaultAzureCredential().get_token(
    "https://storage.azure.com/.default"
).token

storage_options = {
    "bearer_token": token,
    "use_fabric_endpoint": "true"
}

dt = DeltaTable(
    "abfss://<workspace-id>@onelake.dfs.fabric.microsoft.com/<lakehouse-id>/Tables/<table-name>",
    storage_options=storage_options
)
df = dt.to_pandas()
```

**Pros**: Direct HTTPS, respects IP firewall rules, no extra infra needed.
**Cons**: Read-only, Lakehouse only (not Warehouse), Delta table access — not SQL.

### Run SQL via DuckDB + Delta
DuckDB can read Delta tables and run SQL queries:

```python
import duckdb
con = duckdb.connect()
con.execute("INSTALL delta; LOAD delta;")
con.execute("""
    SELECT * FROM delta_scan(
        'abfss://<workspace>@onelake.dfs.fabric.microsoft.com/<lakehouse>/Tables/<table>'
    )
""").fetchdf()
```

---

## Option 2: OneLake Table REST APIs (Unity Catalog Compatible)

Read-only metadata and data via REST at `https://onelake.table.fabric.microsoft.com`.

```bash
GET https://onelake.table.fabric.microsoft.com/delta/<Workspace>/<Lakehouse>/api/2.1/unity-catalog/tables?catalog_name=<Lakehouse>&schema_name=dbo
```

**Pros**: Standard REST API, HTTPS respected.
**Cons**: Read-only metadata, not ad-hoc SQL.

---

## Option 3: Use a Supported Azure Resource with Resource Instance Rules

If the Fabric admin enables Resource Instance Rules and adds a supported Azure resource (e.g., Azure SQL Server `Microsoft.Sql/servers`), that resource can access Fabric via its managed identity. The VM then connects to that proxy resource instead.

**Pros:** Proper security, works cross-tenant with managed identity.
**Cons:** Requires deploying/managing additional Azure resource(s).

---

## Option 4: Run Spark Notebook via Fabric REST API

Submit a Fabric notebook job via REST API and retrieve results.

```python
POST https://api.fabric.microsoft.com/v1/workspaces/{workspaceId}/items/{notebookId}/jobs/instances
```

**Pros**: Full Spark SQL capability, HTTPS respected.
**Cons**: More complex orchestration, latency per query.
