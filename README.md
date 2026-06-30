# UZIMA Fabric Data Access

This package helps approved researchers read UZIMA study data from Microsoft Fabric while staying inside the approved research VM.

The important idea is simple: **data access is VM-only**. We have enabled inbound access restrictions in Fabric, so the data can be read from the approved VM and not from personal laptops or other networks.

## What Researchers Can Do

- Sign in from the approved VM.
- See the lakehouses they have access to.
- Read tables into R or Python for analysis.
- Read only the columns they need when working with large tables.
- Use the same sign-in session without repeatedly authenticating.

## Before You Start

You need:

- Access to the approved research VM.
- Approval to use the Fabric workspace or lakehouse.
- R or Python installed on the VM.
- The package installed on the VM.

Your Azure AD identity must have access to the Fabric workspace. Contributor access works. Viewer access may need the workspace setting **OneLake data access -> Viewers can read OneLake data** enabled by an admin.

If you are outside the AKU domain, your account must be added as an approved external or guest user before access will work.

## Install in R

```r
remotes::install_github(
  "AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect",
  force = TRUE,
  upgrade_dependencies = FALSE
)
```

## Install in Python

```bash
pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall --no-cache-dir
```

## First Use

Run this from the approved VM.

```r
library(fabriconnect)
conn <- connect_to_fabric()
list_tables(conn)
```

```python
from fabricpy import FabricLakehouse
lh = FabricLakehouse()
lh.list_tables()
```

A browser sign-in may appear the first time. After the first successful sign-in, the package keeps the access token for the session and refreshes it before it expires. Researchers should not need to keep signing in for every table read.

## Read a Table

```r
df <- read_table(conn, "dimenrolledparticipants")
```

```python
df = lh.to_pandas("dimenrolledparticipants")
```

## Read Only Selected Columns

This is recommended for large tables.

```r
df <- read_table(
  conn,
  "dimenrolledparticipants",
  columns = c("ParticipantIdentifier", "Gender", "Age")
)
```

```python
df = lh.to_pandas(
  "dimenrolledparticipants",
  columns=["ParticipantIdentifier", "Gender", "Age"]
)
```

## Choose a Lakehouse

The default lakehouse is `uzima_db_backup`.

```r
conn <- connect_to_fabric(lakehouse = "HCW_fitbit_data")
```

```python
lh = FabricLakehouse(lakehouse="HCW_fitbit_data")
```

Available lakehouses include:

- `uzima_db_backup`
- `HCW_fitbit_data`
- `Qualtrics`
- `CDIOUZIMA_Azure_Storage_Accounts_Data`
- `azu_cdiouzima`
- `LS_Fabric_Lakehouse`
- `StagingLakehouseForDataflows_20251110175852`

## Optional: Run SQL Queries

Researchers who prefer SQL can query tables directly after connecting.

```r
query_tables(conn, "SELECT COUNT(*) FROM dimenrolledparticipants")
```

```python
lh.sql("SELECT COUNT(*) FROM dimenrolledparticipants")
```

## Sign-In and Token Refresh

For normal researcher use, call `connect_to_fabric()` or `FabricLakehouse()` and follow the browser sign-in prompt.

For delegated-token access, the project administrator can do the first authentication on the VM. After that, the package refreshes the token before expiry when a refresh token is available.

If a token must be supplied manually, use an environment variable rather than putting it in a script:

```bash
set FABRIC_DELEGATED_ACCESS_TOKEN=<delegated-token>
```

The token can be pasted as the raw token or as `Bearer <token>`.

## Privacy and PII

Sample files shared with researchers should not contain direct personal identifiers. Use the masked sample workbooks for sharing examples outside the secure access workflow.

The real study data remains protected in Fabric and should be accessed only from the approved VM by approved users.

## Common Issues

### I cannot connect from my laptop

That is expected. Fabric inbound access is restricted to the approved VM.

### I see a sign-in prompt

Sign in with the account that has been approved for the Fabric workspace. External users must be added before they can access the data.

### I get a permission or forbidden message

Ask the project administrator to confirm that your account has access to the correct workspace and lakehouse.

### A table is very large

Read only the columns you need. This reduces memory use and makes analysis faster.

### GitHub install fails with a rate-limit message

GitHub limits unauthenticated installs. Wait and try again, or ask the project administrator to install from the VM with a GitHub token.

## Support

Contact the UZIMA/CDIO data team if access fails from the approved VM or if your account needs to be added.

## License

Apache 2.0