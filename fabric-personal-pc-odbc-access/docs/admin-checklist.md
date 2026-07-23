# Admin Checklist

Use this checklist for the Key Vault plus managed identity ODBC model.

## 1. Store ODBC Settings In Key Vault

From this project folder:

```powershell
.\scripts\set-keyvault-odbc-settings.ps1
```

This stores:

- `fabric-odbc-connection-string`
- `fabric-managed-identity-client-id`
- `fabric-managed-identity-object-id`

## 2. Store The Approved Email List

From this project folder:

```powershell
.\scripts\sync-keyvault-whitelist.ps1
```

Approved emails:

- `derick.imbati@aku.edu`
- `rais.muhammad@aku.edu`
- `dorcasm@umich.edu`
- `yechank@med.umich.edu`
- `nannab@med.umich.edu`

These emails are for the approval check. They are not Fabric logins in this model.

## 3. Assign cdiofabric To The Azure Runner

Use this managed identity:

```text
Identity name: cdiofabric
Application ID: 4ae6ed7b-b72c-4853-9a3c-10699e60f63e
Object ID: 8d88bbab-1c76-4bf0-b4f7-1cb49a001d9e
```

Assign it to the Azure Function, runbook worker, app service, or VM that runs the ODBC code.

## 4. Grant Fabric Access To cdiofabric

In Fabric, grant `cdiofabric` only the approved access.

Prefer masked views. Do not grant raw PII tables unless approved.

Example SQL permission:

```sql
GRANT SELECT ON OBJECT::dbo.dimenrolledparticipants TO [cdiofabric];
```

If Fabric shows a different principal name, use that exact name.

## 5. Test ODBC

Run one of these from the Azure-side runner or admin test environment:

- `examples/r/fabric_odbc_researcher_guide.Rmd`
- `examples/python/fabric_odbc_researcher.py`
- `examples/python/fabric_odbc_researcher.ipynb`

The example reads the ODBC connection string from Key Vault, then ODBC uses `cdiofabric` to connect to Fabric.