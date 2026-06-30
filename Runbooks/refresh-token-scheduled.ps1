<#
.SYNOPSIS
    Azure Automation Scheduled Runbook — Auto-refresh Fabric access token
.DESCRIPTION
    Runs every 50 minutes via a schedule. Reads the stored refresh token
    from Key Vault (or Automation Variables), exchanges it for a new
    access token, and stores the result. No HTTP trigger needed.
.NOTES
    Schedule: Run every 50 minutes (Tokens last ~55 min).
    Requires same auth setup as token-broker-runbook.ps1.
#>

$TENANT_ID         = "a5d4252a-02f9-4e60-96f0-9733baae4919"
$STORAGE_RESOURCE  = "https://storage.azure.com"
$CLIENT_ID         = "1950a258-227b-4e31-a9cf-717495945fc2"
$KEY_VAULT_NAME    = "uzima-fabric-tokens"

function Get-KvSecret {
    param([string]$SecretName)
    $conn = Get-AutomationConnection -Name "AzureRunAsConnection"
    $appId = $conn.ApplicationId
    $thumbprint = $conn.CertificateThumbprint
    $tenantId = $conn.TenantId

    Add-Type -AssemblyName System.Web
    $cert = Get-Item -Path "Cert:\CurrentUser\My\$thumbprint"
    $now = [DateTime]::UtcNow
    $audience = "https://login.microsoftonline.com/$tenantId/oauth2/token"
    $expiry = $now.AddHours(1)

    $header = @{ alg = "RS256"; x5t = [System.Web.HttpServerUtility]::UrlTokenEncode($cert.GetCertHash()) }
    $payload = @{
        aud = $audience; iss = $appId; sub = $appId
        jti = [Guid]::NewGuid().ToString()
        nbf = [int][double]::Parse($now.ToString("yyyyMMddHHmmss"))
        exp = [int][double]::Parse($expiry.ToString("yyyyMMddHHmmss"))
    }
    $headerB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($header | ConvertTo-Json -Compress)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $payloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload | ConvertTo-Json -Compress)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $toSign = [Text.Encoding]::UTF8.GetBytes("$headerB64.$payloadB64")
    $sigB64 = [Convert]::ToBase64String($cert.PrivateKey.SignData($toSign, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $jwt = "$headerB64.$payloadB64.$sigB64"

    $body = @{ grant_type = "client_credentials"; client_id = $appId; client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"; client_assertion = $jwt; resource = "https://vault.azure.net" }
    $tokenResp = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token" -Body $body
    $authHeader = @{ Authorization = "Bearer $($tokenResp.access_token)" }

    $url = "https://$KEY_VAULT_NAME.vault.azure.net/secrets/$SecretName/?api-version=7.4"
    return (Invoke-RestMethod -Uri $url -Method Get -Headers $authHeader).value
}

function Set-KvSecret {
    param([string]$SecretName, [string]$SecretValue)
    $conn = Get-AutomationConnection -Name "AzureRunAsConnection"
    $appId = $conn.ApplicationId
    $thumbprint = $conn.CertificateThumbprint
    $tenantId = $conn.TenantId

    Add-Type -AssemblyName System.Web
    $cert = Get-Item -Path "Cert:\CurrentUser\My\$thumbprint"
    $now = [DateTime]::UtcNow
    $audience = "https://login.microsoftonline.com/$tenantId/oauth2/token"
    $expiry = $now.AddHours(1)

    $header = @{ alg = "RS256"; x5t = [System.Web.HttpServerUtility]::UrlTokenEncode($cert.GetCertHash()) }
    $payload = @{
        aud = $audience; iss = $appId; sub = $appId
        jti = [Guid]::NewGuid().ToString()
        nbf = [int][double]::Parse($now.ToString("yyyyMMddHHmmss"))
        exp = [int][double]::Parse($expiry.ToString("yyyyMMddHHmmss"))
    }
    $headerB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($header | ConvertTo-Json -Compress)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $payloadB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload | ConvertTo-Json -Compress)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $toSign = [Text.Encoding]::UTF8.GetBytes("$headerB64.$payloadB64")
    $sigB64 = [Convert]::ToBase64String($cert.PrivateKey.SignData($toSign, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $jwt = "$headerB64.$payloadB64.$sigB64"

    $body = @{ grant_type = "client_credentials"; client_id = $appId; client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"; client_assertion = $jwt; resource = "https://vault.azure.net" }
    $tokenResp = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token" -Body $body
    $authHeader = @{ Authorization = "Bearer $($tokenResp.access_token)" }

    $url = "https://$KEY_VAULT_NAME.vault.azure.net/secrets/$SecretName/?api-version=7.4"
    $bodyJson = @{ value = $SecretValue } | ConvertTo-Json
    Invoke-RestMethod -Uri $url -Method Put -Headers $authHeader -Body $bodyJson -ContentType "application/json" | Out-Null
}

try {
    Write-Output "Starting scheduled token refresh..."

    $refreshToken = Get-KvSecret -SecretName "fabric-refresh-token"
    if (-not $refreshToken) { throw "No refresh token found in Key Vault." }

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

    Set-KvSecret -SecretName "fabric-refresh-token" -SecretValue $newRefresh
    Set-KvSecret -SecretName "fabric-access-token" -SecretValue $response.access_token
    Set-KvSecret -SecretName "fabric-token-expiry" -SecretValue $expiry

    $expiryDate = Get-Date -UnixTimeSeconds $expiry
    Write-Output "Token refreshed successfully."
    Write-Output "Access token stored (expires: $expiryDate)"
    Write-Output "Refresh token updated."
}
catch {
    Write-Error "Refresh failed: $_"
    throw
}
