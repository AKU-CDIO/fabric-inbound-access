"""
Connect to Fabric Lakehouse via OneLake HTTPS API (no TDS/ODBC needed).

Uses Azure CLI device-code authentication instead of hardcoded credentials.
All traffic is HTTPS (port 443) — bypasses the workspace IP firewall TDS bug.

Requirements:
    pip install fabricpy[pandas]
    az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
"""

from fabricpy import FabricLakehouse

def main():
    # Default Lakehouse (uzima_db_backup) from bundled config.json
    lh = FabricLakehouse()

    print("Connected to Fabric Lakehouse via OneLake HTTPS\n")

    # List tables
    tables = lh.list_tables()
    print(f"Available Tables ({len(tables)}):")
    for t in tables:
        print(f"  - {t}")

    # Read sample table
    if tables:
        sample = tables[4] if len(tables) > 4 else tables[0]
        print(f"\nReading '{sample}' (first 5 rows)...")
        df = lh.to_pandas(sample)
        print(f"  {len(df)} rows, {len(df.columns)} cols")
        print(df.head())

if __name__ == "__main__":
    main()