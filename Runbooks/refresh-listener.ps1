<#
.SYNOPSIS
    HTTP listener for instant token refresh triggered by Azure Automation webhook.
.DESCRIPTION
    Runs as a Windows Service. Listens on port 8443 for POST requests
    from the Azure Automation webhook when admin clicks "Refresh" in portal.
    
    Request: POST http://localhost:8443/refresh
             Header: X-Refresh-Secret: <shared secret>
    
    Response: {"status": "ok"} on success
.NOTES
    Port: 8443 (firewall rule added by setup-local-scheduler.ps1)
    Secret: stored in HKLM:\SOFTWARE\UZIMA\FabricTokenBroker\ListenerSecret
#>

$ErrorActionPreference = "Stop"

$PORT = 8443
$BROKER_DIR = "$env:ProgramData\UZIMA\FabricTokenBroker"
$LOG_FILE = "$BROKER_DIR\refresh-log.txt"
$REFRESH_SCRIPT = "$BROKER_DIR\refresh-token-local.ps1"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [LISTENER] $Message"
    Add-Content -Path $LOG_FILE -Value $line -ErrorAction SilentlyContinue
}

function Get-ListenerSecret {
    $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\UZIMA\FabricTokenBroker" -ErrorAction SilentlyContinue
    if ($reg -and $reg.ListenerSecret) {
        return $reg.ListenerSecret
    }
    # Generate and store a new secret on first run
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $secret = [Convert]::ToBase64String($bytes)
    if (-not (Test-Path "HKLM:\SOFTWARE\UZIMA\FabricTokenBroker")) {
        New-Item -Path "HKLM:\SOFTWARE\UZIMA\FabricTokenBroker" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\UZIMA\FabricTokenBroker" -Name "ListenerSecret" -Value $secret
    return $secret
}

function Start-Listener {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://+:$PORT/")
    $listener.Start()
    Write-Log "HTTP listener started on port $PORT"
    return $listener
}

function Stop-Listener {
    param($Listener)
    if ($Listener) {
        try { $Listener.Stop() } catch {}
        try { $Listener.Close() } catch {}
    }
    Write-Log "HTTP listener stopped"
}

# ─── Main ────────────────────────────────────────────────────────────────────
$listener = $null
$running = $true

# Register cleanup on exit
$cleanup = {
    Stop-Listener -Listener $listener
}
Register-EngineEvent PowerShell.Exiting -Action $cleanup | Out-Null

try {
    $secret = Get-ListenerSecret
    Write-Log "Listener secret loaded"
    
    $listener = Start-Listener
    
    while ($running) {
        try {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            $path = $request.Url.AbsolutePath
            $method = $request.HttpMethod
            $callerIp = $request.RemoteEndPoint.Address.ToString()
            
            Write-Log "Request: $method $path from $callerIp"
            
            # Only accept POST /refresh
            if ($path -ne "/refresh" -or $method -ne "POST") {
                $response.StatusCode = 404
                $buffer = [Text.Encoding]::UTF8.GetBytes('{"status":"error","message":"not found"}')
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
                continue
            }
            
            # Validate secret
            $requestSecret = $request.Headers["X-Refresh-Secret"]
            if ($requestSecret -ne $secret) {
                Write-Log "Unauthorized: invalid secret from $callerIp"
                $response.StatusCode = 401
                $buffer = [Text.Encoding]::UTF8.GetBytes('{"status":"error","message":"unauthorized"}')
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
                continue
            }
            
            Write-Log "Authorized refresh request from $callerIp"
            
            # Run the refresh script
            $result = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $REFRESH_SCRIPT 2>&1
            $exitCode = $LASTEXITCODE
            
            if ($exitCode -eq 0) {
                Write-Log "Refresh completed successfully"
                $response.StatusCode = 200
                $buffer = [Text.Encoding]::UTF8.GetBytes('{"status":"ok","message":"token refreshed"}')
            } else {
                Write-Log "Refresh failed with exit code $exitCode"
                $response.StatusCode = 500
                $buffer = [Text.Encoding]::UTF8.GetBytes('{"status":"error","message":"refresh failed"}')
            }
            
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
            
        } catch {
            Write-Log "Listener error: $($_.Exception.Message)"
            Start-Sleep -Seconds 1
        }
    }
} catch {
    Write-Log "Fatal listener error: $($_.Exception.Message)"
} finally {
    Stop-Listener -Listener $listener
}
