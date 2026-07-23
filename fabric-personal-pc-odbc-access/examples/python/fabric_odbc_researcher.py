from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
import pandas as pd
import pyodbc

vault = SecretClient(
    vault_url="https://uzima-fabric-tokens.vault.azure.net/",
    credential=DefaultAzureCredential(),
)

connection_string = vault.get_secret("fabric-odbc-connection-string").value

# To use another database, change only the database name.
# connection_string = connection_string.replace("DATABASE=uzima_db_backup;", "DATABASE=Fitbit;")

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