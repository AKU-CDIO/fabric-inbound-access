param(
    [string]$KeyVaultName = "uzima-fabric-tokens",
    [string]$SecretName = "researcher-whitelist",
    [string[]]$Emails = @(
        "derick.imbati@aku.edu",
        "rais.muhammad@aku.edu",
        "dorcasm@umich.edu",
        "yechank@med.umich.edu",
        "nannab@med.umich.edu"
    ),
    [switch]$AppendExisting
)

$ErrorActionPreference = "Stop"

$normalized = $Emails |
    ForEach-Object { $_.Trim().ToLowerInvariant() } |
    Where-Object { $_ } |
    Sort-Object -Unique

if ($AppendExisting) {
    $existingRaw = az keyvault secret show `
        --vault-name $KeyVaultName `
        --name $SecretName `
        --query value -o tsv 2>$null

    if ($existingRaw) {
        try {
            $existing = $existingRaw | ConvertFrom-Json
        } catch {
            $existing = $existingRaw.Trim("[]").Split(",")
        }

        $normalized = @($normalized + $existing) |
            ForEach-Object { "$_".Trim().Trim('"').ToLowerInvariant() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    }
}

$json = ConvertTo-Json -InputObject @($normalized) -Compress
$tempFile = Join-Path $env:TEMP "uzima-researcher-whitelist.json"
[System.IO.File]::WriteAllText($tempFile, $json, [System.Text.UTF8Encoding]::new($false))

az keyvault secret set `
    --vault-name $KeyVaultName `
    --name $SecretName `
    --file $tempFile `
    --encoding utf-8 `
    --query "{name:name,updated:attributes.updated}" `
    -o json

Write-Host ""
Write-Host "Stored whitelist:"
$json
