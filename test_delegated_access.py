"""
Manual delegated-access smoke test - no setup needed.
Run directly with: python test_delegated_access.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def main():
    os.environ.pop("FABRIC_ACCESS_TOKEN", None)

    from fabricpy import FabricLakehouse

    lh = FabricLakehouse()
    tables = lh.list_tables()
    print(f"OK - {len(tables)} tables found")
    for t in tables[:10]:
        print(f"  - {t}")
    print(f"  ... and {len(tables) - 10} more")


if __name__ == "__main__":
    main()