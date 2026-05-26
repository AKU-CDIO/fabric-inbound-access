# OneLake / Fabric Inbound Access Documentation

## Resource Instance Rules (Trusted Resources)
https://learn.microsoft.com/en-us/fabric/onelake/onelake-manage-inbound-access-trusted-resources?tabs=fabric-portal-1

**Evaluation for VM restriction (2026-05-26):**
This feature allows restricting OneLake access by Azure resource identity instead of network IP. However, it does NOT support our scenario because:
- Virtual Machines (`Microsoft.Compute/virtualMachines`) are NOT in the supported resource types list
- Resources must be in the same Microsoft Entra tenant as the Fabric workspace (our VM is cross-tenant)
- Only applies to OneLake, NOT to the TDS/SQL endpoint (port 1433) used by ODBC/SSMS

## Known Bug: IP Firewall + TDS Endpoint
See `connectToFabricVM/BUG_WORKSPACE_IP_FIREWALL_TDS.md`
Workspace-level IP firewall rules block TDS/SQL connections even with correct IPs in allowlist.

## Fabric REST API Access
**2026-05-26:** Discovered that Fabric REST API is accessible by using the **Fabric tenant** token:
```
az account get-access-token --resource https://api.fabric.microsoft.com --tenant a5d4252a-02f9-4e60-96f0-9733baae4919
```
The earlier "UserNotLicensed" error was from the VM's tenant (`4fde8ff3-4dd5-42e1-a25a-e42905610d66`). Explicit `--tenant` flag resolves this.

## OneLake DFS API Access
**2026-05-26:** Confirmed OneLake DFS API works with correct authentication:
- Requires token from **Fabric tenant** for `https://storage.azure.com`
```powershell
az account get-access-token --resource https://storage.azure.com --tenant a5d4252a-02f9-4e60-96f0-9733baae4919
```
- Workspace name (`cdiofabric`) resolves correctly
- Lakehouse name must include `.Lakehouse` extension in the path
- Only subfolders `Tables`, `Files`, `Functions`, `TableMaintenance` are accessible
- Root-level listing is blocked by policy

## Discovered Workspace Items
| Type | Display Name | GUID |
|------|-------------|------|
| Lakehouse | uzima_db_backup | `67596566-8ea9-4fd6-a451-ca9654aa4f10` |
| SQLEndpoint | uzima_db_backup | `ffa3ec44-57d8-4444-90dd-066fe10bb97a` |
| Lakehouse | HCW_fitbit_data | `65058b40-a60c-4267-a882-9263e0ba0617` |
| Lakehouse | CDIOUZIMA_Azure_Storage_Accounts_Data | `7de09c85-b39d-49e4-873d-e683b671448b` |
| Lakehouse | azu_cdiouzima | `07d783b9-d533-42f3-a9b7-bc16c18a5376` |

## Correction: Lakehouse Tables Folder Contains Data!
**2026-05-26 (corrected):** The earlier "empty" result was wrong — the OneLake DFS API requires specific headers (`x-ms-version`, `Accept`) and the `resource=filesystem` parameter. With the correct API call, **31 user tables** (and ~55 views) were found in the Lakehouse with substantial data (e.g., `factfitbitdailydata`: 1.5M rows).

## Working OneLake Access
The OneLake Delta table workaround **does work** for this Lakehouse. Two packages were created:

### R Package: `fabriconnect`
- Location: `connectToFabricVM/fabriconnect/`
- Install: `R CMD INSTALL fabriconnect/` (or devtools)
- Uses `AzureStor` + `arrow` — no TDS needed
- Functions: `connect_to_fabric()`, `list_tables()`, `read_table()`

### Python Library: `fabricpy`
- Location: `connectToFabricVM/fabriconnectpy/`
- Install: `pip install ./fabriconnectpy/`
- Uses `deltalake` with `bearer_token` + `use_fabric_endpoint`
- Class: `FabricLakehouse` with `list_tables()`, `read_table()`, `to_pandas()`
