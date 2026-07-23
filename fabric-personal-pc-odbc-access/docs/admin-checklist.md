# Admin Checklist

Use this checklist for personal-PC ODBC access.

## 1. Confirm Users

Confirm each researcher exists in the Fabric tenant as a member or guest user.

Approved list:

- `derick.imbati@aku.edu`
- `rais.muhammad@aku.edu`
- `dorcasm@umich.edu`
- `yechank@med.umich.edu`
- `nannab@med.umich.edu`

If `az ad user show --id <email>` does not resolve a user, ask an Entra admin to confirm the exact guest UPN or object ID.

## 2. Grant Fabric Access

In the Fabric tenant:

1. Add the users to the workspace or item.
2. Prefer least privilege.
3. Grant access to approved tables or masked views only.
4. Use SQL permissions on the SQL analytics endpoint for table/view access.

For example, after connecting as an admin to the SQL endpoint:

```sql
-- Example only. Use the final approved table or masked view name.
GRANT SELECT ON OBJECT::dbo.dimenrolledparticipants TO [user@domain.edu];
```

## 3. Lift Network Restrictions

Remove VM-only inbound restrictions for the Fabric SQL endpoint.

The users' personal PCs need to reach the SQL analytics endpoint over ODBC. Microsoft Fabric supports ODBC connections to SQL analytics endpoints with Microsoft Entra authentication and ODBC Driver 18 or later.

## 4. Update Key Vault Whitelist

From this project folder:

```powershell
.\scripts\sync-keyvault-whitelist.ps1
```

The Key Vault list is for admin tracking. It does not replace Fabric workspace, item, or SQL permissions.

## 5. Researcher Test

Ask the researcher to open one of these examples:

- `examples/r/fabric_odbc_researcher_guide.Rmd`
- `examples/python/fabric_odbc_researcher.py`
- `examples/python/fabric_odbc_researcher.ipynb`

The examples already contain the Fabric server and use `uzima_db_backup` by default.

If the researcher needs Fitbit or Qualtrics, change only the `DATABASE=` value inside the connection string.