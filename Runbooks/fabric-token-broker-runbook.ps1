param(
    [Parameter(Mandatory=$false)]
    [object]$WebhookData
)

<#
.SYNOPSIS
    Azure Automation Runbook — Fabric Token Broker (HTTP Webhook)
.DESCRIPTION
    Three endpoints via WebhookData.RequestBody JSON:
      "action": "get_token"   — validate researcher email + IP, return access token
      "action": "add_email"   — add email to whitelist (admin only)
      "action": "remove_email" — remove email from whitelist (admin only)
      "action": "list_emails" — list whitelisted emails (admin only)
      "action": "refresh"     — force token refresh (admin only)

    IP restriction checked against VM_IPS whitelist.
    Email whitelist stored in Key Vault or Automation Variables.
.NOTES
    Requires Automation RunAs Account or Managed Identity.
    Key Vault secrets:
      fabric-refresh-token    — the admin's OAuth2 refresh token
      fabric-access-token     — current cached access token
      fabric-token-expiry     — Unix timestamp when access token expires
      researcher-whitelist    — JSON array of approved emails
#>

# ─── Configuration ───────────────────────────────────────────────────────────
$TENANT_ID         = "a5d4252a-02f9-4e60-96f0-9733baae4919"
$STORAGE_RESOURCE  = "https://storage.azure.com"
$CLIENT_ID         = "1950a258-227b-4e31-a9cf-717495945fc2"
$VM_IPS            = @("4.245.225.10", "102.0.6.106")

# Key Vault name — set this after deployment
$KEY_VAULT_NAME    = "uzima-fabric-tokens"

# Automation Variable names (used if no Key Vault)
$VAR_REFRESH_TOKEN = "fabric-refresh-token"
$VAR_ACCESS_TOKEN  = "fabric-cached-access-token"
$VAR_TOKEN_EXPIRY  = "fabric-token-expiry"
$VAR_WHITELIST     = "researcher-whitelist"

# ─── Helper: Get Automation Connection / Auth ────────────────────────────────
function Get-AutomationAuthHeader {
    try {
        $conn = Get-AutomationConnection -Name "AzureRunAsConnection"
        $appId = $conn.ApplicationId
        $thumbprint = $conn.CertificateThumbprint
        $tenantId = $conn.TenantId

        Add-Type -AssemblyName System.Web
        $cert = Get-Item -Path "Cert:\CurrentUser\My\$thumbprint"
        $now = [DateTime]::UtcNow
        $audience = "https://login.microsoftonline.com/$tenantId/oauth2/token"
        $expiry = $now.AddHours(1)

        $jwtHeader = @{ alg = "RS256"; x5t = [System.Web.HttpServerUtility]::UrlTokenEncode($cert.GetCertHash()) }
        $jwtPayload = @{
            aud = $audience
            iss = $appId
            sub = $appId
            jti = [Guid]::NewGuid().ToString()
            nbf = [int][double]::Parse($now.ToString("yyyyMMddHHmmss"))
            exp = [int][double]::Parse($expiry.ToString("yyyyMMddHHmmss"))
        }
        $jwt = New-JwtToken -Header $jwtHeader -Payload $jwtPayload -Certificate $cert

        $body = @{
            grant_type = "client_credentials"
            client_id = $appId
            client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            client_assertion = $jwt
            resource = "https://vault.azure.net"
        }
        $url = "https://login.microsoftonline.com/$tenantId/oauth2/token"
        $response = Invoke-RestMethod -Method Post -Uri $url -Body $body
        return @{ Authorization = "Bearer $($response.access_token)" }
    }
    catch {
        throw "Failed to authenticate to Azure: $_"
    }
}

function New-JwtToken {
    param($Header, $Payload, $Certificate)
    $headerJson = ConvertTo-Json -InputObject $Header -Compress
    $payloadJson = ConvertTo-Json -InputObject $Payload -Compress
    $headerB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($headerJson)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $payloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payloadJson)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $toSign = [Text.Encoding]::UTF8.GetBytes("$headerB64.$payloadB64")
    $rsa = $Certificate.PrivateKey
    $signature = $rsa.SignData($toSign, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $sigB64 = [Convert]::ToBase64String($signature).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    return "$headerB64.$payloadB64.$sigB64"
}

# ─── Helper: Key Vault Operations ────────────────────────────────────────────
function Get-KvSecret {
    param([string]$SecretName)
    $authHeader = Get-AutomationAuthHeader
    $url = "https://$KEY_VAULT_NAME.vault.azure.net/secrets/$SecretName/?api-version=7.4"
    $result = Invoke-RestMethod -Uri $url -Method Get -Headers $authHeader
    return $result.value
}

function Set-KvSecret {
    param([string]$SecretName, [string]$SecretValue)
    $authHeader = Get-AutomationAuthHeader
    $url = "https://$KEY_VAULT_NAME.vault.azure.net/secrets/$SecretName/?api-version=7.4"
    $body = @{ value = $SecretValue } | ConvertTo-Json
    Invoke-RestMethod -Uri $url -Method Put -Headers $authHeader -Body $body -ContentType "application/json" | Out-Null
}

# ─── Helper: Automation Variable Operations ──────────────────────────────────
function Get-Var {
    param([string]$VarName)
    try { return Get-AutomationVariable -Name $VarName } catch { return $null }
}

function Set-Var {
    param([string]$VarName, [string]$Value)
    try {
        Set-AutomationVariable -Name $VarName -Value $Value
    } catch {
        New-AutomationVariable -Name $VarName -Value $Value -Encrypted $true
    }
}

# ─── Helper: Token Management ────────────────────────────────────────────────
function Get-StoredRefreshToken {
    if ($KEY_VAULT_NAME) {
        try { return Get-KvSecret -SecretName "fabric-refresh-token" } catch { return $null }
    }
    return Get-Var -VarName $VAR_REFRESH_TOKEN
}

function Get-StoredAccessToken {
    if ($KEY_VAULT_NAME) {
        try { return @{
            token = Get-KvSecret -SecretName "fabric-access-token"
            expiry = Get-KvSecret -SecretName "fabric-token-expiry"
        }} catch { return $null }
    }
    $token = Get-Var -VarName $VAR_ACCESS_TOKEN
    $expiry = Get-Var -VarName $VAR_TOKEN_EXPIRY
    if ($token -and $expiry) { return @{ token = $token; expiry = $expiry } }
    return $null
}

function Set-StoredAccessToken {
    param([string]$Token, [string]$Expiry)
    if ($KEY_VAULT_NAME) {
        Set-KvSecret -SecretName "fabric-access-token" -SecretValue $Token
        Set-KvSecret -SecretName "fabric-token-expiry" -SecretValue $Expiry
        return
    }
    Set-Var -VarName $VAR_ACCESS_TOKEN -Value $Token
    Set-Var -VarName $VAR_TOKEN_EXPIRY -Value $Expiry
}

function Set-StoredRefreshToken {
    param([string]$RefreshToken)
    if ($KEY_VAULT_NAME) {
        Set-KvSecret -SecretName "fabric-refresh-token" -SecretValue $RefreshToken
        return
    }
    Set-Var -VarName $VAR_REFRESH_TOKEN -Value $RefreshToken
}

function Get-Whitelist {
    if ($KEY_VAULT_NAME) {
        try {
            $json = Get-KvSecret -SecretName "researcher-whitelist"
            return $json | ConvertFrom-Json
        } catch { return @() }
    }
    $json = Get-Var -VarName $VAR_WHITELIST
    if ($json) { return $json | ConvertFrom-Json }
    return @()
}

function Set-Whitelist {
    param([array]$Emails)
    $json = $Emails | ConvertTo-Json -Compress
    if ($KEY_VAULT_NAME) {
        Set-KvSecret -SecretName "researcher-whitelist" -SecretValue $json
        return
    }
    Set-Var -VarName $VAR_WHITELIST -Value $json
}

function Refresh-AccessToken {
    $refreshToken = Get-StoredRefreshToken
    if (-not $refreshToken) {
        throw "No refresh token stored. Admin must run init-auth first."
    }

    $body = @{
        grant_type    = "refresh_token"
        client_id     = $CLIENT_ID
        refresh_token = $refreshToken
        scope         = "$STORAGE_RESOURCE/.default offline_access"
    }

    $url = "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token"
    $response = Invoke-RestMethod -Method Post -Uri $url -Body $body -ContentType "application/x-www-form-urlencoded"

    $newRefresh = if ($response.refresh_token) { $response.refresh_token } else { $refreshToken }
    $expiry = [int][double]::Parse((Get-Date -UFormat %s)) + 3300

    Set-StoredRefreshToken -RefreshToken $newRefresh
    Set-StoredAccessToken -Token $response.access_token -Expiry $expiry

    Write-Output "Token refreshed. Expires at $(Get-Date -UnixTimeSeconds $expiry)"
    return $response.access_token
}

function Get-ValidAccessToken {
    $cached = Get-StoredAccessToken
    $now = [int][double]::Parse((Get-Date -UFormat %s))

    if ($cached -and $cached.expiry -and [int]$cached.expiry -gt ($now + 120)) {
        return $cached.token
    }

    return Refresh-AccessToken
}

# ─── Helper: IP Validation ───────────────────────────────────────────────────
function Test-CallerIp {
    param([string]$CallerIp)
    $caller = $CallerIp -replace '^.*?:', '' -replace ':\d+$', ''  # strip port
    foreach ($allowed in $VM_IPS) {
        if ($caller -eq $allowed) { return $true }
    }
    # Also check if caller is localhost (VM calling itself)
    if ($caller -eq "127.0.0.1" -or $caller -eq "::1") { return $true }
    return $false
}

# ─── Helper: Email Validation ────────────────────────────────────────────────
function Test-WhitelistedEmail {
    param([string]$Email)
    $whitelist = Get-Whitelist
    return ($Email -in $whitelist)
}

# ─── Helper: Generate Short-Lived Token ──────────────────────────────────────
function Get-SessionToken {
    param([string]$Email)
    $accessToken = Get-ValidAccessToken
    $expiry = [int][double]::Parse((Get-Date -UFormat %s)) + 3300

    return @{
        access_token  = $accessToken
        token_type    = "Bearer"
        expires_in    = 3300
        expires_at    = $expiry
        resource      = $STORAGE_RESOURCE
        tenant        = $TENANT_ID
        researcher    = $Email
        issued_at     = [int][double]::Parse((Get-Date -UFormat %s))
    }
}

# ─── Main ────────────────────────────────────────────────────────────────────
$result = $null

try {
    # Parse request
    if (-not $WebhookData) {
        throw "This runbook must be called via an HTTP webhook (supply WebhookData)."
    }

    $bodyText = $WebhookData.RequestBody
    $callerIp = $WebhookData.RequestHeader."X-Forwarded-For"
    if (-not $callerIp) { $callerIp = $WebhookData.RequestHeader."REMOTE_ADDR" }

    Write-Output "Caller IP: $callerIp"

    $body = $bodyText | ConvertFrom-Json
    $action = $body.action

    # ─── Actions requiring IP validation (all except init-auth) ────
    if ($action -ne "init-auth") {
        if (-not (Test-CallerIp -CallerIp $callerIp)) {
            throw "Access denied: caller IP '$callerIp' not in VM whitelist."
        }
    }

    switch ($action) {
        "get_token" {
            $email = $body.email
            if (-not $email) { throw "Missing required field: email" }

            if (-not (Test-WhitelistedEmail -Email $email)) {
                throw "Access denied: email '$email' is not whitelisted. Contact your administrator."
            }

            $tokenData = Get-SessionToken -Email $email
            $result = @{
                status = "success"
                data   = $tokenData
            }
            Write-Output "Token issued for $email"
            break
        }

        "refresh" {
            $adminEmail = $body.admin_email
            if (-not (Test-WhitelistedEmail -Email $adminEmail)) {
                throw "Access denied: admin email not whitelisted."
            }
            $newToken = Refresh-AccessToken
            $result = @{ status = "success"; message = "Token refreshed successfully" }
            Write-Output "Manual token refresh completed"
            break
        }

        "add_email" {
            $adminEmail = $body.admin_email
            $newEmail = $body.email
            if (-not $adminEmail -or -not $newEmail) {
                throw "Missing required fields: admin_email, email"
            }
            if (-not (Test-WhitelistedEmail -Email $adminEmail)) {
                throw "Access denied: admin email not whitelisted."
            }

            $whitelist = Get-Whitelist
            if ($newEmail -in $whitelist) {
                $result = @{ status = "success"; message = "Email already whitelisted" }
            } else {
                $whitelist += $newEmail
                Set-Whitelist -Emails $whitelist
                $result = @{ status = "success"; message = "Added $newEmail to whitelist" }
                Write-Output "Added $newEmail to whitelist"
            }
            break
        }

        "remove_email" {
            $adminEmail = $body.admin_email
            $removeEmail = $body.email
            if (-not $adminEmail -or -not $removeEmail) {
                throw "Missing required fields: admin_email, email"
            }
            if (-not (Test-WhitelistedEmail -Email $adminEmail)) {
                throw "Access denied: admin email not whitelisted."
            }

            $whitelist = Get-Whitelist | Where-Object { $_ -ne $removeEmail }
            Set-Whitelist -Emails $whitelist
            $result = @{ status = "success"; message = "Removed $removeEmail from whitelist" }
            Write-Output "Removed $removeEmail from whitelist"
            break
        }

        "list_emails" {
            $adminEmail = $body.admin_email
            if (-not $adminEmail) { throw "Missing required field: admin_email" }
            if (-not (Test-WhitelistedEmail -Email $adminEmail)) {
                throw "Access denied: admin email not whitelisted."
            }

            $whitelist = Get-Whitelist
            $result = @{ status = "success"; emails = $whitelist }
            break
        }

        "init_auth" {
            # Admin provides refresh token directly (obtained via device-code on VM)
            $refreshToken = $body.refresh_token
            if (-not $refreshToken) {
                throw "Missing required field: refresh_token. Run device-code auth on VM first."
            }

            Set-StoredRefreshToken -RefreshToken $refreshToken
            $token = Refresh-AccessToken
            $result = @{
                status = "success"
                message = "Refresh token stored. Access token generated."
            }
            Write-Output "Init auth completed — refresh token stored"
            break
        }

        "status" {
            $hasRefresh = (Get-StoredRefreshToken) -ne $null
            $cached = Get-StoredAccessToken
            $whitelist = Get-Whitelist
            $now = [int][double]::Parse((Get-Date -UFormat %s))
            $expiresIn = if ($cached) { [int]$cached.expiry - $now } else { 0 }

            $result = @{
                status           = "success"
                has_refresh_token = $hasRefresh
                access_token_valid = $expiresIn -gt 0
                expires_in_seconds = [Math]::Max(0, $expiresIn)
                whitelisted_emails = $whitelist.Count
                vm_ips           = $VM_IPS
            }
            break
        }

        default {
            throw "Unknown action '$action'. Valid: get_token, refresh, add_email, remove_email, list_emails, init_auth, status"
        }
    }
}
catch {
    $result = @{
        status = "error"
        message = $_.Exception.Message
    }
    Write-Error "Runbook error: $_"
}

# Return result as JSON
if ($result) {
    $jsonResult = $result | ConvertTo-Json -Depth 5
    Write-Output "---BEGIN-RESPONSE---"
    Write-Output $jsonResult
    Write-Output "---END-RESPONSE---"
}
