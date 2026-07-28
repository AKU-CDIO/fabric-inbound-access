"""
External Researcher Example: Fabric SQL via Azure Key Vault service principal

Prerequisites:
  1. Your account has Key Vault Secrets User access on uzima-secrets-xfmh
  2. Create a dedicated .venv; do not install into Anaconda base
  3. Install: python -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
  4. Install Microsoft ODBC Driver 18 for SQL Server
  5. This script authenticates once in connect_to_fabric_sql(), reuses conn, then closes it
"""

from fabricpy import connect_to_fabric_sql, list_sql_tables, query_sql, read_sql_table

conn = connect_to_fabric_sql(keyvault_auth_method="device_code")

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

conn.close()
print("Connection closed.", flush=True)
