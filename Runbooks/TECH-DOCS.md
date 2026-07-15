# UZIMA Fabric Token Broker — Technical Documentation

## Architecture Overview

The token broker system provides automatic, VM-bound Fabric access tokens for all researchers. Tokens rotate every 45 minutes and propagate to all logged-in users instantly.

```
┌─────────────────────────────────────────────────────────────────┐
│  Azure Automation (cloud)                                       │
│  - fabric-token-broker-runbook.ps1 runs every 50 min            │
│  - POST webhook to VM:8443                                      │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  Approved VM (uzima) — 10.1.0.8                                 │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ refresh-listener.ps1 (port 8443, always running)         │   │
│  │ - Receives webhook POST from Azure Automation            │   │
│  │ - Triggers refresh-token-local.ps1                       │   │
│  └──────────────────────┬───────────────────────────────────┘   │
│                         │                                       │
│  ┌──────────────────────▼───────────────────────────────────┐   │
│  │ refresh-token-local.ps1                                   │   │
│  │ - Decrypts refresh-token.enc (machine-bound AES)          │   │
│  │ - Exchanges for fresh access_token via MS OAuth2          │   │
│  │ - Writes fab_token.txt (plain JWT)                        │   │
│  │ - Updates access-token.enc + refresh-token.enc            │   │
│  │ - Sets Machine-level FABRIC_ACCESS_TOKEN env var          │   │
│  │ - Propagates to ALL logged-in users:                      │   │
│  │   → Copies fab_token.txt to each user's profile           │   │
│  │   → Updates user registry env vars (HKCU\Environment)    │   │
│  │ - Falls back to Key Vault if local refresh fails          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Task Scheduler: UZIMA-RefreshFabricToken                  │   │
│  │ - AtStartup + every 45 min                                │   │
│  │ - Runs refresh-token-local.ps1 as SYSTEM                  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Per-user logon tasks (e.g. UZIMA-SetFabricToken-DorcasM)  │   │
│  │ - AtLogOn for each researcher                             │   │
│  │ - Runs logon-set-token.ps1 → sets user env vars           │   │
│  │ - Copies fresh fab_token.txt from broker dir              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Token files (C:\ProgramData\UZIMA\FabricTokenBroker\):         │
│  ├── access-token.enc    — current access token (AES encrypted) │
│  ├── refresh-token.enc   — refresh token (AES encrypted)        │
│  ├── fab_token.txt       — plain access token (for R/Python)    │
│  ├── researchers.json    — approved researcher list              │
│  └── whitelist.json      — email whitelist                      │
└─────────────────────────────────────────────────────────────────┘
```

## Token Refresh Chain

### 1. Scheduled Refresh (every 45 min)
- **Trigger**: Task Scheduler `UZIMA-RefreshFabricToken`
- **Runs as**: `NT AUTHORITY\SYSTEM`
- **Script**: `refresh-token-local.ps1`
- **Action**: Exchanges refresh_token for fresh access_token via MS OAuth2

### 2. Azure Automation Refresh (every 50 min)
- **Trigger**: Azure Automation runbook in cloud
- **Calls**: Webhook POST to `http://<VM-IP>:8443/refresh`
- **Received by**: `refresh-listener.ps1`
- **Action**: Triggers `refresh-token-local.ps1`

### 3. On VM Start/Restart
- **Trigger**: Task Scheduler `-AtStartup` trigger
- **Action**: Same as #1 — fresh token before anyone logs in

### 4. Per-User Logon
- **Trigger**: Per-user scheduled task `UZIMA-SetFabricToken-<username>`
- **Script**: `logon-set-token.ps1`
- **Action**: Sets user env vars + copies fab_token.txt to user profile

## Token Propagation

When `refresh-token-local.ps1` runs (via any trigger), it propagates the fresh token to **all logged-in users**:

1. Parses `quser` output to find active sessions
2. For each user with a loaded profile:
   - Copies `fab_token.txt` to `C:\Users\<username>\fab_token.txt`
   - Updates `HKU\<SID>\Environment` registry with fresh token
3. This ensures users restarting R/Python get fresh tokens immediately

**For users with active R/Python sessions:**
- The `fabriconnect` (R) and `fabricpy` (Python) packages auto-refresh tokens
- `fabricpy` has `_needs_refresh()` with 5-minute buffer before expiry
- `fabricpy` uses refresh_token to get fresh access_token transparently
- Users should **never** see 401 errors in normal operation

## File Encryption

All tokens are encrypted with machine-bound AES:

```
Key = SHA256("uzima-" + Win32_OperatingSystem.SerialNumber)
```

- **access-token.enc**: `ConvertFrom-SecureString` encrypted access_token (JWT)
- **refresh-token.enc**: `ConvertFrom-SecureString` encrypted refresh_token
- **fab_token.txt**: Plain access_token (JWT) — readable by R/Python packages

## Fallback Chain

1. **Local refresh token** → Exchange via MS OAuth2 → Fresh access_token
2. **Key Vault fallback** (if local fails):
   - Uses VM managed identity to access Key Vault
   - Pulls fresh token or uses stored refresh_token
   - Syncs back to local files

## Adding New Researchers

1. Add to `researchers.json` (vm_users + external_researchers)
2. Add to `whitelist.json`
3. Create per-user logon task:
   ```powershell
   $taskName = "UZIMA-SetFabricToken-<username>"
   $action = New-ScheduledTaskAction -Execute "powershell.exe" `
       -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\ProgramData\UZIMA\FabricTokenBroker\logon-set-token.ps1`""
   $trigger = New-ScheduledTaskTrigger -AtLogOn -User "uzima\<username>"
   Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger ...
   ```

## Troubleshooting

### Token not refreshing
- Check `refresh-log.txt` for errors
- Verify `refresh-token.enc` exists and is non-empty
- Test manually: `& "C:\ProgramData\UZIMA\FabricTokenBroker\refresh-token-local.ps1"`

### User gets 401
- Check if `fab_token.txt` exists in user profile
- Verify `FABRIC_ACCESS_TOKEN` env var is set
- Restart R/Python to pick up fresh token
- Check `refresh-log.txt` for propagation entries

### Webhook not working
- Verify `refresh-listener.ps1` is running (port 8443)
- Check firewall rule `UZIMA-Token-Listener`
- Test: `Invoke-RestMethod -Uri "http://localhost:8443/" -Method GET` → should return 404

## Key Vault Configuration

- **Vault name**: `uzima-fabric-tokens`
- **Secrets**: `fabric-access-token`, `fabric-token-expiry`, `fabric-refresh-token`
- **Access**: VM managed identity (no credentials on disk)
- **Tenant**: `a5d4252a-02f9-4e60-96f0-9733baae4919`
- **Client ID**: `1950a258-227b-4e31-a9cf-717495945fc2`
