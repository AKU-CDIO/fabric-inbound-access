<#
.SYNOPSIS
    Local token refresh — exchanges the stored refresh token for a fresh
    access token and writes it to fab_token.txt.
.DESCRIPTION
    Runs via Task Scheduler on VM startup + every 45 minutes.
    Both the R (fabriconnect) and Python (fabricpy) packages read fab_token.txt
    on startup, so no env var setup is needed.
    
    Fallback chain:
      1. Local encrypted refresh token → exchange for fresh access token
      2. Key Vault (via managed identity) → pull fresh token or refresh
.NOTES
    Requires: access-token.enc and refresh-token.enc in the same directory.
    Tenant: a5d4252a-02f9-4e60-96f0-9733baae4919
    Client ID: 1950a258-227b-4e31-a9cf-717495945fc2
#>

$ErrorActionPreference = "Stop"

$BROKER_DIR      = "$env:ProgramData\UZIMA\FabricTokenBroker"
$TOKEN_FILE      = "$BROKER_DIR\fab_token.txt"
$LOG_FILE        = "$BROKER_DIR\refresh-log.txt"
$TENANT_ID       = "a5d4252a-02f9-4e60-96f0-9733baae4919"
$STORAGE_RESOURCE = "https://storage.azure.com"
$CLIENT_ID       = "1950a258-227b-4e31-a9cf-717495945fc2"
$KV_NAME         = "uzima-fabric-tokens"
$LISTENER_SECRET = (Get-ItemProperty -Path "HKLM:\SOFTWARE\UZIMA\FabricTokenBroker" -ErrorAction SilentlyContinue).ListenerSecret

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Add-Content -Path $LOG_FILE -Value $line -ErrorAction SilentlyContinue
}

function Get-DecryptedToken {
    param([string]$EncFileName)
    $encPath = "$BROKER_DIR\$EncFileName"
    if (-not (Test-Path $encPath)) {
        throw "Encrypted file not found: $encPath"
    }
    $enc = Get-Content $encPath -Raw
    $s = (Get-WmiObject Win32_OperatingSystem).SerialNumber
    $k = "uzima-$s"
    $sha = [Security.Cryptography.SHA256]::Create()
    $kb = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($k)))
    $sec = ConvertTo-SecureString -String $enc -Key ([Text.Encoding]::UTF8.GetBytes($kb.Substring(0,32)))
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
    return $plain
}

function Get-FreshAccessToken {
    param([string]$RefreshToken)
    Add-Type -AssemblyName System.Web
    $bodyParts = @(
        "grant_type=refresh_token",
        "client_id=$CLIENT_ID",
        "refresh_token=$([System.Web.HttpUtility]::UrlEncode($RefreshToken))",
        "scope=$([System.Web.HttpUtility]::UrlEncode("$STORAGE_RESOURCE/.default offline_access"))"
    )
    $bodyStr = $bodyParts -join "&"
    $resp = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" `
        -Body $bodyStr `
        -ContentType "application/x-www-form-urlencoded" `
        -TimeoutSec 30

    if (-not $resp.access_token) {
        throw "No access_token in response"
    }

    return @{
        access_token  = $resp.access_token
        refresh_token = if ($resp.refresh_token) { $resp.refresh_token } else { $RefreshToken }
    }
}

function Test-TokenValid {
    param([string]$Token)
    if (-not $Token -or -not $Token.StartsWith("eyJ")) { return $false }
    try {
        $parts = $Token.Split(".")
        $payload = $parts[1]
        $mod = $payload.Length % 4
        if ($mod -gt 0) { $payload += ("=" * (4 - $mod)) }
        $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $json = $decoded | ConvertFrom-Json
        $exp = [DateTimeOffset]::FromUnixTimeSeconds($json.exp)
        $now = [DateTimeOffset]::UtcNow
        return ($exp -gt $now)
    } catch {
        return $false
    }
}

function Update-EncryptedFiles {
    param([string]$AccessToken, [string]$RefreshToken)

    $s = (Get-WmiObject Win32_OperatingSystem).SerialNumber
    $k = "uzima-$s"
    $sha = [Security.Cryptography.SHA256]::Create()
    $kb = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($k)))

    $secure = ConvertTo-SecureString $AccessToken -AsPlainText -Force
    $encAccess = ConvertFrom-SecureString -SecureString $secure -Key ([Text.Encoding]::UTF8.GetBytes($kb.Substring(0,32)))
    Set-Content -Path "$BROKER_DIR\access-token.enc" -Value $encAccess -NoNewline

    $secure = ConvertTo-SecureString $RefreshToken -AsPlainText -Force
    $encRefresh = ConvertFrom-SecureString -SecureString $secure -Key ([Text.Encoding]::UTF8.GetBytes($kb.Substring(0,32)))
    Set-Content -Path "$BROKER_DIR\refresh-token.enc" -Value $encRefresh -NoNewline
}

function Get-KvAccessToken {
    try {
        $kvToken = Invoke-RestMethod `
            -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" `
            -Headers @{Metadata="true"} -Method Get -TimeoutSec 10
        return $kvToken.access_token
    } catch {
        return $null
    }
}

function Get-KvSecret {
    param([string]$SecretName, [string]$KvAccessToken)
    $headers = @{ Authorization = "Bearer $KvAccessToken"; "Content-Type" = "application/json" }
    $url = "https://$KV_NAME.vault.azure.net/secrets/$SecretName/?api-version=7.4"
    $result = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 10
    return $result.value
}

function Set-KvSecret {
    param([string]$SecretName, [string]$SecretValue, [string]$KvAccessToken)
    $headers = @{ Authorization = "Bearer $KvAccessToken"; "Content-Type" = "application/json" }
    $url = "https://$KV_NAME.vault.azure.net/secrets/$SecretName/?api-version=7.4"
    $body = @{ value = $SecretValue } | ConvertTo-Json
    Invoke-RestMethod -Uri $url -Headers $headers -Method Put -Body $body -TimeoutSec 10 | Out-Null
}

# ─── Key Vault Fallback ─────────────────────────────────────────────────────
function Invoke-KeyVaultRefresh {
    Write-Log "Attempting Key Vault fallback..."
    
    $kvAccess = Get-KvAccessToken
    if (-not $kvAccess) {
        Write-Log "Key Vault fallback: cannot obtain managed identity token"
        return $false
    }
    Write-Log "Key Vault fallback: managed identity token obtained"
    
    # Check if Key Vault has a fresh access token
    try {
        $kvAccessToken = Get-KvSecret -SecretName "fabric-access-token" -KvAccessToken $kvAccess
        $kvExpiry = Get-KvSecret -SecretName "fabric-token-expiry" -KvAccessToken $kvAccess
        $now = [int][double]::Parse((Get-Date -UFormat %s))
        
        if ($kvAccessToken -and $kvExpiry -and ([int]$kvExpiry -gt ($now + 120))) {
            Write-Log "Key Vault fallback: found valid access token (expires in $([int]$kvExpiry - $now)s)"
            if (Test-TokenValid -Token $kvAccessToken) {
                Set-Content -Path $TOKEN_FILE -Value $kvAccessToken -NoNewline -Force
                Write-Log "Key Vault fallback: written fresh token to fab_token.txt"
                return $true
            }
        }
        Write-Log "Key Vault fallback: cached token expired or invalid, refreshing..."
    } catch {
        Write-Log "Key Vault fallback: no cached token ($($_.Exception.Message))"
    }
    
    # Use Key Vault's refresh token to get a new access token
    try {
        $kvRefreshToken = Get-KvSecret -SecretName "fabric-refresh-token" -KvAccessToken $kvAccess
        if (-not $kvRefreshToken -or $kvRefreshToken.Length -lt 100) {
            Write-Log "Key Vault fallback: no valid refresh token in Key Vault"
            return $false
        }
        
        $result = Get-FreshAccessToken -RefreshToken $kvRefreshToken
        $accessToken = $result.access_token
        $newRefreshToken = $result.refresh_token
        
        if (-not (Test-TokenValid -Token $accessToken)) {
            Write-Log "Key Vault fallback: refreshed token is invalid"
            return $false
        }
        
        # Write to local files
        Set-Content -Path $TOKEN_FILE -Value $accessToken -NoNewline -Force
        Update-EncryptedFiles -AccessToken $accessToken -RefreshToken $newRefreshToken
        [Environment]::SetEnvironmentVariable("FABRIC_ACCESS_TOKEN", $accessToken, "Machine")
        
        # Update Key Vault with new tokens
        $expiry = [int][double]::Parse((Get-Date -UFormat %s)) + 3300
        Set-KvSecret -SecretName "fabric-access-token" -SecretValue $accessToken -KvAccessToken $kvAccess
        Set-KvSecret -SecretName "fabric-token-expiry" -SecretValue $expiry -KvAccessToken $kvAccess
        Set-KvSecret -SecretName "fabric-refresh-token" -SecretValue $newRefreshToken -KvAccessToken $kvAccess
        
        Write-Log "Key Vault fallback: refreshed and synced both local + Key Vault"
        return $true
    } catch {
        Write-Log "Key Vault fallback: refresh failed ($($_.Exception.Message))"
        return $false
    }
}

# ─── Main ────────────────────────────────────────────────────────────────────
try {
    Write-Log "Starting local token refresh..."

    # 1. Try local refresh token
    try {
        $refreshRaw = Get-DecryptedToken -EncFileName "refresh-token.enc"
        try {
            $refreshJson = $refreshRaw | ConvertFrom-Json
            $refreshToken = $refreshJson.refresh_token
            if (-not $refreshToken) { $refreshToken = $refreshRaw }
        } catch {
            $refreshToken = $refreshRaw
        }
        if (-not $refreshToken -or $refreshToken.Length -lt 100) {
            throw "No valid refresh_token in encrypted data"
        }
        Write-Log "Refresh token decrypted OK ($($refreshToken.Length) chars)"

        $result = Get-FreshAccessToken -RefreshToken $refreshToken
        $accessToken = $result.access_token
        $newRefreshToken = $result.refresh_token
        Write-Log "Fresh access token obtained ($($accessToken.Length) chars)"

        if (-not (Test-TokenValid -Token $accessToken)) {
            throw "Obtained token is invalid or already expired"
        }

        Set-Content -Path $TOKEN_FILE -Value $accessToken -NoNewline -Force
        Write-Log "Written to $TOKEN_FILE"

        Update-EncryptedFiles -AccessToken $accessToken -RefreshToken $newRefreshToken
        Write-Log "Encrypted files updated"

        [Environment]::SetEnvironmentVariable("FABRIC_ACCESS_TOKEN", $accessToken, "Machine")
        Write-Log "Machine env var updated"

        $parts = $accessToken.Split(".")
        $payload = $parts[1]
        $mod = $payload.Length % 4
        if ($mod -gt 0) { $payload += ("=" * (4 - $mod)) }
        $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $jwt = $decoded | ConvertFrom-Json
        $exp = [DateTimeOffset]::FromUnixTimeSeconds($jwt.exp).ToString("yyyy-MM-dd HH:mm:ss UTC")
        Write-Log "Token expires: $exp"

        Write-Log "Token refresh completed successfully (local path)"
        exit 0
    } catch {
        Write-Log "Local refresh failed: $($_.Exception.Message)"
        Write-Log "Falling back to Key Vault..."
    }

    # 2. Fallback to Key Vault
    $kvResult = Invoke-KeyVaultRefresh
    if ($kvResult) {
        Write-Log "Token refresh completed successfully (Key Vault fallback)"
        exit 0
    }

    throw "Both local and Key Vault refresh failed"
} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
