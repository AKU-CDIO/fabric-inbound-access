<#
.SYNOPSIS
    One-time setup: installs the local token refresh system on the VM.
.DESCRIPTION
    Creates:
      1. Windows Task Scheduler job (startup + every 45 min)
      2. HTTP listener service (instant portal propagation)
      3. Firewall rule for listener port
      4. Registry key with listener secret
.NOTES
    Run as Administrator once. Then restart R/Python to use tokens.
#>

$ErrorActionPreference = "Stop"

$BROKER_DIR      = "$env:ProgramData\UZIMA\FabricTokenBroker"
$REFRESH_SCRIPT  = "$BROKER_DIR\refresh-token-local.ps1"
$LISTENER_SCRIPT = "$BROKER_DIR\refresh-listener.ps1"
$LOG_FILE        = "$BROKER_DIR\refresh-log.txt"
$TASK_NAME       = "UZIMA-RefreshFabricToken"
$LISTENER_PORT   = 8443

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [SETUP] $Message"
    Add-Content -Path $LOG_FILE -Value $line -ErrorAction SilentlyContinue
    echo $line
}

# ─── 1. Generate Listener Secret ────────────────────────────────────────────
Write-Log "Setting up listener secret..."
$regPath = "HKLM:\SOFTWARE\UZIMA\FabricTokenBroker"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
$existing = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).ListenerSecret
if (-not $existing) {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $secret = [Convert]::ToBase64String($bytes)
    Set-ItemProperty -Path $regPath -Name "ListenerSecret" -Value $secret
    Write-Log "Generated new listener secret"
} else {
    $secret = $existing
    Write-Log "Using existing listener secret"
}

# ─── 2. Firewall Rule for HTTP Listener ─────────────────────────────────────
Write-Log "Configuring firewall rule on port $LISTENER_PORT..."
$ruleName = "UZIMA-Token-Listener"
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existingRule) {
    Remove-NetFirewallRule -DisplayName $ruleName
}
New-NetFirewallRule -DisplayName $ruleName `
    -Direction Inbound -Protocol TCP -LocalPort $LISTENER_PORT `
    -Action Allow -Profile Any `
    -Description "UZIMA Fabric Token Broker HTTP listener" | Out-Null
Write-Log "Firewall rule created"

# ─── 3. Scheduled Task (startup + every 45 min) ─────────────────────────────
Write-Log "Setting up scheduled task..."
$existingTask = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$REFRESH_SCRIPT`""

$triggerStartup = New-ScheduledTaskTrigger -AtStartup
$triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 45) `
    -RepetitionDuration (New-TimeSpan -Days 9999)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $TASK_NAME `
    -Action $action `
    -Trigger @($triggerStartup, $triggerRepeat) `
    -Settings $settings `
    -Principal $principal `
    -Description "Refresh UZIMA Fabric access token every 45 minutes" | Out-Null
Write-Log "Scheduled task '$TASK_NAME' registered"

# ─── 4. HTTP Listener Service ───────────────────────────────────────────────
Write-Log "Setting up HTTP listener service..."
$listenerTaskName = "UZIMA-TokenListener"
$existingListener = Get-ScheduledTask -TaskName $listenerTaskName -ErrorAction SilentlyContinue
if ($existingListener) {
    Unregister-ScheduledTask -TaskName $listenerTaskName -Confirm:$false
}

$listenerAction = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LISTENER_SCRIPT`""

$listenerTrigger = New-ScheduledTaskTrigger -AtStartup
$listenerSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Days 9999) `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $listenerTaskName `
    -Action $listenerAction `
    -Trigger $listenerTrigger `
    -Settings $listenerSettings `
    -Principal $principal `
    -Description "HTTP listener for instant token refresh from Azure Portal" | Out-Null
Write-Log "HTTP listener task '$listenerTaskName' registered"

# ─── 5. Ensure fab_token.txt exists and is writable ─────────────────────────
$tokenFile = "$BROKER_DIR\fab_token.txt"
if (-not (Test-Path $tokenFile)) {
    Set-Content -Path $tokenFile -Value "" -NoNewline
}
icacls $tokenFile /grant "SYSTEM:(R)" /grant "Everyone:(R)" /T /Q | Out-Null
Write-Log "fab_token.txt permissions set"

# ─── 6. Run initial refresh ─────────────────────────────────────────────────
Write-Log "Running initial token refresh..."
$initResult = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $REFRESH_SCRIPT 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Log "Initial refresh succeeded"
} else {
    Write-Log "Initial refresh failed (will retry on schedule)"
}

# ─── 7. Start listener immediately ──────────────────────────────────────────
Write-Log "Starting HTTP listener..."
Start-ScheduledTask -TaskName $listenerTaskName
Start-Sleep -Seconds 2
$listenerState = (Get-ScheduledTask -TaskName $listenerTaskName).State
Write-Log "Listener state: $listenerState"

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Log "=== Setup Complete ==="
Write-Log "Scheduled task: $TASK_NAME (startup + every 45 min)"
Write-Log "HTTP listener: $listenerTaskName (port $LISTENER_PORT)"
Write-Log "Firewall rule: $ruleName"
Write-Log ""
Write-Log "Portal 'Refresh' propagation: instant (via HTTP listener)"
Write-Log "Scheduled refresh: every 45 minutes (via Task Scheduler)"
Write-Log "Fallback chain: local refresh → Key Vault → error"
Write-Log ""
Write-Log "Listener secret: $secret"
Write-Log "(Store this for Azure Automation webhook configuration)"
