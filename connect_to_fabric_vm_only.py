import pyodbc

# Configuration
lakehouse_endpoint = "fis5jjpzajqe5fxqs4z3vlsjde-zgopmz6jacoezkc3hd6da52lpm.datawarehouse.fabric.microsoft.com"
database_name = "uzima_db_backup"
user_id = "derick.imbati@aku.edu"

# Connection String
conn_str = (
    f"Driver={{ODBC Driver 17 for SQL Server}};"
    f"Server={lakehouse_endpoint};"
    f"Database={database_name};"
    f"UID={user_id};"
    f"PWD=Pass@123;"
    f"Authentication=ActiveDirectoryPassword;"
    f"Encrypt=yes;"
    f"TrustServerCertificate=yes;"
    f"Port=1433;"
    f"Timeout=30;"
)

try:
    # Establish connection
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()
    print("Connected to Fabric Lakehouse SQL endpoint")

    # List tables (Equivalent to the 'tables' call in your R snippet)
    print("\nAvailable Tables:")
    for table_info in cursor.tables(tableType='TABLE'):
        print(table_info.table_name)

except Exception as e:
    print(f"Error connecting to database: {e}")

finally:
    # Clean up connection
    if 'conn' in locals():
        conn.close()