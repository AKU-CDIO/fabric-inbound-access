# Bug: Workspace-level IP Firewall Rules block TDS/SQL endpoint connections

## Status
**Unresolved** — awaiting Microsoft fix (reported May 2026)

## Description
When a Fabric workspace is set to **"Allow connections from selected networks and workspace level private links"** with source IPs in the allowlist, the **Fabric portal (HTTPS)** correctly evaluates the IP rules, but the **TDS/SQL endpoint (port 1433, used by ODBC/SSMS)** rejects all connections with a misleading error about private links.

This means workspace-level IP firewall rules work for the browser UI but NOT for database connections via ODBC, SSMS, or any TDS-based tool — despite "Warehouses" being listed as a supported item type in the documentation.

## Error Message
```
[28000] [Microsoft][ODBC Driver 17 for SQL Server][SQL Server]
While private links are enabled, you cannot connect from this IP address (18456)
```

## Affected Setup
- **VM**: `uzima-copied` (VNET: `uzimadsvmInstance-vnet`, IP: `4.245.225.10`)
- **Fabric Workspace ID**: `67f69cc9-00c9-4c9c-a85b-38fc30774b7b`
- **Connection**: ODBC Driver 17 via `ActiveDirectoryPassword` auth
- **VM public IP `4.245.225.10`** confirmed correct via httpbin.org echo

## What Works
- Setting workspace to **"Allow all connections"** (Public) → connection succeeds
- Fabric portal access with IP firewall rules enabled → works correctly

## What Does NOT Work
- TDS/SQL endpoint connections when IP firewall rules are active → blocked with private-link error
- Even with correct IPs in the allowlist, confirmed via REST API

## Reported By
- **BartOuwehand** on Fabric Community (2026-05-10):
  https://community.fabric.microsoft.com/t5/Data-Warehouse/Workspace-IP-Firewall-Rules-block-SSMS-TDS-connections-to/m-p/5180444
- Support response: "raise a Microsoft support ticket" — no fix available

## References
- MS Learn — Workspace IP firewall overview:
  https://learn.microsoft.com/en-us/fabric/security/security-workspace-level-firewall-overview
- MS Learn — Workspace IP firewall setup:
  https://learn.microsoft.com/en-us/fabric/security/security-workspace-level-firewall-set-up
- MS Learn — Workspace-level private links setup:
  https://learn.microsoft.com/en-us/fabric/security/security-workspace-level-private-links-set-up
- MS Learn — Cross-tenant private link communication:
  https://learn.microsoft.com/en-us/fabric/security/security-cross-tenant-communication
- Fabric Community — Same error (Data Warehouse + Private Link + Lookup activity):
  https://community.fabric.microsoft.com/t5/Data-Warehouse/Data-Warehouse-with-Private-Link-enabled-Lookup-activity-Cannot/m-p/4363134

## Workaround
The only current workaround is to set the workspace to **"Allow all connections"** (Public). The proper fix requires workspace-level Private Link, which is blocked by cross-tenant constraints (VM in tenant `4fde8ff3-...`, Fabric in different tenant).

## Workaround Available: OneLake Delta HTTPS
**2026-05-26 (updated):** The earlier "empty Tables" finding was incorrect — the API call was missing required headers. The Lakehouse **does** have 31 user tables with data in OneLake. The packages `fabriconnect` (R) and `fabricpy` (Python) provide working OneLake Delta table access over HTTPS, bypassing the TDS bug entirely.
