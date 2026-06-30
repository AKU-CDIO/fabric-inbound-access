param(
    [string]$WebhookUrl,
    [string]$Email
)

# ─── Config ──────────────────────────────────────────────────────────────────
$ALLOWED_VM_HOST = "admindsvm"
$ALLOWED_VM_IPS  = @("4.245.225.10", "102.0.6.106")

$KNOWN_USERS = @(
    @{ name = "Ye Chan Kim";  email = "yechank@med.umich.edu" }
    @{ name = "Kenney Brooke"; email = "nannab@med.umich.edu" }
)

# ─── Check VM ────────────────────────────────────────────────────────────────
$hostname = $env:COMPUTERNAME.ToLower()
if ($hostname -notlike "$ALLOWED_VM_HOST*") {
    Write-Host "This tool can only run on the approved UZIMA VM." -ForegroundColor Red
    Write-Host "Current PC: $hostname" -ForegroundColor Red
    exit 1
}

# ─── Get Webhook URL ─────────────────────────────────────────────────────────
if (-not $WebhookUrl) { $WebhookUrl = $env:FABRIC_WEBHOOK_URL }
if (-not $WebhookUrl) {
    Write-Host "`nPaste the webhook URL you received from the admin:" -ForegroundColor Yellow
    $WebhookUrl = Read-Host "Webhook URL"
}

# ─── Get Email ───────────────────────────────────────────────────────────────
if (-not $Email) {
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "     UZIMA Fabric Data Access" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Who are you?" -ForegroundColor Yellow
    Write-Host ""
    for ($i = 0; $i -lt $KNOWN_USERS.Length; $i++) {
        Write-Host "  $($i + 1). $($KNOWN_USERS[$i].name)" -ForegroundColor White
    }
    Write-Host "  $($KNOWN_USERS.Length + 1). Other (enter email manually)" -ForegroundColor Gray
    Write-Host ""

    $selection = Read-Host "Enter number (1-$($KNOWN_USERS.Length + 1))"
    $selection = [int]::TryParse($selection, [ref]$null) ? [int]$selection : 0

    if ($selection -ge 1 -and $selection -le $KNOWN_USERS.Length) {
        $Email = $KNOWN_USERS[$selection - 1].email
        Write-Host "Hello $($KNOWN_USERS[$selection - 1].name)!" -ForegroundColor Green
    } else {
        $Email = Read-Host "Enter your email address"
    }
}

# ─── Validate email format ───────────────────────────────────────────────────
while ($Email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
    Write-Host "That doesn't look like an email. Try again." -ForegroundColor Yellow
    $Email = Read-Host "Enter your email address"
}

# ─── Get Token ───────────────────────────────────────────────────────────────
Write-Host "`nContacting the authentication service..." -ForegroundColor Gray

$body = @{ action = "get_token"; email = $Email } | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Method Post -Uri $WebhookUrl `
        -Body $body -ContentType "application/json" -TimeoutSec 30

    if ($response.status -eq "success") {
        $token = $response.data.access_token
    } else {
        Write-Host "`nAccess denied: $($response.message)" -ForegroundColor Red
        Write-Host "Contact your administrator if you believe this is a mistake." -ForegroundColor Yellow
        Read-Host "`nPress Enter to exit"
        exit 1
    }
} catch {
    Write-Host "`nCould not contact authentication service:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "`nCheck your internet connection and the webhook URL." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# ─── Set Token ───────────────────────────────────────────────────────────────
$env:FABRIC_DELEGATED_ACCESS_TOKEN = $token
$env:FABRIC_RESEARCHER_EMAIL = $Email

# ─── Done ────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║         ACCESS GRANTED                        ║" -ForegroundColor Green
Write-Host "║   $Email" -ForegroundColor White
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Your data access session is ready." -ForegroundColor Cyan
Write-Host ""

Write-Host "  [1] Open R" -ForegroundColor White
Write-Host "  [2] Open Python" -ForegroundColor White
Write-Host "  [3] Open Command Prompt (run R/Python yourself)" -ForegroundColor White
Write-Host "  [4] Exit" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "What do you want to do? (1-4)"

switch ($choice) {
    "1" {
        Write-Host "Starting R... (run 'library(fabriconnect); conn <- connect_to_fabric()' to begin)" -ForegroundColor Gray
        Start-Process "Rgui" -Wait
    }
    "2" {
        Write-Host "Starting Python... (run 'from fabricpy import FabricLakehouse')" -ForegroundColor Gray
        Start-Process "python" -Wait
    }
    "3" {
        powershell -NoExit -Command @"
Write-Host 'FABRIC_DELEGATED_ACCESS_TOKEN is set for $Email' -ForegroundColor Green
Write-Host 'Run your R/Python scripts here.' -ForegroundColor Green
"@
    }
    default {
        Write-Host "Token is set. To use it later, run this in PowerShell:" -ForegroundColor Gray
        Write-Host '  $env:FABRIC_DELEGATED_ACCESS_TOKEN = "' -NoNewline; Write-Host "$($token.Substring(0, 30))..." -ForegroundColor Gray -NoNewline; Write-Host '"' -ForegroundColor Gray
    }
}
