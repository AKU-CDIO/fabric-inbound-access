param()

$encPath = "$env:ProgramData\UZIMA\FabricTokenBroker\access-token.enc"

if (-not (Test-Path $encPath)) {
    Write-Error "No encrypted token found at $encPath"
    exit 1
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

# Handle both JSON wrapper and raw JWT formats
try {
    $data = $plain | ConvertFrom-Json
    if ($data.access_token) {
        Write-Output $data.access_token
    } else {
        Write-Output $plain
    }
} catch {
    Write-Output $plain
}
