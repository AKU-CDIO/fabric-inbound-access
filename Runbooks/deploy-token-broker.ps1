<#
.SYNOPSIS
    Deploy the Fabric Token Broker — initial setup script
.DESCRIPTION
    Run this on the approved VM (admindsvm) to:
      1. Authenticate via device code (admin) to get a refresh token
      2. Deploy the refresh token to Azure Key Vault or store locally
      3. Set up a Windows Scheduled Task to refresh the token every 50 min
         (local mode) OR print instructions for Azure Automation deployment
      4. Save the whitelist of approved researcher emails

    Choose between two modes:
      - AzureAutomation:  Token stored in Key Vault, refreshed by Azure Runbook
      - LocalVM:          Token stored encrypted on VM, refreshed by Scheduled Task

.PARAMETER Mode
    "AzureAutomation" (default) or "LocalVM"

.PARAMETER KeyVaultName
    Required for AzureAutomation mode. Name of Key Vault to store tokens.

.PARAMETER SkipAuth
    Skip initial device-code auth (if refresh token already available).
#>

param(
    [ValidateSet("AzureAutomation", "LocalVM")]
    [string]$Mode = "AzureAutomation",
    [string]$KeyVaultName = "uzima-fabric-tokens",
    [switch]$SkipAuth
)

$TENANT_ID        = "a5d4252a-02f9-4e60-96f0-9733baae4919"
$STORAGE_RESOURCE = "https://storage.azure.com"
$CLIENT_ID        = "1950a258-227b-4e31-a9cf-717495945fc2"
$ALLOWED_VM_HOST  = "admindsvm"
$TOKEN_DIR        = "$env:PROGRAMDATA\UZIMA\FabricTokenBroker"

function Assert-AdminVm {
    $hostname = $env:COMPUTERNAME.ToLower()
    if ($hostname -notlike "$ALLOWED_VM_HOST*") {
        Write-Error "This script must run on the approved VM ($ALLOWED_VM_HOST). Current: $hostname"
        exit 1
    }
}

function Get-MachineKey {
    $serial = try {
        (Get-WmiObject Win32_OperatingSystem).SerialNumber
    } catch { "FALLBACK-KEY" }
    $combined = "$ALLOWED_VM_HOST-$serial"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [Text.Encoding]::UTF8.GetBytes($combined)
    $hash = $sha.ComputeHash($bytes)
    return [Convert]::ToBase64String($hash)
}

function Protect-String {
    param([string]$PlainText)
    $key = Get-MachineKey
    $secure = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
    $encrypted = ConvertFrom-SecureString -SecureString $secure -Key ([Text.Encoding]::UTF8.GetBytes($key.Substring(0, 32)))
    return $encrypted
}

function Unprotect-String {
    param([string]$EncryptedString)
    $key = Get-MachineKey
    $secure = ConvertTo-SecureString -String $EncryptedString -Key ([Text.Encoding]::UTF8.GetBytes($key.Substring(0, 32)))
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Do-DeviceCodeAuth {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  UZIMA Fabric Token Broker — Admin Auth" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "You'll authenticate with your Azure AD account (device code flow)." -ForegroundColor White
    Write-Host "This grants a refresh token that will be stored securely and used" -ForegroundColor White
    Write-Host "to generate access tokens for approved researchers." -ForegroundColor White
    Write-Host ""

    # Request device code
    $deviceCodeBody = @{
        client_id = $CLIENT_ID
        scope     = "$STORAGE_RESOURCE/.default offline_access"
    }
    $deviceCodeUrl = "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/devicecode"
    $deviceCodeResp = Invoke-RestMethod -Method Post -Uri $deviceCodeUrl -Body $deviceCodeBody -ContentType "application/x-www-form-urlencoded"

    Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "│  OPEN YOUR BROWSER AND NAVIGATE TO:" -ForegroundColor Yellow
    Write-Host "│  $($deviceCodeResp.verification_uri)" -ForegroundColor White
    Write-Host "│" -ForegroundColor Yellow
    Write-Host "│  ENTER THE CODE: $($deviceCodeResp.user_code)" -ForegroundColor Cyan
    Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Waiting for authentication..." -ForegroundColor Gray

    $interval = [Math]::Max(2, [int]$deviceCodeResp.interval)
    $deadline = (Get-Date).AddSeconds([int]$deviceCodeResp.expires_in)
    $tokenUrl = "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token"

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $interval
        try {
            $tokenBody = @{
                grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
                client_id   = $CLIENT_ID
                device_code = $deviceCodeResp.device_code
            }
            $tokenResp = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $tokenBody -ContentType "application/x-www-form-urlencoded"

            Write-Host "`nAuthentication successful!" -ForegroundColor Green
            return @{
                access_token  = $tokenResp.access_token
                refresh_token = $tokenResp.refresh_token
            }
        } catch {
            $errBody = $_.Exception.Response
            if ($errBody) {
                $reader = New-Object System.IO.StreamReader($errBody.GetResponseStream())
                $errText = $reader.ReadToEnd() | ConvertFrom-Json
                if ($errText.error -eq "authorization_pending") { continue }
                if ($errText.error -eq "slow_down") { $interval += 5; continue }
                if ($errText.error -eq "expired_token") {
                    Write-Error "Device code expired. Run this script again."
                    return $null
                }
                if ($errText.error -eq "access_denied") {
                    Write-Error "Authentication cancelled."
                    return $null
                }
            }
            Write-Error "Auth error: $_"
            return $null
        }
    }
    Write-Error "Authentication timed out."
    return $null
}

# ─── Azure Automation Mode ───────────────────────────────────────────────
function Deploy-AzureAutomation {
    param($Tokens)

    if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
        Write-Warning "Azure CLI not found. Install it from https://aka.ms/installazurecliwindows"
        Write-Host "You'll need to manually store the refresh token in Key Vault."
        Write-Host ""
        Write-Host "Refresh token (COPY THIS NOW):" -ForegroundColor Yellow
        Write-Host $Tokens.refresh_token -ForegroundColor White
        Write-Host ""
        Write-Host "Then run:" -ForegroundColor Cyan
        Write-Host "  az keyvault secret set --vault-name $KeyVaultName --name fabric-refresh-token --value '<token>'" -ForegroundColor Gray
        return
    }

    Write-Host "`nStoring refresh token in Key Vault '$KeyVaultName'..." -ForegroundColor Cyan

    # Check if Key Vault exists
    $kvCheck = az keyvault show --name $KeyVaultName 2>$null
    if (-not $kvCheck) {
        Write-Host "Key Vault '$KeyVaultName' not found. Creating..." -ForegroundColor Yellow
        $rg = Read-Host "Azure Resource Group name"
        az keyvault create --name $KeyVaultName --resource-group $rg --location eastus | Out-Null
        Write-Host "Key Vault created." -ForegroundColor Green
    }

    # Store secrets
    $expiry = [int][double]::Parse((Get-Date -UFormat %s)) + 3300
    az keyvault secret set --vault-name $KeyVaultName --name "fabric-refresh-token" --value $Tokens.refresh_token | Out-Null
    az keyvault secret set --vault-name $KeyVaultName --name "fabric-access-token" --value $Tokens.access_token | Out-Null
    az keyvault secret set --vault-name $KeyVaultName --name "fabric-token-expiry" --value $expiry | Out-Null

    # Store initial whitelist
    $whitelist = @(
        "your-admin-email@aku.edu",
        "yechank@med.umich.edu",
        "nannab@med.umich.edu"
    ) | ConvertTo-Json -Compress
    az keyvault secret set --vault-name $KeyVaultName --name "researcher-whitelist" --value $whitelist | Out-Null

    Write-Host "`n✓ Secrets stored in Key Vault '$KeyVaultName'" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Import the runbooks into Azure Automation:" -ForegroundColor White
    Write-Host "     - fabric-token-broker-runbook.ps1  (HTTP Webhook)" -ForegroundColor Gray
    Write-Host "     - refresh-token-scheduled.ps1      (Schedule: every 50 min)" -ForegroundColor Gray
    Write-Host "  2. Grant Automation RunAs Account access to Key Vault:" -ForegroundColor White
    Write-Host "     az keyvault set-policy --name $KeyVaultName --object-id <runas-sp-oid> --secret-permissions get list set" -ForegroundColor Gray
    Write-Host "  3. Share the webhook URL with VM researchers" -ForegroundColor White
    Write-Host "  4. Set FABRIC_WEBHOOK_URL env var on the VM for vm-token-client.ps1" -ForegroundColor Gray
}

# ─── Local VM Mode ────────────────────────────────────────────────────────
function Deploy-LocalVM {
    param($Tokens)

    Write-Host "`nStoring tokens locally on VM (machine-bound encryption)..." -ForegroundColor Cyan

    # Create directory with admin-only ACL
    if (-not (Test-Path $TOKEN_DIR)) {
        New-Item -ItemType Directory -Path $TOKEN_DIR -Force | Out-Null
    }
    icacls $TOKEN_DIR /inheritance:r /grant:r "$env:USERNAME`:F" /T 2>$null | Out-Null

    # Save refresh token (encrypted)
    $encryptedRefresh = Protect-String $Tokens.refresh_token
    $encryptedRefresh | Set-Content "$TOKEN_DIR\refresh-token.enc" -Force

    # Save access token + expiry (encrypted)
    $tokenData = @{
        access_token = $Tokens.access_token
        expiry       = [int][double]::Parse((Get-Date -UFormat %s)) + 3300
    } | ConvertTo-Json
    $encryptedAccess = Protect-String $tokenData
    $encryptedAccess | Set-Content "$TOKEN_DIR\access-token.enc" -Force

    # Save whitelist
    $whitelist = @(
        @{ email = "your-admin-email@aku.edu"; name = "Admin"; active = $true },
        @{ email = "yechank@med.umich.edu"; name = "Ye Chan Kim"; active = $true },
        @{ email = "nannab@med.umich.edu"; name = "Kenney Brooke"; active = $true }
    )
    $whitelist | ConvertTo-Json -Depth 5 | Out-File "$TOKEN_DIR\whitelist.json" -Encoding utf8
    icacls "$TOKEN_DIR\whitelist.json" /inheritance:r /grant:r "$env:USERNAME`:F" 2>$null | Out-Null

    # Set up scheduled task for token refresh
    $refreshScriptPath = "$TOKEN_DIR\refresh-token-task.ps1"
    $refreshScript = @"
`$TENANT_ID = "$TENANT_ID"
`$STORAGE_RESOURCE = "$STORAGE_RESOURCE"
`$CLIENT_ID = "$CLIENT_ID"
`$TOKEN_DIR = "$TOKEN_DIR"

function Get-MachineKey {
    `$serial = (Get-WmiObject Win32_OperatingSystem).SerialNumber
    `$combined = "$ALLOWED_VM_HOST-`$serial"
    `$sha = [System.Security.Cryptography.SHA256]::Create()
    `$hash = `$sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(`$combined))
    return [Convert]::ToBase64String(`$hash)
}

function Unprotect-String {
    param(`$EncryptedString)
    `$key = Get-MachineKey
    `$secure = ConvertTo-SecureString -String `$EncryptedString -Key ([Text.Encoding]::UTF8.GetBytes(`$key.Substring(0, 32)))
    `$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(`$secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR(`$ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(`$ptr) }
}

try {
    `$encrypted = Get-Content "$TOKEN_DIR\refresh-token.enc" -Raw
    `$refreshToken = Unprotect-String `$encrypted

    `$body = @{
        grant_type = "refresh_token"
        client_id  = `$CLIENT_ID
        refresh_token = `$refreshToken
        scope = "`$STORAGE_RESOURCE/.default offline_access"
    }
    `$url = "https://login.microsoftonline.com/`$TENANT_ID/oauth2/v2.0/token"
    `$response = Invoke-RestMethod -Method Post -Uri `$url -Body `$body -ContentType "application/x-www-form-urlencoded"

    `$newRefresh = if (`$response.refresh_token) { `$response.refresh_token } else { `$refreshToken }
    `$encryptedRefresh = ConvertFrom-SecureString -SecureString (ConvertTo-SecureString -String `$newRefresh -AsPlainText -Force) -Key ([Text.Encoding]::UTF8.GetBytes((Get-MachineKey).Substring(0, 32)))
    `$encryptedRefresh | Set-Content "$TOKEN_DIR\refresh-token.enc" -Force

    `$tokenData = @{ access_token = `$response.access_token; expiry = [int][double]::Parse((Get-Date -UFormat %s)) + 3300 } | ConvertTo-Json
    `$encryptedAccess = ConvertFrom-SecureString -SecureString (ConvertTo-SecureString -String `$tokenData -AsPlainText -Force) -Key ([Text.Encoding]::UTF8.GetBytes((Get-MachineKey).Substring(0, 32)))
    `$encryptedAccess | Set-Content "$TOKEN_DIR\access-token.enc" -Force

    Write-Output "Token refreshed at `$(Get-Date)"
} catch {
    Write-Error "Refresh failed: `$_"
    exit 1
}
"@
    $refreshScript | Set-Content $refreshScriptPath -Force

    # Create scheduled task
    $taskName = "UZIMA-FabricTokenRefresh"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$refreshScriptPath`""
    $trigger = New-ScheduledTaskTrigger -Daily -At "00:00" -RepetitionInterval (New-TimeSpan -Minutes 50) -RepetitionDuration (New-TimeSpan -Days 365)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force

    Write-Host "`n✓ Local token broker deployed!" -ForegroundColor Green
    Write-Host "  Token directory: $TOKEN_DIR" -ForegroundColor Gray
    Write-Host "  Scheduled task:  $taskName (every 50 min)" -ForegroundColor Gray
    Write-Host "  Whitelist:       $TOKEN_DIR\whitelist.json" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Researchers run:" -ForegroundColor Cyan
    Write-Host "  .\vm-token-client-local.ps1  (from this VM)" -ForegroundColor White
}

# ─── Main ────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     UZIMA Fabric Token Broker — Deployment        ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Assert-AdminVm

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Not running as Administrator. Some features (Scheduled Task) may fail."
    $cont = Read-Host "Continue anyway? (y/N)"
    if ($cont -ne "y") { exit }
}

# Authenticate
$tokens = $null
if (-not $SkipAuth) {
    $tokens = Do-DeviceCodeAuth
    if (-not $tokens) { exit 1 }
} else {
    Write-Host "Skipping auth (use -SkipAuth only if tokens already stored)." -ForegroundColor Yellow
}

# Deploy
switch ($Mode) {
    "AzureAutomation" {
        if ($tokens) { Deploy-AzureAutomation -Tokens $tokens }
        else { Write-Error "Cannot deploy: no tokens available. Remove -SkipAuth."; exit 1 }
    }
    "LocalVM" {
        if ($tokens) { Deploy-LocalVM -Tokens $tokens }
        else { Write-Error "Cannot deploy: no tokens available. Remove -SkipAuth."; exit 1 }
    }
}

Write-Host "`nDone." -ForegroundColor Green
