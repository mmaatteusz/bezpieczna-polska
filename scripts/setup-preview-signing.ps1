param(
  [string]$Repo = "mmaatteusz/bezpieczna-polska",
  [string]$BackupDir = "$HOME/.bezpieczna-polska/preview-signing"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function New-RandomHex([int]$Bytes = 32) {
  $buffer = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($buffer)
  } finally {
    $rng.Dispose()
  }
  return (($buffer | ForEach-Object { $_.ToString("x2") }) -join "")
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI (gh) is required. Install it, then run: gh auth login"
}
if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
  throw "Java keytool is required. Install a JDK and ensure keytool is in PATH."
}

& gh auth status | Out-Null

$null = New-Item -ItemType Directory -Force -Path $BackupDir
$keystore = Join-Path $BackupDir "preview-signing.jks"
$credentials = Join-Path $BackupDir "preview-signing-credentials.txt"

if (Test-Path $keystore) {
  throw "Refusing to overwrite existing signing key: $keystore. Reuse the existing key for all future preview APKs."
}

$alias = "bezpieczna-polska-preview"
$storePassword = New-RandomHex
$keyPassword = New-RandomHex

& keytool -genkeypair -v -storetype JKS -keystore $keystore -storepass $storePassword -keypass $keyPassword -alias $alias -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Bezpieczna Polska Preview, OU=Android Preview, O=Bezpieczna Polska, C=PL"

$keystoreB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore))

& gh secret set ANDROID_PREVIEW_KEYSTORE_B64 --repo $Repo --body $keystoreB64
& gh secret set ANDROID_PREVIEW_KEYSTORE_PASSWORD --repo $Repo --body $storePassword
& gh secret set ANDROID_PREVIEW_KEY_ALIAS --repo $Repo --body $alias
& gh secret set ANDROID_PREVIEW_KEY_PASSWORD --repo $Repo --body $keyPassword

@"
Repository: $Repo
Keystore: $keystore
ANDROID_PREVIEW_KEYSTORE_PASSWORD=$storePassword
ANDROID_PREVIEW_KEY_ALIAS=$alias
ANDROID_PREVIEW_KEY_PASSWORD=$keyPassword

IMPORTANT:
- Keep this file and preview-signing.jks private and backed up.
- Never commit either file to the repository.
- Never replace this key for package pl.bezpiecznapolska.preview unless you intentionally accept that old preview installs will no longer update in-place.
"@ | Set-Content -Encoding UTF8 $credentials

try {
  if ([System.Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    & icacls $BackupDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null
  }
} catch {
  Write-Warning "Could not tighten Windows ACLs automatically. Protect $BackupDir manually."
}

Write-Host ""
Write-Host "Stable preview signing secrets are configured for $Repo."
Write-Host "Private backup: $BackupDir"
Write-Host "Next: rerun the failed Android GitHub Actions jobs."
Write-Host "Do not delete the keystore or credentials backup."
