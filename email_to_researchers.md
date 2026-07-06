**Subject:** Interim UZIMA Data Access on the VM – Testing Instructions

**To:** Ye Chan Kim (yechank@med.umich.edu), Kenney Brooke (nannab@med.umich.edu)

---

Hi Ye Chan and Kenney,

While the Karachi team works on granting official Fabric access to external researchers, we've set up a temporary delegated access system on the approved VM so you can start working with the data now.

**Quick start (RStudio):**
```r
library(fabriconnect)
conn <- connect_to_fabric()
tables <- list_tables(conn)
```

**Quick start (Python):**
```python
from fabricpy import FabricLakehouse
lh = FabricLakehouse()
tables = lh.list_tables()
```

No login needed — tokens are pre-configured and auto-refresh. Full documentation is in `UZIMA_Instructions.docx` on the VM.

**What's available:**
- Primary lakehouse: **uzima_db_backup** — 31 tables (Fitbit, surveys, participants, agents)
- **HCW_fitbit_data** shortcut — 5 Fitbit tables
- **Qualtrics** shortcut — `dbo.aku_survey_responses_2026`
- All accessible with the same one-liner above (change `lakehouse_guid` to switch)

**To verify it's working**, open PowerShell (not as admin) and run:
```
C:\ProgramData\UZIMA\FabricTokenBroker\test-nannab.ps1
```
If all steps show OK/Green, you're good.

**If you get errors:**
1. Log out and log back in (picks up latest settings)
2. Run `C:\ProgramData\UZIMA\FabricTokenBroker\setup-user-env.ps1` once
3. Let me know what the test script shows

The source code and runbooks are on GitHub: https://github.com/AKU-CDIO/fabric-inbound-access

Best,
Derick
