# fabriconnect / fabricpy

Read Delta tables from Microsoft Fabric Lakehouses via the **OneLake HTTPS API** — no TDS/ODBC required.

Bypasses the [known Fabric bug](docs/BUG_WORKSPACE_IP_FIREWALL_TDS.md) where workspace-level IP firewall rules block TDS (port 1433) connections even for allowed IPs. Since all traffic is HTTPS (port 443), the firewall works correctly.

## Quick Start

### R
```r
library(fabriconnect)
conn <- connect_to_fabric()
df <- read_table(conn, "dimenrolledparticipants")
```

### Python
```python
from fabricpy import FabricLakehouse
lh = FabricLakehouse()
df = lh.to_pandas("dimenrolledparticipants")
```

## Repository Structure

| Path | Description |
|------|-------------|
| `fabriconnect/` | **R package** — install with `R CMD INSTALL fabriconnect/` |
| `fabriconnectpy/` | **Python package** — install with `pip install ./fabriconnectpy/` |
| `examples/` | Example R scripts |
| `docs/` | Bug report, workarounds, detailed documentation |
| `onelake_delta_access.py` | Standalone Python reference script |
| `connect_to_fabric_vm_only.py` | Original ODBC connection script (requires TDS) |

## Prerequisites

- **Azure CLI** logged into an account with access to the Fabric workspace
- Workspace network set to **"Allow all connections"** (Public) or your machine's IP in the allowlist
- Internet access to `onelake.dfs.fabric.microsoft.com` (HTTPS/443)

## How It Works

1. Gets an Azure AD token for the Fabric tenant via `az.cmd`
2. Reads Delta tables directly from OneLake via the ADLS Gen2 API
3. All requests are HTTPS — the IP firewall correctly allows them

## License

MIT
