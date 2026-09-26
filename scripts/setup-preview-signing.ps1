param(
  [string]$Repo = "mmaatteusz/bezpieczna-polska",
  [string]$BackupDir = "$HOME/.bezpieczna-polska/preview-signing"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedPreviewCertSha256 = "1f7f3f2aea7073889563b7461e7dfd8f80929a36fff8138c51a2a9516db153d2"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI (gh) is required. Install it, then run: gh auth login"
}
if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
  throw "Java keytool is required. Install a JDK and ensure keytool is in PATH."
}

& gh auth status | Out-Null
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI is not authenticated." }

$keystore = Join-Path $BackupDir "preview-signing.jks"
$credentials = Join-Path $BackupDir "preview-signing-credentials.txt"

if (-not (Test-Path $keystore) -or -not (Test-Path $credentials)) {
  throw @"
Stable preview signing backup is missing from:
  $BackupDir

Do NOT generate a replacement key. A new key would make existing
pl.bezpiecznapolska.preview installations impossible to update in place.
Recover preview-signing.jks and preview-signing-credentials.txt from backup.
"@
}

$values = @{}
Get-Content $credentials | ForEach-Object {
  if ($_ -match '^([^=]+)=(.*)$') {
    $values[$matches[1].Trim()] = $matches[2].Trim()
  }
}

foreach ($name in @("ANDROID_PREVIEW_KEYSTORE_PASSWORD", "ANDROID_PREVIEW_KEY_ALIAS", "ANDROID_PREVIEW_KEY_PASSWORD")) {
  if (-not $values.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($values[$name])) {
    throw "Missing $name in $credentials"
  }
}

$storePassword = $values["ANDROID_PREVIEW_KEYSTORE_PASSWORD"]
$alias = $values["ANDROID_PREVIEW_KEY_ALIAS"]
$keyPassword = $values["ANDROID_PREVIEW_KEY_PASSWORD"]

$tempCert = Join-Path ([IO.Path]::GetTempPath()) ("bp-preview-" + [Guid]::NewGuid().ToString("N") + ".cer")
try {
  & keytool -exportcert -keystore $keystore -storepass $storePassword -alias $alias -file $tempCert | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "keytool could not read the preview signing key." }
  $actualSha256 = (Get-FileHash -Algorithm SHA256 $tempCert).Hash.ToLowerInvariant()
} finally {
  Remove-Item $tempCert -Force -ErrorAction SilentlyContinue
}

if ($actualSha256 -ne $ExpectedPreviewCertSha256) {
  throw @"
Preview signing certificate mismatch.
Expected: $ExpectedPreviewCertSha256
Actual:   $actualSha256

Refusing to overwrite GitHub secrets with a key that would break in-place updates.
"@
}

$keystoreB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore))

& gh secret set ANDROID_PREVIEW_KEYSTORE_B64 --repo $Repo --body $keystoreB64
if ($LASTEXITCODE -ne 0) { throw "Failed to set ANDROID_PREVIEW_KEYSTORE_B64" }
& gh secret set ANDROID_PREVIEW_KEYSTORE_PASSWORD --repo $Repo --body $storePassword
if ($LASTEXITCODE -ne 0) { throw "Failed to set ANDROID_PREVIEW_KEYSTORE_PASSWORD" }
& gh secret set ANDROID_PREVIEW_KEY_ALIAS --repo $Repo --body $alias
if ($LASTEXITCODE -ne 0) { throw "Failed to set ANDROID_PREVIEW_KEY_ALIAS" }
& gh secret set ANDROID_PREVIEW_KEY_PASSWORD --repo $Repo --body $keyPassword
if ($LASTEXITCODE -ne 0) { throw "Failed to set ANDROID_PREVIEW_KEY_PASSWORD" }

Write-Host ""
Write-Host "Stable preview signing restored and verified."
Write-Host "Repository: $Repo"
Write-Host "Certificate SHA-256: $actualSha256"
Write-Host "Backup: $BackupDir"
Write-Host "Existing preview APKs remain on the same signing/update chain."
