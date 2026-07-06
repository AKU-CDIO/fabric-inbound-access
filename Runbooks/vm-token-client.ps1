param(
    [string]$WebhookUrl,
    [string]$Email
)

$ALLOWED_VM_HOST = "uzima"
$ALLOWED_VM_IPS  = @("4.245.225.10", "102.0.6.106")
$CONFIG_FILE     = "$env:PROGRAMDATA\UZIMA\FabricTokenBroker\researchers.json"

$hostname = $env:COMPUTERNAME.ToLower()
if ($hostname -notlike "$ALLOWED_VM_HOST*") {
    Write-Host "This tool can only run on the approved UZIMA VM." -ForegroundColor Red
    Write-Host "Current PC: $hostname" -ForegroundColor Red
    exit 1
}

if (-not $WebhookUrl) { $WebhookUrl = $env:FABRIC_WEBHOOK_URL }
if (-not $WebhookUrl -and (Test-Path $CONFIG_FILE)) {
    $config = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
    $WebhookUrl = $config.webhook_url
}
if (-not $WebhookUrl) {
    Write-Host "`nWebhook URL not configured. Set FABRIC_WEBHOOK_URL or update researchers.json." -ForegroundColor Red
    exit 1
}

$knownUsers = @()
if (Test-Path $CONFIG_FILE) {
    $config = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
    $knownUsers = $config.vm_users | Where-Object { $_.active -eq $true }
}

if (-not $Email) {
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "     UZIMA Fabric Data Access" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Who are you?" -ForegroundColor Yellow
    Write-Host ""
    for ($i = 0; $i -lt $knownUsers.Length; $i++) {
        $label = $knownUsers[$i].name
        if ($knownUsers[$i].institution) { $label += " (" + $knownUsers[$i].institution + ")" }
        Write-Host "  $($i + 1). $label" -ForegroundColor White
    }
    Write-Host "  $($knownUsers.Length + 1). Other (enter email manually)" -ForegroundColor Gray
    Write-Host ""

    $selection = Read-Host "Enter number (1-$($knownUsers.Length + 1))"
    $selection = [int]::TryParse($selection, [ref]$null) ? [int]$selection : 0

    if ($selection -ge 1 -and $selection -le $knownUsers.Length) {
        $Email = $knownUsers[$selection - 1].email
        $userName = $knownUsers[$selection - 1].name
        Write-Host "Hello $userName!" -ForegroundColor Green
    } else {
        $Email = Read-Host "Enter your email address"
    }
}

while ($Email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
    Write-Host "That doesn't look like an email. Try again." -ForegroundColor Yellow
    $Email = Read-Host "Enter your email address"
}

Write-Host "`nContacting the authentication service..." -ForegroundColor Gray

$body = @{ action = "get_token"; email = $Email } | ConvertTo-Json

try {
    $webResponse = Invoke-RestMethod -Method Post -Uri $WebhookUrl `
        -Body $body -ContentType "application/json" -TimeoutSec 30

    $jobIds = $webResponse.JobIds
    if (-not $jobIds) {
        Write-Host "`nAuthentication error: unexpected response." -ForegroundColor Red
        exit 1
    }
    $jobId = $jobIds[0]
    Write-Host "  Job submitted: $jobId" -ForegroundColor Gray

    # Load config for job polling
    $cfgPath = "$PSScriptRoot\..\fabricpy\config.json"
    if (-not (Test-Path $cfgPath)) {
        Write-Host "`nConfig not found for job polling." -ForegroundColor Red
        exit 1
    }
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $sub = $cfg.automation.subscription_id
    $rg  = $cfg.automation.resource_group
    $aa  = $cfg.automation.account_name

    Write-Host "  Waiting for job to complete..." -ForegroundColor Gray
    $deadline = (Get-Date).AddSeconds(120)
    $completed = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 10
        $statusResult = & az rest --method GET --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Automation/automationAccounts/$aa/jobs/$jobId`?api-version=2023-11-01" --query "properties.status" -o tsv 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`nAzure CLI not available. Run 'az login --scope https://management.azure.com/.default --use-device-code' first." -ForegroundColor Red
            exit 1
        }
        $status = $statusResult.Trim()
        if ($status -eq "Completed") { $completed = $true; break }
        if ($status -in @("Failed", "Stopped", "Suspended")) {
            Write-Host "`nAuthentication service error: job $status." -ForegroundColor Red
            exit 1
        }
        Write-Host "  Status: $status" -ForegroundColor Gray
    }

    if (-not $completed) {
        Write-Host "`nAuthentication timed out." -ForegroundColor Red
        exit 1
    }

    Write-Host "  Fetching token..." -ForegroundColor Gray
    $outputResult = & az rest --method GET --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Automation/automationAccounts/$aa/jobs/$jobId/output?api-version=2023-11-01" -o json 2>$null
    $outputText = $outputResult

    # Parse response markers
    $markerStart = "---BEGIN-RESPONSE---"
    $markerEnd = "---END-RESPONSE---"
    $startIdx = $outputText.IndexOf($markerStart)
    if ($startIdx -ge 0) {
        $startIdx += $markerStart.Length
        $endIdx = $outputText.IndexOf($markerEnd, $startIdx)
        if ($endIdx -ge 0) {
            $jsonStr = $outputText.Substring($startIdx, $endIdx - $startIdx).Trim()
            $tokenData = $jsonStr | ConvertFrom-Json
            if ($tokenData.status -eq "success") {
                $token = $tokenData.data.access_token
            }
        }
    }

    if (-not $token) {
        Write-Host "`nAccess denied or unexpected response." -ForegroundColor Red
        exit 1
    }

    $env:FABRIC_DELEGATED_ACCESS_TOKEN = $token
    $env:FABRIC_RESEARCHER_EMAIL = $Email

    Clear-Host
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "         ACCESS GRANTED" -ForegroundColor Green
    Write-Host "   $Email" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your data access session is ready." -ForegroundColor Cyan
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

    powershell -NoExit -Command "Write-Host 'FABRIC_DELEGATED_ACCESS_TOKEN set for $Email' -ForegroundColor Green; Write-Host 'Run your R/Python scripts here.' -ForegroundColor Green"

} catch {
    Write-Host "`nCould not contact authentication service:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "`nEnsure you are logged into Azure CLI:" -ForegroundColor Yellow
    Write-Host "  az login --scope https://management.azure.com/.default --use-device-code" -ForegroundColor Gray
    exit 1
}
