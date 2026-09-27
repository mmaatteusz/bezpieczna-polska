param(
  [Parameter(Mandatory = $true)]
  [string]$CsvPath,

  [string]$ApiBaseUrl = $env:API_BASE_URL,

  [string]$AdminToken = $env:ADMIN_TOKEN
)

$ErrorActionPreference = 'Stop'

if (-not $ApiBaseUrl) {
  throw 'Set API_BASE_URL or pass -ApiBaseUrl.'
}
if (-not $AdminToken -or $AdminToken.Length -lt 32) {
  throw 'Set ADMIN_TOKEN or pass -AdminToken (minimum 32 characters).'
}
if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
  throw "CSV file not found: $CsvPath"
}

$file = Get-Item -LiteralPath $CsvPath
if ($file.Length -gt 32MB) {
  throw "CSV is larger than the 32 MB import limit: $($file.Length) bytes"
}

$uri = $ApiBaseUrl.TrimEnd('/') + '/admin/shelters/import'
Write-Host "Importing official shelter CSV: $($file.FullName)"
Write-Host "Target: $uri"

$response = Invoke-WebRequest `
  -Method Post `
  -Uri $uri `
  -Headers @{ Authorization = "Bearer $AdminToken" } `
  -ContentType 'text/csv; charset=utf-8' `
  -InFile $file.FullName

$result = $response.Content | ConvertFrom-Json
$result | ConvertTo-Json -Depth 8

if (-not $result.ok) {
  throw 'Shelter import did not return ok=true.'
}

Write-Host "Imported $($result.itemCount) shelter points; data date $($result.dataDate)."
