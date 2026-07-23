from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
import pandas as pd
import pyodbc

# Change only this value when you need another database.
# Options: "uzima_db_backup", "HCW_fitbit_data", "Qualtrics"
database_name = "uzima_db_backup"

vault = SecretClient(
    vault_url="https://uzima-fabric-tokens.vault.azure.net/",
    credential=DefaultAzureCredential(),
)

connection_string = vault.get_secret("fabric-odbc-connection-string").value

if "Interactive" in connection_string:
    raise SystemExit("Key Vault ODBC secret must use managed identity auth, not browser or email sign-in.")

if "Authentication=ActiveDirectoryMsi" not in connection_string:
    raise SystemExit("Key Vault ODBC secret is missing Authentication=ActiveDirectoryMsi.")

parts = connection_string.split(";")
parts = [f"DATABASE={database_name}" if part.upper().startswith("DATABASE=") else part for part in parts]
connection_string = ";".join(parts)

table_to_read = "dbo.dimenrolledparticipants"

with pyodbc.connect(connection_string, timeout=30) as connection:
    tables = pd.read_sql(
        """
        SELECT TABLE_SCHEMA, TABLE_NAME
        FROM INFORMATION_SCHEMA.TABLES
        ORDER BY TABLE_SCHEMA, TABLE_NAME
        """,
        connection,
    )
    print(tables.head(30).to_string(index=False))

    sample = pd.read_sql(f"SELECT TOP 10 * FROM {table_to_read}", connection)
    print(sample)