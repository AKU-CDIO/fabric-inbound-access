# Auto-set FABRIC_ACCESS_TOKEN from encrypted token on user logon
$encPath = "$env:ProgramData\UZIMA\FabricTokenBroker\access-token.enc"
if (-not (Test-Path $encPath)) { exit 0 }

try {
    $enc = Get-Content $encPath -Raw
    $s = (Get-WmiObject Win32_OperatingSystem).SerialNumber
    $k = "uzima-$s"
    $sha = [Security.Cryptography.SHA256]::Create()
    $kb = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($k)))
    $sec = ConvertTo-SecureString -String $enc -Key ([Text.Encoding]::UTF8.GetBytes($kb.Substring(0,32)))
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    try { $data = $plain | ConvertFrom-Json; $tok = $data.access_token } catch { $tok = $plain }
    [Environment]::SetEnvironmentVariable("FABRIC_ACCESS_TOKEN", $tok, "User")
    [Environment]::SetEnvironmentVariable("FABRIC_DELEGATED_ACCESS_TOKEN", $tok, "User")
    # Sync fab_token.txt to user profile for .Rprofile
    $tokenFile = "$env:USERPROFILE\fab_token.txt"
    if ($tok -and (Test-Path "$env:ProgramData\UZIMA\FabricTokenBroker\fab_token.txt")) {
        Copy-Item "$env:ProgramData\UZIMA\FabricTokenBroker\fab_token.txt" $tokenFile -Force -ErrorAction SilentlyContinue
    } elseif ($tok) {
        $tok | Out-File -FilePath $tokenFile -Encoding ascii -NoNewline -ErrorAction SilentlyContinue
    }
} catch { }
