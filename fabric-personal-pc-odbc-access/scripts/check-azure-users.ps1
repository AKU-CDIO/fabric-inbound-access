param(
    [string[]]$Emails = @(
        "derick.imbati@aku.edu",
        "rais.muhammad@aku.edu",
        "dorcasm@umich.edu",
        "yechank@med.umich.edu",
        "nannab@med.umich.edu"
    )
)

$ErrorActionPreference = "Continue"

$tenant = az account show --query tenantId -o tsv 2>$null
Write-Host "Current Azure tenant: $tenant"

foreach ($email in $Emails) {
    Write-Host ""
    Write-Host "Checking $email"

    $json = az ad user show --id $email `
        --query "{id:id,displayName:displayName,userPrincipalName:userPrincipalName,mail:mail,userType:userType,accountEnabled:accountEnabled}" `
        -o json 2>$null

    if ($LASTEXITCODE -eq 0 -and $json) {
        $json
        continue
    }

    Write-Warning "Direct lookup did not resolve $email."
    Write-Warning "If this is a guest account, ask an Entra admin to confirm the exact UPN or object ID."
}
