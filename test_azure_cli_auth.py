"""
Test fabricpy with Azure CLI authentication
"""

import sys
import os

# Add the local fabricpy directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def test_azure_cli_auth():
    """Test that fabricpy can use Azure CLI authentication"""
    print("Testing fabricpy with Azure CLI authentication...")
    
    try:
        from fabricpy import FabricLakehouse
        
        # Initialize with default settings (should use Azure CLI since we're logged in)
        print("Initializing FabricLakehouse...")
        lh = FabricLakehouse()
        
        print("Attempting to list tables using Azure CLI authentication...")
        tables = lh.list_tables()
        
        print(f"SUCCESS: Listed {len(tables)} tables")
        print("First 10 tables:")
        for table in tables[:10]:
            print(f"  - {table}")
        
        return True, tables
        
    except Exception as e:
        print(f"FAILED: {e}")
        import traceback
        traceback.print_exc()
        return False, None

def test_token_directly():
    """Test getting token directly via Azure CLI"""
    print("\nTesting direct Azure CLI token retrieval...")
    
    try:
        import subprocess
        
        result = subprocess.run(
            "az account get-access-token --resource https://storage.azure.com "
            "--tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --query accessToken -o tsv",
            capture_output=True, text=True, timeout=30, shell=True
        )
        
        if result.returncode != 0:
            print(f"FAILED: Azure CLI command failed: {result.stderr}")
            return False, None
        
        token = result.stdout.strip()
        if not token:
            print("FAILED: Empty token returned")
            return False, None
        
        print(f"SUCCESS: Got token (length: {len(token)} chars)")
        print(f"Token starts with: {token[:20]}...")
        
        return True, token
        
    except Exception as e:
        print(f"FAILED: {e}")
        import traceback
        traceback.print_exc()
        return False, None

def main():
    print("=" * 60)
    print("Testing Azure CLI Authentication for fabricpy")
    print("=" * 60)
    
    # Test direct token retrieval
    token_success, token = test_token_directly()
    
    # Test fabricpy with Azure CLI auth
    fabricpy_success, tables = test_azure_cli_auth()
    
    print("\n" + "=" * 60)
    print("Test Results Summary")
    print("=" * 60)
    print(f"Direct Azure CLI Token: {'PASS' if token_success else 'FAIL'}")
    print(f"fabricpy Azure CLI Auth: {'PASS' if fabricpy_success else 'FAIL'}")
    
    if fabricpy_success:
        print(f"\nSUCCESS: Azure CLI authentication works with fabricpy!")
        print(f"Total tables accessible: {len(tables)}")
        return 0
    else:
        print(f"\nFAILURE: Azure CLI authentication failed")
        return 1

if __name__ == "__main__":
    sys.exit(main())
