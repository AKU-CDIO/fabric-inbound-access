import pandas as pd
import pyodbc

connection_string = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=fis5jjpzajqe5fxqs4z3vlsjde-zgopmz6jacoezkc3hd6da52lpm.datawarehouse.fabric.microsoft.com;"
    "DATABASE=uzima_db_backup;"
    "Authentication=ActiveDirectoryInteractive;"
    "Encrypt=yes;"
    "TrustServerCertificate=no;"
)

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