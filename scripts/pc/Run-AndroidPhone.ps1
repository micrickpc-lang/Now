#requires -Version 5.1

<#
.SYNOPSIS
Runs the staging app on a connected physical Android phone over the PC LAN.
#>

[CmdletBinding()]
param(
  [string]$EnvFile,

  [string]$DeviceId,

  [switch]$UseLanApi
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PcCommon.ps1')

function Get-PcObjectProperty {
  param(
    [Parameter(Mandatory = $true)]
    [object]$InputObject,

    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $property = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

$root = Get-PcRepositoryRoot
$resolvedEnv = if ($EnvFile) {
  Resolve-PcPath $EnvFile
} else {
  Join-Path $root '.env.pc'
}
$environment = Read-PcEnvironment $resolvedEnv
$lanIPv4 = Get-PcEnvironmentLanIPv4 $environment
$publicIPv4 = Get-PcPublicIPv4 $environment

$flutterPaths = @(
  Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Source } |
    Where-Object { $_ } |
    Select-Object -Unique
)
if ($flutterPaths.Count -eq 0) {
  $flutter = 'C:\src\flutter\bin\flutter.bat'
  if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
    throw (
      'Flutter was not found on PATH or at ' +
      'C:\src\flutter\bin\flutter.bat'
    )
  }
} else {
  $flutter = [string]$flutterPaths[0]
}

$mainManifest =
  Join-Path $root 'apps\mobile\android\app\src\main\AndroidManifest.xml'
$debugManifest =
  Join-Path $root 'apps\mobile\android\app\src\debug\AndroidManifest.xml'
if (
  -not (Get-Content -Raw -LiteralPath $mainManifest).Contains(
    'android:usesCleartextTraffic="false"'
  ) -or
  -not (Get-Content -Raw -LiteralPath $debugManifest).Contains(
    'android:usesCleartextTraffic="true"'
  )
) {
  throw 'Android cleartext policy drifted; refusing to run the LAN HTTP contour'
}

$deviceJson = @(& $flutter devices --machine 2>$null) -join `
  [System.Environment]::NewLine
if ($LASTEXITCODE -ne 0 -or -not $deviceJson) {
  throw 'Unable to enumerate Flutter devices'
}
try {
  $devices = @($deviceJson | ConvertFrom-Json)
} catch {
  throw 'Flutter returned an invalid device list'
}

$physicalAndroidDevices = @(
  $devices |
    Where-Object {
      $platform = [string](Get-PcObjectProperty $_ 'targetPlatform')
      $emulator = Get-PcObjectProperty $_ 'emulator'
      $platform.StartsWith('android-') -and $emulator -eq $false
    }
)
if ($DeviceId) {
  $selected = @(
    $physicalAndroidDevices |
      Where-Object { [string](Get-PcObjectProperty $_ 'id') -eq $DeviceId }
  )
  if ($selected.Count -ne 1) {
    throw 'DeviceId must identify a connected physical Android phone'
  }
  $selectedDevice = $selected[0]
} else {
  if ($physicalAndroidDevices.Count -eq 0) {
    throw 'No connected physical Android phone was found'
  }
  if ($physicalAndroidDevices.Count -gt 1) {
    throw 'Multiple Android phones are connected; pass -DeviceId explicitly'
  }
  $selectedDevice = $physicalAndroidDevices[0]
}
$selectedId = [string](Get-PcObjectProperty $selectedDevice 'id')

$apiHost = if ($UseLanApi) { $lanIPv4 } else { $publicIPv4 }
$baseUrl = "http://$apiHost"
$flutterArguments = @(
  'run',
  '--debug',
  '-d', $selectedId,
  '--dart-define=APP_ENV=staging',
  "--dart-define=API_BASE_URL=$baseUrl/api/v1",
  "--dart-define=WS_BASE_URL=$baseUrl",
  "--dart-define=MAP_STYLE_URL=$baseUrl/api/v1/maps/style.json",
  "--dart-define=FIRST_PARTY_DOMAINS=$apiHost",
  '--dart-define=DEMO_MODE=false',
  '--dart-define=PILOT_REGION=Monaco pilot'
)

Write-Output (
  ('Starting the Android debug app over ' +
  ($(if ($UseLanApi) { 'LAN' } else { 'public' })) + ' HTTP. ') +
  'Profile/release cleartext remains disabled.'
)
Push-Location (Join-Path $root 'apps\mobile')
try {
  & $flutter @flutterArguments
  if ($LASTEXITCODE -ne 0) {
    throw 'Flutter failed to run the Android debug app'
  }
} finally {
  Pop-Location
}
