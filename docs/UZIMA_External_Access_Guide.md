# UZIMA Fabric Data Access - External Researcher Setup Guide

**Version:** 1.2
**Date:** July 2026
**Contact:** Derick Imbati - derick.imbati@aku.edu

---

## Overview

This guide explains how approved external researchers can access UZIMA study data from Microsoft Fabric on a personal Windows or Mac computer. The supported personal-laptop path is:

1. Sign in interactively to the AKU Azure tenant.
2. Retrieve service-principal credentials from Azure Key Vault.
3. Use the service principal to connect to the Microsoft Fabric SQL endpoint.
4. Query only the authorized Fabric data.

No service-principal secret should be saved in notebooks, scripts, or local files.

## What You Need

- Windows or Mac computer
- Internet connection
- Python 3.10+ with a dedicated `.venv`; do not install into Anaconda `base`
- Microsoft ODBC Driver 18 for SQL Server
- For Mac: `unixODBC` is also required
- An approved account added to the AKU tenant and granted Key Vault access

## Install Python Package

Use a dedicated virtual environment. Do not install this into Anaconda `base` or another shared Python environment, because shared environments may contain Azure CLI, Jupyter, or analytics packages with different dependency pins.

### Windows PowerShell

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
```

If `py` is not available, use `python` instead:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
```

### Mac Terminal

```bash
python3 -m venv .venv
./.venv/bin/python -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
```

This installs the Fabric package plus the SQL/Key Vault dependencies inside `.venv`: `pandas`, `pyodbc`, `azure-identity`, and `azure-keyvault-secrets`.

## Connect to Fabric SQL

Authenticate once by calling `connect_to_fabric_sql()`. Keep that same `conn` open while you list tables, read tables, and run SQL. Close it with `conn.close()` when finished. Do not call `connect_to_fabric_sql()` again for each query, because that can trigger repeated authentication.

```python
from fabricpy import connect_to_fabric_sql, list_sql_tables, read_sql_table, query_sql

conn = connect_to_fabric_sql(keyvault_auth_method="device_code")

tables = list_sql_tables(conn)
print(tables)

df = read_sql_table(conn, "dbo.dimenrolledparticipants", top=10)
print(df.head())

summary = query_sql(conn, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants")
print(summary)

conn.close()
```

## Authentication Behavior

`connect_to_fabric_sql()` authenticates interactively to Key Vault.

- By default it prints one device-code prompt.
- Use the printed code at `https://login.microsoft.com/device`.
- Complete MFA with the method enabled for your account.
- Browser login is opt-in only by calling `connect_to_fabric_sql(keyvault_auth_method="browser")`.

Expected device-code prompt:

```text
SIGN IN REQUIRED
Open: https://login.microsoft.com/device
Code: XXXXXXXX
```

Tenant used for Key Vault login:

```text
4fde8ff3-4dd5-42e1-a25a-e42905610d66
```

## Common Queries

Run these examples while the same `conn` from the previous section is still open. When finished, run `conn.close()`.

### List Tables

```python
tables = list_sql_tables(conn)
print(tables)
```

### Read Selected Columns

```python
df = read_sql_table(
    conn,
    "dbo.dimenrolledparticipants",
    columns=["ParticipantIdentifier", "Gender", "Age"],
    top=100,
)
print(df.head())
```

### Filter With SQL

```python
df = query_sql(conn, """
    SELECT ParticipantIdentifier, Gender, Age
    FROM dbo.dimenrolledparticipants
    WHERE Gender = 'Female'
""")
print(df.head())
```

### Large Tables

Use `TOP`, selected columns, and filters before loading data into pandas:

```python
df = query_sql(conn, """
    SELECT TOP 100 ParticipantIdentifier, date, steps
    FROM dbo.factfitbitdailydata
    WHERE date >= '2023-01-01'
""")
print(df.head())
```

## R Users

R service-principal SQL access is available, but the current R helper uses Azure CLI to obtain the Key Vault token.

```r
install.packages(c("DBI", "odbc", "httr", "jsonlite", "dplyr", "remotes"))
remotes::install_github(
  "AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect",
  force = TRUE,
  upgrade_dependencies = FALSE
)
```

Before connecting in R, sign in:

```bash
az login --tenant 4fde8ff3-4dd5-42e1-a25a-e42905610d66
```

Then use:

```r
library(fabriconnect)

con <- connect_to_fabric_sql()
list_tables(con)
df <- read_table(con, "dbo.dimenrolledparticipants")
DBI::dbDisconnect(con)
```

## Troubleshooting

### ImportError: cannot import name `connect_to_fabric_sql`

You are using an old installed copy of `fabricpy`. Create a clean `.venv`, install from GitHub there, and verify the import with that `.venv` Python:

Windows:

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
```

Mac:

```bash
python3 -m venv .venv
./.venv/bin/python -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
```

Verify:

```python
import fabricpy
print(fabricpy.__file__)
print(hasattr(fabricpy, "connect_to_fabric_sql"))
```

### HTTP 401 from `FabricLakehouse/list_tables`

That is the older OneLake delegated-token path. For personal-laptop Key Vault + service-principal access, use `connect_to_fabric_sql()`.

### Browser Login Does Not Open

Use the printed device-code prompt at `https://login.microsoft.com/device`. If you see both browser login and device code, update the package and call `connect_to_fabric_sql(keyvault_auth_method="device_code")`.

### Microsoft Authenticator Shows No Code

This usually indicates an account/tenant/MFA provisioning issue rather than a Python or Mac issue. Confirm:

- The researcher is added as a guest/user in the AKU tenant.
- The account can complete MFA for tenant `4fde8ff3-4dd5-42e1-a25a-e42905610d66`.
- Conditional Access allows the user's MFA method.
- The researcher has Key Vault RBAC access.

### Key Vault Forbidden

Ask the admin to confirm the user has the `Key Vault Secrets User` role on the UZIMA Key Vault.

### ODBC Driver Error

Install Microsoft ODBC Driver 18 for SQL Server.

Mac also needs `unixODBC`, commonly installed with Homebrew:

```bash
brew install unixodbc
```

### Fabric SQL Login Fails

Ask the admin to confirm the service principal has read access to the required Fabric workspace/lakehouse/SQL endpoint.

## Security Notes

- Do not print or save Key Vault secret values.
- Do not put service-principal credentials in notebooks.
- Use read-only Fabric permissions for the service principal.
- Rotate the service-principal secret before expiry.
- Review Key Vault audit logs for secret access.

---

*Document version 1.2 - July 2026*