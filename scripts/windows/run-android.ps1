#requires -Version 5.1

[CmdletBinding()]
param(
  [string]$EnvFile,
  [string]$DeviceId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WindowsLocalTestCommon.ps1')

function Get-WindowsObjectProperty {
  param([object]$InputObject, [string]$Name)
  $property = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-WindowsFlutter {
  $candidate = Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($candidate) { return $candidate.Source }
  $fallback = 'C:\src\flutter\bin\flutter.bat'
  if (Test-Path -LiteralPath $fallback -PathType Leaf) { return $fallback }
  throw 'Flutter was not found on PATH or at C:\src\flutter\bin\flutter.bat'
}

$environmentFile = Get-WindowsLocalTestEnvironmentPath $EnvFile
if (-not (Test-Path -LiteralPath $environmentFile -PathType Leaf)) {
  throw "Local-test environment was not found: $environmentFile. Run start-server.ps1 first."
}
$environment = Read-PcEnvironment $environmentFile
if ($environment['AUTH_MODE'] -ne 'local_test') {
  throw 'run-android.ps1 requires a local_test environment'
}
$lan = ConvertTo-PcUsableIPv4 $environment['LAN_IP']
Assert-WindowsHttpOk "http://$lan`:8080/ready"

$root = Get-WindowsRepositoryRoot
$mainManifest = Join-Path $root 'apps\mobile\android\app\src\main\AndroidManifest.xml'
$debugManifest = Join-Path $root 'apps\mobile\android\app\src\debug\AndroidManifest.xml'
if (-not (Get-Content -Raw -LiteralPath $mainManifest).Contains('android:usesCleartextTraffic="false"') -or
    -not (Get-Content -Raw -LiteralPath $debugManifest).Contains('android:usesCleartextTraffic="true"')) {
  throw 'Android cleartext policy drifted; refusing to run the LAN HTTP contour'
}

$flutter = Get-WindowsFlutter
$deviceJson = @(& $flutter devices --machine 2>$null) -join [Environment]::NewLine
if ($LASTEXITCODE -ne 0 -or -not $deviceJson) { throw 'Unable to enumerate Flutter devices' }
try { $devices = @($deviceJson | ConvertFrom-Json) } catch { throw 'Flutter returned an invalid device list' }
$phones = @($devices | Where-Object {
  ([string](Get-WindowsObjectProperty $_ 'targetPlatform')).StartsWith('android-') -and
  (Get-WindowsObjectProperty $_ 'emulator') -eq $false
})
if ($DeviceId) {
  $selected = @($phones | Where-Object { [string](Get-WindowsObjectProperty $_ 'id') -eq $DeviceId })
  if ($selected.Count -ne 1) { throw 'DeviceId must identify one connected physical Android phone' }
} else {
  if ($phones.Count -eq 0) { throw 'No connected physical Android phone was found' }
  if ($phones.Count -gt 1) { throw 'More than one Android phone is connected; pass -DeviceId' }
  $selected = @($phones[0])
}
$selectedId = [string](Get-WindowsObjectProperty $selected[0] 'id')
$mapStyle = $environment['MAP_STYLE_URL']
if ([string]::IsNullOrWhiteSpace($mapStyle)) { throw 'MAP_STYLE_URL is required' }

$flutterArguments = @(
  'run', '--debug', '-d', $selectedId,
  '--dart-define=APP_ENV=development',
  "--dart-define=API_BASE_URL=http://$lan`:8080/api/v1",
  "--dart-define=WS_BASE_URL=ws://$lan`:8080",
  "--dart-define=MAP_MODE=global_provider",
  "--dart-define=MAP_STYLE_URL=$mapStyle",
  "--dart-define=MAP_API_KEY=$($environment['MAP_API_KEY'])",
  "--dart-define=MAP_DEFAULT_LAT=$($environment['MAP_DEFAULT_LAT'])",
  "--dart-define=MAP_DEFAULT_LNG=$($environment['MAP_DEFAULT_LNG'])",
  "--dart-define=MAP_DEFAULT_ZOOM=$($environment['MAP_DEFAULT_ZOOM'])",
  "--dart-define=MAP_MIN_ZOOM=$($environment['MAP_MIN_ZOOM'])",
  "--dart-define=MAP_MAX_ZOOM=$($environment['MAP_MAX_ZOOM'])",
  "--dart-define=FIRST_PARTY_DOMAINS=$lan",
  '--dart-define=DEMO_MODE=false'
)

Write-Output "Starting Android debug app for $selectedId over http://$lan`:8080."
Push-Location (Join-Path $root 'apps\mobile')
try {
  & $flutter @flutterArguments
  if ($LASTEXITCODE -ne 0) { throw 'Flutter failed to run the Android debug app' }
} finally {
  Pop-Location
}
