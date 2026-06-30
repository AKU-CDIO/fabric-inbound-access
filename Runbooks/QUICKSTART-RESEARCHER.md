# Accessing UZIMA Data — Quick Start for Researchers

## 3 steps

### 1. Log into the VM

Open Remote Desktop and connect to the UZIMA research VM.

### 2. Run the login tool

Double-click **`login.bat`** (or `Runbooks\login.bat`).

A blue window will open and ask:

```
Who are you?
  1. Ye Chan Kim
  2. Kenney Brooke
```

Type **1** or **2** and press Enter.

### 3. Use the data

The tool will confirm your access. Pick an option:

- **1** → Opens R (run `library(fabriconnect); conn <- connect_to_fabric()`)
- **2** → Opens Python
- **3** → Opens command prompt

That's it. The token is set automatically. You don't need to sign in again during your session.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Access denied" | Your email hasn't been added yet. Ask the admin. |
| "Cannot contact service" | VM needs internet. Check connection. |
| Token expired mid-session | Just run `login.bat` again — takes 10 seconds. |

## Available Lakehouses

- `uzima_db_backup` (default)
- `HCW_fitbit_data`
- `Qualtrics`
- `CDIOUZIMA_Azure_Storage_Accounts_Data`
- `azu_cdiouzima`
- `LS_Fabric_Lakehouse`
- `StagingLakehouseForDataflows_20251110175852`

To use a different lakehouse: `connect_to_fabric(lakehouse = "HCW_fitbit_data")`
