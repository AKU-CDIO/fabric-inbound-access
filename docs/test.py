from fabricpy import connect_to_fabric_sql, list_sql_tables, query_sql, read_sql_table

print("UZIMA Fabric SQL test starting...", flush=True)
print("Authenticating once, opening one Fabric SQL connection...", flush=True)

conn = connect_to_fabric_sql(keyvault_auth_method="device_code")
try:
    tables = list_sql_tables(conn)
    print(f"Found {len(tables)} tables", flush=True)
    print(tables[:10], flush=True)

    df = read_sql_table(conn, "dbo.dimenrolledparticipants", top=10)
    print(df.head(), flush=True)

    summary = query_sql(conn, "SELECT COUNT(*) AS total FROM dbo.dimenrolledparticipants")
    print(summary, flush=True)

    print("SUCCESS: Fabric SQL access via Key Vault + service principal is working.", flush=True)
finally:
    conn.close()
    print("Connection closed.", flush=True)