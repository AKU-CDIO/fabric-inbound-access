param(
    [string]$KeyVaultName = "uzima-fabric-tokens",
    [string]$ConnectionStringSecretName = "fabric-odbc-connection-string",
    [string]$Server = "fis5jjpzajqe5fxqs4z3vlsjde-zgopmz6jacoezkc3hd6da52lpm.datawarehouse.fabric.microsoft.com",
    [string]$Database = "uzima_db_backup",
    [string]$ManagedIdentityClientId = "4ae6ed7b-b72c-4853-9a3c-10699e60f63e",
    [string]$ManagedIdentityObjectId = "8d88bbab-1c76-4bf0-b4f7-1cb49a001d9e"
)

$ErrorActionPreference = "Stop"

$connectionString = "DRIVER={ODBC Driver 18 for SQL Server};SERVER=$Server;DATABASE=$Database;Authentication=ActiveDirectoryMsi;UID=$ManagedIdentityClientId;Encrypt=yes;TrustServerCertificate=no;"

$tempFile = Join-Path $env:TEMP "uzima-fabric-odbc-connection-string.txt"
[System.IO.File]::WriteAllText($tempFile, $connectionString, [System.Text.UTF8Encoding]::new($false))

az keyvault secret set `
    --vault-name $KeyVaultName `
    --name $ConnectionStringSecretName `
    --file $tempFile `
    --encoding utf-8 `
    --query "{name:name,updated:attributes.updated}" `
    -o json

az keyvault secret set `
    --vault-name $KeyVaultName `
    --name "fabric-managed-identity-client-id" `
    --value $ManagedIdentityClientId `
    --query "{name:name,updated:attributes.updated}" `
    -o json

az keyvault secret set `
    --vault-name $KeyVaultName `
    --name "fabric-managed-identity-object-id" `
    --value $ManagedIdentityObjectId `
    --query "{name:name,updated:attributes.updated}" `
    -o json

Write-Host ""
Write-Host "Stored ODBC connection string for database: $Database"
Write-Host "Managed identity client ID: $ManagedIdentityClientId"