<#
.SYNOPSIS
    Local VM Token Client — for use with LocalVM deployment mode
.DESCRIPTION
    When the token broker is deployed in LocalVM mode (tokens stored
    on the VM with machine-bound encryption, refreshed by a Windows
    Scheduled Task), researchers use this script to:
      1. Verify they're on the approved VM
      2. Enter their email
      3. Have it checked against the local whitelist
      4. Get the current access token
      5. Set $env:FABRIC_DELEGATED_ACCESS_TOKEN
      6. Launch an R/Python session

.PARAMETER ResearcherEmail
    Email of the researcher. If omitted, prompts interactively.

.PARAMETER NoLaunch
    If set, prints the token instead of launching a shell.

.EXAMPLE
    .\vm-token-client-local.ps1
    .\vm-token-client-local.ps1 -ResearcherEmail yechank@med.umich.edu
#>

param(
    [string]$ResearcherEmail,
    [switch]$NoLaunch
)

$ALLOWED_VM_HOST = "admindsvm"
$ALLOWED_VM_IPS  = @("4.245.225.10", "102.0.6.106")
$TOKEN_DIR       = "$env:PROGRAMDATA\UZIMA\FabricTokenBroker"
$TOKEN_FILE      = "$TOKEN_DIR\access-token.enc"
$WHITELIST_FILE  = "$TOKEN_DIR\whitelist.json"

function Assert-Vm {
    $hostname = $env:COMPUTERNAME.ToLower()
    if ($hostname -notlike "$ALLOWED_VM_HOST*") {
        Write-Error "This script can only run on the approved UZIMA VM. Current: $hostname"
        exit 1
    }
    try {
        $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
        if ($publicIp -notin $ALLOWED_VM_IPS) {
            Write-Warning "Public IP ($publicIp) not in VM whitelist."
        }
    } catch { }
}

function Get-MachineKey {
    $serial = try { (Get-WmiObject Win32_OperatingSystem).SerialNumber } catch { "FALLBACK-KEY" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("$ALLOWED_VM_HOST-$serial")))
}

function Unprotect-String {
    param([string]$EncryptedString)
    $key = Get-MachineKey
    $secure = ConvertTo-SecureString -String $EncryptedString -Key ([Text.Encoding]::UTF8.GetBytes($key.Substring(0, 32)))
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Test-EmailFormat {
    param([string]$Email)
    return $Email -match '^[^@\s]+@[^@\s]+\.[^@\s]+$'
}

# ─── Main ────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  UZIMA Fabric Token Client (Local Mode) ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

Assert-Vm

# Check token broker is deployed
if (-not (Test-Path $TOKEN_FILE)) {
    Write-Error "Token broker not deployed. Ask admin to run deploy-token-broker.ps1 -Mode LocalVM"
    exit 1
}
if (-not (Test-Path $WHITELIST_FILE)) {
    Write-Error "Whitelist not found. Ask admin to run deploy-token-broker.ps1"
    exit 1
}

# Get researcher email
if (-not $ResearcherEmail) {
    $ResearcherEmail = Read-Host "Enter your email address"
}
while (-not (Test-EmailFormat $ResearcherEmail)) {
    Write-Host "Invalid email format." -ForegroundColor Yellow
    $ResearcherEmail = Read-Host "Enter your email address"
}

# Check whitelist
$whitelist = Get-Content $WHITELIST_FILE -Raw | ConvertFrom-Json
$matched = $whitelist | Where-Object { $_.email -eq $ResearcherEmail -and $_.active -eq $true }

if (-not $matched) {
    Write-Error "Access denied: '$ResearcherEmail' is not in the approved researchers list."
    Write-Host "  Whitelisted emails:" -ForegroundColor Yellow
    $whitelist | Where-Object { $_.active } | ForEach-Object { Write-Host "    - $($_.email) ($($_.name))" -ForegroundColor Gray }
    exit 1
}

Write-Host "`n✓ Identity verified: $($matched.name) <$ResearcherEmail>" -ForegroundColor Green

# Read and decrypt access token
try {
    $encrypted = Get-Content $TOKEN_FILE -Raw
    $decrypted = Unprotect-String $encrypted
    $tokenData = $decrypted | ConvertFrom-Json
    $now = [int][double]::Parse((Get-Date -UFormat %s))

    if ($tokenData.expiry -le $now) {
        Write-Warning "Cached token expired. Waiting for next scheduled refresh (every 50 min)..."
        Write-Host "  Run: Start-ScheduledTask -TaskName 'UZIMA-FabricTokenRefresh'" -ForegroundColor Yellow
        Write-Host "  Then try again in 30 seconds." -ForegroundColor Yellow
        exit 1
    }

    $token = $tokenData.access_token
    $expiresIn = $tokenData.expiry - $now
    Write-Host "✓ Token retrieved (expires in $expiresIn seconds)" -ForegroundColor Green
} catch {
    Write-Error "Failed to read token: $_"
    exit 1
}

# Set environment variable
$env:FABRIC_DELEGATED_ACCESS_TOKEN = $token
$env:FABRIC_RESEARCHER_EMAIL = $ResearcherEmail

Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Session ready for $ResearcherEmail" -ForegroundColor White
Write-Host "  FABRIC_DELEGATED_ACCESS_TOKEN is set" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "In R:" -ForegroundColor Yellow
Write-Host '  library(fabriconnect)' -ForegroundColor Gray
Write-Host '  conn <- connect_to_fabric()' -ForegroundColor Gray
Write-Host '  list_tables(conn)' -ForegroundColor Gray
Write-Host ""
Write-Host "In Python:" -ForegroundColor Yellow
Write-Host '  from fabricpy import FabricLakehouse' -ForegroundColor Gray
Write-Host '  lh = FabricLakehouse()' -ForegroundColor Gray
Write-Host '  lh.list_tables()' -ForegroundColor Gray
Write-Host ""

if (-not $NoLaunch) {
    powershell -NoExit -Command "Write-Host 'FABRIC_DELEGATED_ACCESS_TOKEN set for $ResearcherEmail' -ForegroundColor Green; Write-Host 'Run your R/Python scripts here.' -ForegroundColor Green"
} else {
    Write-Host "Token (first 50 chars): $($token.Substring(0, 50))..." -ForegroundColor Gray
}
