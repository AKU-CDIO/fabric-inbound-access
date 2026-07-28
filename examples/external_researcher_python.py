"""
External Researcher Example: Fabric SQL via Azure Key Vault service principal

Use this personal-laptop flow for approved researchers. It authenticates once to
Azure Key Vault, opens one Fabric SQL connection, reuses that connection for all
reads/queries, then closes it once.

Prerequisites:
  1. Your account has Key Vault Secrets User access on uzima-secrets-xfmh
  2. Create a dedicated .venv; do not install into Anaconda base
  3. Install: python -m pip install "fabricpy[sqlserver] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --no-cache-dir
  4. Install Microsoft ODBC Driver 18 for SQL Server
"""

from fabricpy import connect_to_fabric_sql, list_sql_tables, query_sql, read_sql_table

print("UZIMA researcher Fabric SQL example starting...", flush=True)
print("Authenticating once and opening one SQL connection...", flush=True)

conn = connect_to_fabric_sql(keyvault_auth_method="device_code")
try:
    tables = list_sql_tables(conn)
    print(f"Found {len(tables)} tables:")
    for table in tables[:10]:
        print(f"  - {table}")
    if len(tables) > 10:
        print(f"  ... and {len(tables) - 10} more")

    print("\nTop participants:")
    participants = read_sql_table(
        conn,
        "dbo.dimenrolledparticipants",
        columns=["ParticipantIdentifier", "Gender", "Age"],
        top=10,
    )
    print(participants.head())

    print("\nParticipant count:")
    summary = query_sql(conn, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants")
    print(summary)
finally:
    conn.close()
    print("Connection closed.", flush=True)
