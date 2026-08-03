# UZIMA Fabric Data Access - Python External Researcher Guide

**Version:** 1.0
**Date:** August 2026
**Contact:** Derick Imbati - derick.imbati@aku.edu

---

## 1. What This Guide Is For

This guide is for approved external researchers who want to access UZIMA Microsoft Fabric data from Python on a personal Windows or Mac computer.

The access flow is:

1. Open your terminal or Python notebook environment.
2. Install the UZIMA Python package directly from GitHub.
3. Start Python and call `connect_to_fabric_sql(auth="sp_vault")`.
4. Sign in interactively with your approved account.
5. The package retrieves service-principal credentials from Azure Key Vault.
6. The package connects to the Microsoft Fabric SQL endpoint.
7. You list tables, read tables, or run read-only SQL queries.
8. You close the connection when finished.

You do not need to run `az login`. Do not save or paste service-principal credentials anywhere.

## 2. Before You Start

Confirm these items before installing the package.

### Account Access

You need an approved account that has been added to the AKU Azure tenant and granted access to the UZIMA Key Vault.

The Key Vault sign-in tenant is:

```text
4fde8ff3-4dd5-42e1-a25a-e42905610d66
```

### Software

You need:

- Python 3.10 or later
- Microsoft ODBC Driver 18 for SQL Server
- Internet access

Mac users also need `unixODBC`.

Install it with Homebrew:

```bash
brew install unixodbc
```

## 3. Install The Python Package

Install the package directly into your Python user site. A virtual environment is not required.

### Windows PowerShell

```powershell
py -3 -m pip install --user "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --upgrade --no-cache-dir
```

If `py` is not available, use `python`:

```powershell
python -m pip install --user "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --upgrade --no-cache-dir
```

### Mac Terminal

```bash
python3 -m pip install --user "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --upgrade --no-cache-dir
```

## 4. Confirm The Package Installed

Open Python and run:

```python
import fabricpy

print(fabricpy.__file__)
print(fabricpy.__version__)
print(hasattr(fabricpy, "connect_to_fabric_sql"))
```

The version should be `0.1.1` or later, and the last line should print:

```text
True
```

If it prints `False`, update the package again using the install command above.

## 5. Connect To The Default UZIMA Lakehouse

The default database/lakehouse is:

```text
uzima_db_backup
```

Run this in Python:

```python
from fabricpy import connect_to_fabric_sql

conn = connect_to_fabric_sql(auth="sp_vault")
```

A Microsoft sign-in page should open. Complete the sign-in with your approved account and complete MFA.

If the browser does not open automatically, Python will print a device-code message similar to this:

```text
SIGN IN REQUIRED
Open: https://login.microsoft.com/device
Code: XXXXXXXX
```

Open the printed URL in your browser and enter the printed code.

Keep the same `conn` object open while you work. Do not call `connect_to_fabric_sql(auth="sp_vault")` again for every table or query, because that can ask you to authenticate again.

## 6. List Available Tables

After the connection succeeds, list the tables:

```python
from fabricpy import list_sql_tables

tables = list_sql_tables(conn)
print(tables)
```

Table names may include a schema such as `dbo`. Use the full name when reading a table, for example `dbo.dimenrolledparticipants`.

## 7. Read A Small Table Sample

Start with a small sample before loading a large table.

```python
from fabricpy import read_sql_table

participants = read_sql_table(
    conn,
    "dbo.dimenrolledparticipants",
    columns=["ParticipantIdentifier", "Gender", "Age"],
    top=10,
)

print(participants.head())
```

## 8. Run A Read-Only SQL Query

Use `query_sql()` for SQL queries.

```python
from fabricpy import query_sql

participant_count = query_sql(
    conn,
    "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants",
)

print(participant_count)
```

Only read-only `SELECT` queries are allowed by the package helpers.

## 9. Work With Large Tables Safely

For large tables, select only the columns you need and filter before loading data into pandas.

```python
fitbit_sample = query_sql(conn, """
    SELECT TOP 100
      ParticipantIdentifier,
      date,
      steps
    FROM dbo.factfitbitdailydata
    WHERE date >= '2023-01-01'
""")

print(fitbit_sample.head())
```

## 10. Connect To A Different Lakehouse Or Database

Use the `database` argument when you need a different lakehouse/database.

Available options include:

| Database | Use For |
|---|---|
| `uzima_db_backup` | Main UZIMA data, participants, surveys, Fitbit facts |
| `HCW_fitbit_data` | HCW Fitbit daily data, activity logs, sleep logs, devices, profiles |
| `Qualtrics` | Qualtrics survey response data |

Close the current connection before switching to a different database.

```python
conn.close()
```

### Connect To `HCW_fitbit_data`

```python
from fabricpy import connect_to_fabric_sql, list_sql_tables, query_sql

conn = connect_to_fabric_sql(database="HCW_fitbit_data", auth="sp_vault")

tables = list_sql_tables(conn)
print(tables)

sleep_sample = query_sql(conn, """
    SELECT TOP 100
      participantidentifier,
      date,
      totalsleepminutes,
      efficiency
    FROM dbo.fitbitsleeplogdetails
    WHERE totalsleepminutes > 0
""")

print(sleep_sample.head())

conn.close()
```

### Connect To `Qualtrics`

```python
from fabricpy import connect_to_fabric_sql, list_sql_tables, query_sql

conn = connect_to_fabric_sql(database="Qualtrics", auth="sp_vault")

tables = list_sql_tables(conn)
print(tables)

survey_sample = query_sql(conn, """
    SELECT TOP 100 *
    FROM dbo.aku_survey_responses_2026
""")

print(survey_sample.head())

conn.close()
```

### Return To The Default UZIMA Database

```python
from fabricpy import connect_to_fabric_sql, list_sql_tables

conn = connect_to_fabric_sql(auth="sp_vault")

tables = list_sql_tables(conn)
print(tables)

conn.close()
```

## 11. Complete Python Example

This is the recommended full pattern for day-to-day work:

```python
from fabricpy import connect_to_fabric_sql, list_sql_tables, query_sql, read_sql_table

conn = connect_to_fabric_sql(auth="sp_vault")

tables = list_sql_tables(conn)
print(tables)

participants = read_sql_table(
    conn,
    "dbo.dimenrolledparticipants",
    columns=["ParticipantIdentifier", "Gender", "Age"],
    top=10,
)
print(participants.head())

participant_count = query_sql(
    conn,
    "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants",
)
print(participant_count)

conn.close()
```

## 12. Important Working Rules

- Connect once at the start of your script or notebook session.
- Reuse the same `conn` object for all reads and queries.
- Close the connection once at the end with `conn.close()`.
- Do not call `connect_to_fabric_sql(auth="sp_vault")` before every query.
- Do not print, save, or share Key Vault secret values.
- Do not put service-principal credentials in notebooks or scripts.
- Use selected columns, `TOP`, and `WHERE` filters for large tables.

## 13. Troubleshooting

### `ImportError: cannot import name connect_to_fabric_sql`

You are using an old installed copy of `fabricpy`.

Update from GitHub:

Windows PowerShell:

```powershell
py -3 -m pip install --user "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --upgrade --no-cache-dir
```

Mac Terminal:

```bash
python3 -m pip install --user "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --upgrade --no-cache-dir
```

Then verify:

```python
import fabricpy

print(fabricpy.__file__)
print(fabricpy.__version__)
print(hasattr(fabricpy, "connect_to_fabric_sql"))
```

### Browser Login Does Not Open

Copy the printed `https://login.microsoft.com/device` URL into your browser and enter the printed code.

### Microsoft Authenticator Shows No Code

This is usually an account, tenant, or MFA provisioning issue rather than a Mac or Python issue.

Ask the AKU admin to confirm:

- Your account exists in the AKU tenant.
- Your account can complete MFA for tenant `4fde8ff3-4dd5-42e1-a25a-e42905610d66`.
- Your MFA method is allowed by Conditional Access.
- Your account has Key Vault access.

### Key Vault Forbidden

Ask the admin to confirm you have the `Key Vault Secrets User` role on the UZIMA Key Vault.

### ODBC Driver Error

Install Microsoft ODBC Driver 18 for SQL Server.

Mac users should also install `unixODBC`:

```bash
brew install unixodbc
```

### Fabric SQL Login Fails

Ask the admin to confirm the service principal has read access to the required Fabric workspace and lakehouse/database.

### HTTP 401 From `FabricLakehouse.list_tables()`

That is the older OneLake delegated-token path. For personal-laptop Key Vault + service-principal access, use `connect_to_fabric_sql(auth="sp_vault")`.

### A Table Name Fails

Run `list_sql_tables(conn)` first and copy the exact table name from the output. If the table includes `dbo.`, include `dbo.` in your query or `read_sql_table()` call.

## 14. Security Notes

The package includes these guardrails:

- It does not print Key Vault secret values.
- It retrieves service-principal values at runtime.
- It clears the temporary service-principal secret after minting the Fabric SQL token.
- It does not ask researchers to put credentials in notebooks.
- It sets `ApplicationIntent=ReadOnly` on the SQL connection.
- It blocks non-SELECT statements in `query_sql()`.

These package guardrails do not replace Azure/Fabric permissions. Admins must still enforce read-only Fabric access, rotate the service-principal secret before expiry, and review Key Vault audit logs.

---

*Document version 1.0 - August 2026*