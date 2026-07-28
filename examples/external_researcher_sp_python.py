"""
External Researcher Example: Fabric SQL via Azure Key Vault service principal

Prerequisites:
  1. Your account has Key Vault Secrets User access on uzima-secrets-xfmh
  2. Run: az login --tenant 4fde8ff3-4dd5-42e1-a25a-e42905610d66
  3. Install: pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall --no-cache-dir
  4. Install Microsoft ODBC Driver 18 for SQL Server
"""

from fabricpy import connect_to_fabric_sql, list_sql_tables, query_sql, read_sql_table

conn = connect_to_fabric_sql()
try:
    print("Connected via Key Vault service-principal access.\n")

    tables = list_sql_tables(conn)
    print(f"Found {len(tables)} tables:")
    for table in tables[:10]:
        print(f"  - {table}")
    if len(tables) > 10:
        print(f"  ... and {len(tables) - 10} more")

    print("\nTop participants:")
    df = read_sql_table(
        conn,
        "dbo.dimenrolledparticipants",
        columns=["ParticipantIdentifier", "Gender", "Age"],
        top=10,
    )
    print(df)

    print("\nParticipant count:")
    print(query_sql(conn, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants"))
finally:
    conn.close()
