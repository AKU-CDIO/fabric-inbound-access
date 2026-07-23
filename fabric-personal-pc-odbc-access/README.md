# UZIMA Fabric Data Access For Researchers

This folder is for researchers who need to read approved UZIMA data from their own computer.

It uses a normal ODBC connection to Microsoft Fabric. It is not part of the `fabriconnect` or `fabricpy` libraries, and it does not use the delegated token runbook.

Each researcher signs in with their own approved Microsoft account. No shared Fabric token is given to researchers.

## How Access Works

1. The researcher is approved by AKU/CDIO.
2. The researcher is added to Microsoft Fabric with their email address.
3. The researcher runs one of the examples in this folder.
4. A Microsoft sign-in window opens.
5. The researcher signs in with the approved email.
6. The script lists the tables/views they are allowed to read.
7. The researcher reads a small sample from an approved table or masked view.

Key Vault is only for admin tracking of the approved email list. Researchers do not need Key Vault access.

## Current Fabric Connection

The examples already contain this Fabric server:

```text
fis5jjpzajqe5fxqs4z3vlsjde-zgopmz6jacoezkc3hd6da52lpm.datawarehouse.fabric.microsoft.com
```

The examples use `uzima_db_backup` by default.

The available database names are:

- `uzima_db_backup`
- `Fitbit`
- `qualtrics`

## Changing The Database

In the R and Python examples, find this line inside the connection string:

```text
DATABASE=uzima_db_backup;
```

To use Fitbit data, change it to:

```text
DATABASE=Fitbit;
```

To use Qualtrics data, change it to:

```text
DATABASE=qualtrics;
```

That is the only change needed to open a different database.

## Reading One Table

After the script connects, it shows the tables/views you are allowed to read.

To read one table, change the table name line.

In R:

```r
table_to_read <- "dbo.dimenrolledparticipants"
```

In Python:

```python
table_to_read = "dbo.dimenrolledparticipants"
```

Use the table or masked view name your AKU/CDIO contact gave you.

## Combining Data From Two Databases

You can combine two approved tables in one step. This is useful when, for example, you want participant details from `uzima_db_backup` and Fitbit steps from `Fitbit`.

Use this only when you have been approved for both datasets.

In R:

```r
merge_question <- "
SELECT TOP 100
  p.ParticipantIdentifier,
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

In Python:

```python
merge_question = """
SELECT TOP 100
  p.ParticipantIdentifier,
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

If Fabric says a table cannot be found, check the table list shown by the script. The table name may be different, or your account may not yet have access.

## Privacy Reminder

Researchers should use approved tables or masked views only.

Do not read columns such as names, emails, phone numbers, exact addresses, dates of birth, postal codes, device IDs, or direct participant identifiers unless that access has been specifically approved.

When masked views are provided, use the masked view instead of the raw table.

## Approved Researchers

Current approved emails for the Key Vault whitelist:

- `derick.imbati@aku.edu`
- `rais.muhammad@aku.edu`
- `dorcasm@umich.edu`
- `yechank@med.umich.edu`
- `nannab@med.umich.edu`

Note: `rais.muhammad@aku.edu` was found in local Azure activity records, but `az ad user show --id rais.muhammad@aku.edu` did not resolve in the current Azure CLI session. Ask an Entra admin or someone with Directory Readers to confirm Rais's exact user principal name or object ID.

## Researcher Setup

Install:

- Microsoft ODBC Driver 18 for SQL Server
- For R: RStudio, `DBI`, and `odbc`
- For Python: Python, `pyodbc`, and `pandas`

## R Markdown Example

Open [examples/r/fabric_odbc_researcher_guide.Rmd](examples/r/fabric_odbc_researcher_guide.Rmd) in RStudio and run the sections from top to bottom.

## Python Examples

Use either:

- [examples/python/fabric_odbc_researcher.py](examples/python/fabric_odbc_researcher.py)
- [examples/python/fabric_odbc_researcher.ipynb](examples/python/fabric_odbc_researcher.ipynb)

## Admin Notes

For personal PC access, public access to the Fabric SQL analytics endpoint must be allowed. Then rely on Microsoft sign-in, Fabric permissions, and SQL permissions.

Researchers should be granted access only to approved tables or masked views. Do not grant raw PII tables unless that has been explicitly approved.

Use [scripts/sync-keyvault-whitelist.ps1](scripts/sync-keyvault-whitelist.ps1) to update the approved email list in Key Vault.

Use [scripts/check-azure-users.ps1](scripts/check-azure-users.ps1) to check whether emails resolve in the current Azure tenant.

## Important Notes

- ODBC access does not use the token broker or delegated refresh token.
- ODBC access does not need the R/Python package auth helpers.
- Researchers authenticate as themselves.
- If a researcher can sign in but sees no tables, check Fabric workspace, SQL endpoint, and SQL permissions.
- If a researcher cannot connect at all, check that network restrictions were lifted for the SQL endpoint and that ODBC Driver 18 is installed.