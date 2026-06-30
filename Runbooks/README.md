# UZIMA Fabric Token Broker

## For Researchers

**There's nothing to install or run.** Just use R or Python as normal.

Once the admin sets up the webhook URL on the VM, set your email once:

```
setx FABRIC_RESEARCHER_EMAIL your.email@umich.edu
```

Then `connect_to_fabric()` or `FabricLakehouse()` automatically calls the token broker in the background — no bat files, no browser sign-in, no separate login step.

See [RESEARCHER-GUIDE.md](RESEARCHER-GUIDE.md).

---

## For Admins — Deployment

### How it works

You authenticate **once** via device code on the VM. The refresh token is stored in Azure Key Vault. An Azure Automation Runbook keeps it fresh and hands short-lived access tokens to approved researchers — but only when they call from the VM.

**3-layer security:**
| Layer | Check | Where |
|-------|-------|-------|
| 1 | VM hostname (`admindsvm`) | R/Python package |
| 2 | Caller IP (`4.245.225.10` / `102.0.6.106`) | Runbook checks webhook caller |
| 3 | Email in whitelist | Runbook checks Key Vault |

### Deploy

Double-click **`setup.bat`** on the VM, or run:

```powershell
.\Runbooks\deploy-token-broker.ps1 -Mode AzureAutomation
```

A browser opens. Sign in with your Azure AD account. The script stores the refresh token in Key Vault.

### After deployment

| Step | What |
|------|------|
| 1 | Import `fabric-token-broker-runbook.ps1` into Azure Automation → **Webhook** |
| 2 | Import `refresh-token-scheduled.ps1` → **Schedule** (every 50 min) |
| 3 | Grant the Automation RunAs Account `Get/Set/List` secrets on the Key Vault |
| 4 | **Set `FABRIC_WEBHOOK_URL` as a System env var on the VM** |
| 5 | Researchers set `FABRIC_RESEARCHER_EMAIL` and use R/Python normally |

### Managing the whitelist

**Add a researcher:**
```powershell
Invoke-RestMethod -Method Post -Uri $WEBHOOK_URL `
  -Body '{"action":"add_email","admin_email":"you@aku.edu","email":"new@umich.edu"}' `
  -ContentType "application/json"
```

**Remove:**
```powershell
Invoke-RestMethod -Method Post -Uri $WEBHOOK_URL `
  -Body '{"action":"remove_email","admin_email":"you@aku.edu","email":"old@umich.edu"}' `
  -ContentType "application/json"
```

### Files

| File | What |
|------|------|
| `setup.bat` | Double-click to deploy |
| `deploy-token-broker.ps1` | Device-code auth → stores refresh token in Key Vault |
| `fabric-token-broker-runbook.ps1` | Azure Automation webhook — validates email/IP, returns token |
| `refresh-token-scheduled.ps1` | Azure Automation schedule — refreshes token every 50 min |
| `whitelist.json` | Sample whitelist |
| `RESEARCHER-GUIDE.md` | Instructions for researchers |
