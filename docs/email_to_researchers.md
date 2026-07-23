# Email to External Researchers

**Subject:** Access UZIMA Fabric Data from Your Personal PC — Setup Guide Attached

---

Dear Researcher,

You now have access to UZIMA study data from your personal PC — no VM or VPN required.

## What's New

We've added a new authentication method that lets you connect directly to Microsoft Fabric using your AKU credentials. This uses a Service Principal stored in Azure Key Vault, so you don't need to be on the approved VM.

## What You Need

1. **Windows or Mac** computer
2. **R and RStudio** installed
3. Your AKU email address (or whitelisted email)

**Works on both Windows and Mac** — no special setup needed.

## Quick Setup (5 minutes)

### Windows and Mac

1. Open RStudio and run:

```r
remotes::install_github("AKU-CDIO/fabric-inbound-access",
  subdir = "fabriconnect", force = TRUE)

library(fabriconnect)
conn <- connect_to_fabric(auth = "sp_vault")  # Opens browser for login
list_tables(conn)
```

2. A browser window will open — sign in with your AKU email
3. Done! You now have access to UZIMA data

## What You Can Do

- List all available tables
- Read study data directly into R
- Run SQL queries (joins, aggregations, filters)
- Access multiple databases (uzima_db_backup, HCW_fitbit_data, Qualtrics)

## Attached

Please find attached the **UZIMA External Access Guide** — a step-by-step document with:
- Installation instructions
- Connection examples
- SQL query examples
- Table reference
- Troubleshooting tips

## Support

If you encounter any issues:
1. Check the troubleshooting section in the guide
2. Email me at derick.imbati@aku.edu
3. Include the error message and what you were trying to do

## Next Steps

1. Complete the setup (should take ~5 minutes)
2. Try the example code in the guide
3. Let me know if you have questions

Best regards,
Derick Imbati
CDIO, Aga Khan University
derick.imbati@aku.edu

---

**Attachments:**
- UZIMA_External_Access_Guide.md (convert to Word/PDF as needed)
