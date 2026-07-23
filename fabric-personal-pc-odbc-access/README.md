# UZIMA Fabric Data Access For Researchers

This folder uses a simple access path:

```text
Key Vault -> ODBC -> cdiofabric managed identity -> Microsoft Fabric
```

Researchers are not added directly to Fabric. Their email is used only to check that they are approved. Fabric access is done by the AKU/CDIO managed identity.

```text
Identity name: cdiofabric
Application ID: 4ae6ed7b-b72c-4853-9a3c-10699e60f63e
Object ID: 8d88bbab-1c76-4bf0-b4f7-1cb49a001d9e
```

## How It Works

1. The approved email list is stored in Key Vault.
2. The ODBC connection string is stored in Key Vault.
3. The connection string uses `Authentication=ActiveDirectoryMsi`.
4. ODBC uses `cdiofabric` to reach Fabric.
5. Fabric returns only the tables/views that `cdiofabric` is allowed to read.

Researchers should not receive Fabric tokens or raw Key Vault secrets. Their personal computer should use the AKU/CDIO approved access route. The Azure side of that route reads Key Vault and connects to Fabric.

## Key Vault Values

Vault name:

```text
uzima-fabric-tokens
```

Main ODBC secret:

```text
fabric-odbc-connection-string
```

The secret value is:

```text
DRIVER={ODBC Driver 18 for SQL Server};SERVER=fis5jjpzajqe5fxqs4z3vlsjde-zgopmz6jacoezkc3hd6da52lpm.datawarehouse.fabric.microsoft.com;DATABASE=uzima_db_backup;Authentication=ActiveDirectoryMsi;UID=4ae6ed7b-b72c-4853-9a3c-10699e60f63e;Encrypt=yes;TrustServerCertificate=no;
```

The `UID` is the `cdiofabric` Application ID/client ID.

## Changing The Database

The examples use `uzima_db_backup` by default.

To use another database, change only this part of the connection string:

```text
DATABASE=uzima_db_backup;
```

Use one of these values:

```text
DATABASE=uzima_db_backup;
DATABASE=Fitbit;
DATABASE=qualtrics;
```

In Python, this one line changes the database after reading the connection string from Key Vault:

```python
connection_string = connection_string.replace("DATABASE=uzima_db_backup;", "DATABASE=Fitbit;")
```

In R, this one line does the same:

```r
connection_string <- sub("DATABASE=uzima_db_backup;", "DATABASE=Fitbit;", connection_string)
```

## Reading One Table

After the script connects, it shows the tables/views that `cdiofabric` is allowed to read.

To read one approved table or masked view, change this line.

In Python:

```python
table_to_read = "dbo.dimenrolledparticipants"
```

In R:

```r
table_to_read <- "dbo.dimenrolledparticipants"
```

Use the approved table or masked view name provided by AKU/CDIO.

## Combining Data From Two Databases

You can combine two approved tables in one step. This is useful when, for example, you want participant age/gender from `uzima_db_backup` and Fitbit steps from `Fitbit`.

The matching ID is used only to join the tables. It is not shown in the result below.

In Python:

```python
merge_question = """
SELECT TOP 100
  p.Gender,
  p.Age,
  f.date,
  f.steps
FROM uzima_db_backup.dbo.dimenrolledparticipants p
JOIN Fitbit.dbo.fitbitdailydata f
  ON p.ParticipantIdentifier = f.participantidentifier
"""

merged_data = pd.read_sql(merge_question, connection)
print(merged_data)
```

In R:

```r
merge_question <- "
SELECT TOP 100
  p.Gender,
  p.Age,
  f.date,
  f.steps
FROM uzima_db_backup.dbo.dimenrolledparticipants p
JOIN Fitbit.dbo.fitbitdailydata f
  ON p.ParticipantIdentifier = f.participantidentifier
"

merged_data <- DBI::dbGetQuery(con, merge_question)
merged_data
```

If Fabric says a table cannot be found, the table name may be different or `cdiofabric` may not have access yet.

## Privacy Reminder

Use approved tables or masked views only.

Do not return names, emails, phone numbers, exact addresses, dates of birth, postal codes, device IDs, or direct participant identifiers unless that access has been specifically approved.

When masked views are provided, use the masked view instead of the raw table.

## Approved Researcher Emails

These emails are stored in Key Vault for the approval check:

- `derick.imbati@aku.edu`
- `rais.muhammad@aku.edu`
- `dorcasm@umich.edu`
- `yechank@med.umich.edu`
- `nannab@med.umich.edu`

## Examples

R Markdown:

- [examples/r/fabric_odbc_researcher_guide.Rmd](examples/r/fabric_odbc_researcher_guide.Rmd)

Python:

- [examples/python/fabric_odbc_researcher.py](examples/python/fabric_odbc_researcher.py)
- [examples/python/fabric_odbc_researcher.ipynb](examples/python/fabric_odbc_researcher.ipynb)

## Admin Notes

Use [scripts/set-keyvault-odbc-settings.ps1](scripts/set-keyvault-odbc-settings.ps1) to store the ODBC connection string and managed identity IDs in Key Vault.

Use [scripts/sync-keyvault-whitelist.ps1](scripts/sync-keyvault-whitelist.ps1) to update the approved email list in Key Vault.

Make sure the Azure Function, runbook worker, app service, or VM that runs ODBC has the `cdiofabric` managed identity assigned.

Then grant `cdiofabric` access in Fabric and SQL to only the approved tables or masked views.