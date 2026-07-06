param(
    [string]$ResearcherEmail,
    [switch]$NoLaunch
)

$ALLOWED_VM_HOST = "uzima"
$ALLOWED_VM_IPS  = @("4.245.225.10", "102.0.6.106")
$TOKEN_DIR       = "$env:PROGRAMDATA\UZIMA\FabricTokenBroker"
$TOKEN_FILE      = "$TOKEN_DIR\access-token.enc"
$WHITELIST_FILE  = "$TOKEN_DIR\whitelist.json"

function Assert-Vm {
    $hostname = $env:COMPUTERNAME.ToLower()
    if ($hostname -notlike "$ALLOWED_VM_HOST*") {
        Write-Error "This script can only run on the approved VM. Current: $hostname"
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

Clear-Host
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  UZIMA Fabric Token Client (Local Mode)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

Assert-Vm

if (-not (Test-Path $TOKEN_FILE)) {
    Write-Error "Token broker not deployed. Ask admin to run deploy-token-broker.ps1 -Mode LocalVM"
    exit 1
}
if (-not (Test-Path $WHITELIST_FILE)) {
    Write-Error "Whitelist not found. Ask admin to run deploy-token-broker.ps1"
    exit 1
}

# Load whitelist for researcher menu
$whitelist = Get-Content $WHITELIST_FILE -Raw | ConvertFrom-Json
$activeResearchers = $whitelist | Where-Object { $_.active -eq $true -and $_.email -notlike "*@aku.edu" }

if (-not $ResearcherEmail) {
    Write-Host ""
    Write-Host "Who are you?" -ForegroundColor Yellow
    Write-Host ""
    for ($i = 0; $i -lt $activeResearchers.Length; $i++) {
        Write-Host "  $($i + 1). $($activeResearchers[$i].name)" -ForegroundColor White
    }
    Write-Host "  $($activeResearchers.Length + 1). Other (enter email manually)" -ForegroundColor Gray
    Write-Host ""

    $selection = Read-Host "Enter number (1-$($activeResearchers.Length + 1))"
    $selection = [int]::TryParse($selection, [ref]$null) ? [int]$selection : 0

    if ($selection -ge 1 -and $selection -le $activeResearchers.Length) {
        $ResearcherEmail = $activeResearchers[$selection - 1].email
        Write-Host "Hello $($activeResearchers[$selection - 1].name)!" -ForegroundColor Green
    } else {
        $ResearcherEmail = Read-Host "Enter your email address"
    }
}

while (-not (Test-EmailFormat $ResearcherEmail)) {
    Write-Host "Invalid email format." -ForegroundColor Yellow
    $ResearcherEmail = Read-Host "Enter your email address"
}

# Check whitelist
$matched = $whitelist | Where-Object { $_.email -eq $ResearcherEmail -and $_.active -eq $true }
if (-not $matched) {
    Write-Error "Access denied: '$ResearcherEmail' is not in the approved researchers list."
    exit 1
}

Write-Host "`nIdentity verified: $($matched.name) <$ResearcherEmail>" -ForegroundColor Green

try {
    $encrypted = Get-Content $TOKEN_FILE -Raw
    $decrypted = Unprotect-String $encrypted
    $tokenData = $decrypted | ConvertFrom-Json
    $now = [int][double]::Parse((Get-Date -UFormat %s))

    if ($tokenData.expiry -le $now) {
        Write-Warning "Cached token expired."
        Write-Host "  Ask admin to refresh or use vm-token-client.ps1 with Azure CLI." -ForegroundColor Yellow
        exit 1
    }

    $token = $tokenData.access_token
    $expiresIn = $tokenData.expiry - $now
    Write-Host "Token retrieved (expires in $expiresIn seconds)" -ForegroundColor Green
} catch {
    Write-Error "Failed to read token: $_"
    exit 1
}

$env:FABRIC_DELEGATED_ACCESS_TOKEN = $token
$env:FABRIC_RESEARCHER_EMAIL = $ResearcherEmail

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  Session ready for $ResearcherEmail" -ForegroundColor White
Write-Host "  FABRIC_DELEGATED_ACCESS_TOKEN is set" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "In Python:" -ForegroundColor Yellow
Write-Host '  from fabricpy import FabricLakehouse' -ForegroundColor Gray
Write-Host '  lh = FabricLakehouse()' -ForegroundColor Gray
Write-Host '  lh.list_tables()' -ForegroundColor Gray
Write-Host ""
Write-Host "In R:" -ForegroundColor Yellow
Write-Host '  library(fabriconnect)' -ForegroundColor Gray
Write-Host '  conn <- connect_to_fabric()' -ForegroundColor Gray
Write-Host '  list_tables(conn)' -ForegroundColor Gray
Write-Host ""

if (-not $NoLaunch) {
    powershell -NoExit -Command "Write-Host 'FABRIC_DELEGATED_ACCESS_TOKEN set for $ResearcherEmail' -ForegroundColor Green; Write-Host 'Run your R/Python scripts here.' -ForegroundColor Green"
} else {
    Write-Host "Token (first 50 chars): $($token.Substring(0, 50))..." -ForegroundColor Gray
}
