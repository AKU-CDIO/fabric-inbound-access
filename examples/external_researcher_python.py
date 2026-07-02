"""
External Researcher Example: UZIMA Fabric Data Access

Prerequisites:
  1. Your email must be added to the whitelist by the admin
  2. Run once: setx FABRIC_RESEARCHER_EMAIL your.email@umich.edu
  3. Install: pip install "fabricpy[pandas,sql] @ git+https://github.com/AKU-CDIO/fabric-inbound-access.git#subdirectory=fabriconnectpy" --force-reinstall --no-cache-dir
"""

import os
from fabricpy import FabricLakehouse

# The package reads your email from the environment variable
email = os.environ.get("FABRIC_RESEARCHER_EMAIL")
if not email:
    print("ERROR: Set FABRIC_RESEARCHER_EMAIL first:")
    print("  setx FABRIC_RESEARCHER_EMAIL your.email@umich.edu")
    print("  Then restart this terminal.")
    exit(1)

print(f"Connecting as {email}...")

# Connect — the package automatically calls the token broker webhook
lh = FabricLakehouse()

# List all available tables
tables = lh.list_tables()
print(f"\nFound {len(tables)} tables:")
for t in tables[:10]:
    print(f"  - {t}")
if len(tables) > 10:
    print(f"  ... and {len(tables) - 10} more")

# Read a table as pandas DataFrame
print("\nReading dimenrolledparticipants (first 5 rows)...")
df = lh.to_pandas("dimenrolledparticipants", columns=["ParticipantIdentifier", "Gender", "Age"])
print(df.head())
print(f"\nShape: {df.shape}")

# SQL query across tables (requires duckdb)
print("\nRunning SQL query...")
try:
    result = lh.sql("SELECT COUNT(*) cnt FROM dimenrolledparticipants")
    print(result)
except Exception as e:
    print(f"  Skipped: {e}")
    print("  (Install duckdb for SQL support: pip install duckdb)")

# Work with a different lakehouse
print("\nSwitching to HCW_fitbit_data...")
hcw = FabricLakehouse(lakehouse="HCW_fitbit_data")
hcw_tables = hcw.list_tables()
print(f"Found {len(hcw_tables)} tables in HCW_fitbit_data:")
for t in hcw_tables[:5]:
    print(f"  - {t}")

# Cross-lakehouse SQL query
if len(tables) > 0 and len(hcw_tables) > 0:
    print("\nCross-lakehouse query (requires duckdb)...")
    try:
        result = FabricLakehouse.cross_query(
            {"uzima": lh, "hcw": hcw},
            """SELECT p.ParticipantIdentifier, p.Gender
               FROM uzima.dimenrolledparticipants p
               LIMIT 5"""
        )
        print(result)
    except Exception as e:
        print(f"  Skipped: {e}")
