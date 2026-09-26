param(
  [string]$Repo = "mmaatteusz/bezpieczna-polska",
  [string]$BackupDir = "$HOME/.bezpieczna-polska/production-signing"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function New-RandomHex([int]$Bytes = 32) {
  $buffer = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
  return (($buffer | ForEach-Object { $_.ToString("x2") }) -join "")
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI (gh) is required. Install it, then run: gh auth login"
}
if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
  throw "Java keytool is required. Install a JDK and ensure keytool is in PATH."
}
& gh auth status | Out-Null
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI is not authenticated." }

$null = New-Item -ItemType Directory -Force -Path $BackupDir
$keystore = Join-Path $BackupDir "production-signing.jks"
$credentials = Join-Path $BackupDir "production-signing-credentials.txt"

if ((Test-Path $keystore) -xor (Test-Path $credentials)) {
  throw "Production signing backup is incomplete. Recover both $keystore and $credentials before continuing."
}

if (-not (Test-Path $keystore)) {
  $alias = "bezpieczna-polska-production"
  $storePassword = New-RandomHex
  $keyPassword = New-RandomHex

  & keytool -genkeypair -v -storetype JKS -keystore $keystore -storepass $storePassword -keypass $keyPassword -alias $alias -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Bezpieczna Polska, OU=Android Production, O=Bezpieczna Polska, C=PL"
  if ($LASTEXITCODE -ne 0) { throw "Failed to create production keystore." }

  @"
Repository: $Repo
Keystore: $keystore
ANDROID_KEYSTORE_PASSWORD=$storePassword
ANDROID_KEY_ALIAS=$alias
ANDROID_KEY_PASSWORD=$keyPassword

IMPORTANT:
- This is the permanent production signing identity for pl.bezpiecznapolska.
- Keep at least two encrypted offline backups in separate locations.
- Losing this key can prevent future direct APK updates and may complicate store releases.
- Never commit this file or the keystore.
"@ | Set-Content -Encoding UTF8 $credentials
} else {
  $values = @{}
  Get-Content $credentials | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
      $values[$matches[1].Trim()] = $matches[2].Trim()
    }
  }
  foreach ($name in @("ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD")) {
    if (-not $values.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($values[$name])) {
      throw "Missing $name in $credentials"
    }
  }
  $storePassword = $values["ANDROID_KEYSTORE_PASSWORD"]
  $alias = $values["ANDROID_KEY_ALIAS"]
  $keyPassword = $values["ANDROID_KEY_PASSWORD"]
}

$tempCert = Join-Path ([IO.Path]::GetTempPath()) ("bp-production-" + [Guid]::NewGuid().ToString("N") + ".cer")
try {
  & keytool -exportcert -keystore $keystore -storepass $storePassword -alias $alias -file $tempCert | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "keytool could not read the production signing key." }
  $certSha256 = (Get-FileHash -Algorithm SHA256 $tempCert).Hash.ToLowerInvariant()
} finally {
  Remove-Item $tempCert -Force -ErrorAction SilentlyContinue
}

$keystoreB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore))

& gh secret set ANDROID_KEYSTORE_B64 --repo $Repo --body $keystoreB64
if ($LASTEXITCODE -ne 0) { throw "Failed to set ANDROID_KEYSTORE_B64" }
& gh secret set ANDROID_KEYSTORE_PASSWORD --repo $Repo --body $storePassword
if ($LASTEXITCODE -ne 0) { throw "Failed to set ANDROID_KEYSTORE_PASSWORD" }
& gh secret set ANDROID_KEY_ALIAS --repo $Repo --body $alias
if ($LASTEXITCODE -ne 0) { throw "Failed to set ANDROID_KEY_ALIAS" }
& gh secret set ANDROID_KEY_PASSWORD --repo $Repo --body $keyPassword
if ($LASTEXITCODE -ne 0) { throw "Failed to set ANDROID_KEY_PASSWORD" }
& gh variable set PRODUCTION_SIGNING_CERT_SHA256 --repo $Repo --body $certSha256
if ($LASTEXITCODE -ne 0) { throw "Failed to set PRODUCTION_SIGNING_CERT_SHA256" }

try {
  if ([System.Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    & icacls $BackupDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null
  }
} catch {
  Write-Warning "Could not tighten Windows ACLs automatically. Protect $BackupDir manually."
}

Write-Host ""
Write-Host "Production signing identity is configured for $Repo."
Write-Host "Certificate SHA-256: $certSha256"
Write-Host "Private backup: $BackupDir"
Write-Host "Do not regenerate this key after distributing pl.bezpiecznapolska."
