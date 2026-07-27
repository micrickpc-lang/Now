#requires -Version 5.1

<#
.SYNOPSIS
Builds verified map artifacts and performs the one-time PC Nominatim import.
#>

[CmdletBinding()]
param(
  [string]$EnvFile,

  [switch]$RefreshDownload
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PcCommon.ps1')

$root = Get-PcRepositoryRoot
$resolvedEnv = if ($EnvFile) {
  Resolve-PcPath $EnvFile
} else {
  Join-Path $root '.env.pc'
}
$environment = Read-PcEnvironment $resolvedEnv
[void](Get-PcEnvironmentLanIPv4 $environment)
$docker = Assert-PcDockerEngine
$compose = Get-PcComposeArguments $resolvedEnv

Push-Location $root
try {
  Invoke-PcNativeCommand $docker ($compose + @('config', '--quiet')) `
    'The PC Compose configuration is invalid'

  $running = @(
    & $docker @($compose + @(
      '--profile', 'maps-import', 'ps', '--status', 'running', '--services'
    )) 2>$null
  )
  if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect the PC stack before map initialization'
  }
  if (@($running | Where-Object { $_.Trim() }).Count -ne 0) {
    throw 'Stop the PC stack before building maps or importing Nominatim'
  }

  $downloadArguments = @()
  if ($RefreshDownload) {
    $downloadArguments += '--force'
  }
  & (Join-Path $root 'scripts\maps\download-region.ps1') @downloadArguments
  if ($LASTEXITCODE -ne 0) {
    throw 'Map extract download or verification failed'
  }

  & (Join-Path $root 'scripts\maps\build-tiles.ps1') --force
  if ($LASTEXITCODE -ne 0) {
    throw 'Map tile build failed'
  }

  $mbtiles = Join-Path $root 'infra\maps\data\seychas-v1.mbtiles'
  & (Join-Path $root 'scripts\maps\validate-map.ps1') --mbtiles $mbtiles
  if ($LASTEXITCODE -ne 0) {
    throw 'Map validation failed'
  }

  & $docker volume create 'seychas-pc-nginx-map-cache' *> $null
  if ($LASTEXITCODE -ne 0) {
    throw 'Unable to create the PC Nginx map-cache volume'
  }
  Invoke-PcNativeCommand $docker @(
    'run', '--rm', '--network', 'none', '--user', '0:0',
    '--volume', 'seychas-pc-nginx-map-cache:/cache',
    'nginxinc/nginx-unprivileged:1.29-alpine',
    'chown', '-R', '101:101', '/cache'
  ) 'Unable to initialize the PC Nginx map-cache volume'

  $hasPgVersion = Test-PcNominatimMarker $docker $compose 'PG_VERSION'
  $hasImportFinished =
    Test-PcNominatimMarker $docker $compose 'import-finished'
  if ($hasPgVersion -and $hasImportFinished) {
    Write-Output 'Verified map artifacts and the existing Nominatim import are ready.'
    return
  }
  if ($hasPgVersion -or $hasImportFinished) {
    throw (
      'Incomplete Nominatim data found. This script will not reset the named ' +
      'volume; preserve or remove it explicitly before retrying.'
    )
  }

  Invoke-PcNativeCommand $docker (
    $compose + @('--profile', 'maps-import', 'config', '--quiet')
  ) 'The maps-import Compose configuration is invalid'
  Invoke-PcNativeCommand $docker (
    $compose + @(
      '--profile', 'maps-import',
      'up', '-d', '--wait', '--wait-timeout', '3600',
      'nominatim-import'
    )
  ) 'The one-time Nominatim import did not become healthy'
  Invoke-PcNativeCommand $docker (
    $compose + @('--profile', 'maps-import', 'stop', 'nominatim-import')
  ) 'Unable to stop the completed Nominatim importer'
  Invoke-PcNativeCommand $docker (
    $compose + @('--profile', 'maps-import', 'rm', '-f', 'nominatim-import')
  ) 'Unable to remove the completed Nominatim importer container'

  $hasPgVersion = Test-PcNominatimMarker $docker $compose 'PG_VERSION'
  $hasImportFinished =
    Test-PcNominatimMarker $docker $compose 'import-finished'
  if (-not $hasPgVersion -or -not $hasImportFinished) {
    throw 'Nominatim import completed without both required readiness markers'
  }

  Write-Output 'Verified map artifacts and the one-time Nominatim import are ready.'
} finally {
  Pop-Location
}
