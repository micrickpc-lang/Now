#requires -Version 5.1

<#
.SYNOPSIS
Builds and starts the isolated Windows PC/LAN staging stack.
#>

[CmdletBinding()]
param(
  [string]$EnvFile,

  [string]$ImageTag
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PcCommon.ps1')

function Get-PcComposeConfiguration {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Docker,

    [Parameter(Mandatory = $true)]
    [object[]]$ComposeArguments
  )

  $json = @(
    & $Docker @($ComposeArguments + @('config', '--format', 'json')) 2>$null
  ) -join [System.Environment]::NewLine
  if ($LASTEXITCODE -ne 0 -or -not $json) {
    throw 'Unable to inspect the resolved PC Compose configuration'
  }
  try {
    return $json | ConvertFrom-Json
  } catch {
    throw 'Docker Compose returned an invalid configuration document'
  }
}

function Assert-PcOnlyNginxPublishesPorts {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Configuration,

    [Parameter(Mandatory = $true)]
    [string]$LanIPv4
  )

  $publishedServices = @()
  $nginxPorts = @()
  foreach ($serviceProperty in $Configuration.services.PSObject.Properties) {
    $portsProperty = $serviceProperty.Value.PSObject.Properties['ports']
    $ports = @()
    if ($null -ne $portsProperty -and $null -ne $portsProperty.Value) {
      $ports = @($portsProperty.Value)
    }
    if ($ports.Count -gt 0) {
      $publishedServices += $serviceProperty.Name
      if ($serviceProperty.Name -eq 'nginx') {
        $nginxPorts = $ports
      }
    }
  }

  if (
    $publishedServices.Count -ne 1 -or
    $publishedServices[0] -ne 'nginx' -or
    $nginxPorts.Count -ne 1
  ) {
    throw 'Only one Nginx port mapping may be published by the PC stack'
  }

  $port = $nginxPorts[0]
  if (
    [string]$port.host_ip -notin @('0.0.0.0', $LanIPv4) -or
    [string]$port.published -ne '80' -or
    [string]$port.target -ne '8080' -or
    [string]$port.protocol -ne 'tcp'
  ) {
    throw 'Nginx must bind LAN IPv4 TCP port 80 to container port 8080'
  }
}

function Assert-PcHttpOk {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Uri
  )

  try {
    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 15
  } catch {
    throw "Health probe failed: $Uri"
  }
  if ([int]$response.StatusCode -ne 200) {
    throw "Health probe returned HTTP $($response.StatusCode): $Uri"
  }
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
$docker = Assert-PcDockerEngine
$compose = Get-PcComposeArguments $resolvedEnv

if (-not $ImageTag) {
  $gitPaths = @(
    Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
      ForEach-Object { $_.Source } |
      Where-Object { $_ } |
      Select-Object -Unique
  )
  if ($gitPaths.Count -eq 0) {
    throw 'Git is required to derive the PC image tag'
  }
  $git = [string]$gitPaths[0]
  $imageTagOutput = @(
    & $git -C $root rev-parse --short=12 HEAD 2>$null
  )
  if ($LASTEXITCODE -ne 0 -or $imageTagOutput.Count -ne 1) {
    throw 'Unable to derive the PC image tag from Git'
  }
  $ImageTag = $imageTagOutput[0].Trim()
}
if ($ImageTag -notmatch '^[A-Za-z0-9_.-]+$') {
  throw 'ImageTag may contain only letters, numbers, dots, underscores and dashes'
}

$hadImageTag = Test-Path Env:IMAGE_TAG
$previousImageTag = $env:IMAGE_TAG
$hadParallelLimit = Test-Path Env:COMPOSE_PARALLEL_LIMIT
$previousParallelLimit = $env:COMPOSE_PARALLEL_LIMIT
$env:IMAGE_TAG = $ImageTag
$env:COMPOSE_PARALLEL_LIMIT = '1'

Push-Location $root
try {
  Invoke-PcNativeCommand $docker ($compose + @('config', '--quiet')) `
    'The PC Compose configuration is invalid'
  $configuration = Get-PcComposeConfiguration $docker $compose
  Assert-PcOnlyNginxPublishesPorts $configuration $lanIPv4

  foreach ($artifact in @(
    (Join-Path $root 'infra\maps\data\region.osm.pbf'),
    (Join-Path $root 'infra\maps\data\seychas-v1.mbtiles')
  )) {
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
      throw "Required map artifact is missing: $artifact"
    }
  }
  foreach ($marker in @('PG_VERSION', 'import-finished')) {
    if (-not (Test-PcNominatimMarker $docker $compose $marker)) {
      throw "Required Nominatim readiness marker is missing: $marker"
    }
  }

  foreach ($service in @('migrate', 'api', 'worker')) {
    Invoke-PcNativeCommand $docker ($compose + @('build', $service)) `
      "PC image build failed for $service"
  }
  Invoke-PcNativeCommand $docker (
    $compose + @('up', '-d', '--wait', '--wait-timeout', '600')
  ) 'The PC stack did not become healthy'

  Invoke-PcNativeCommand $docker ($compose + @('ps')) `
    'Unable to inspect the running PC stack'

  $baseUrl = "http://$lanIPv4"
  Assert-PcHttpOk "$baseUrl/health"
  Assert-PcHttpOk "$baseUrl/ready"
  & (Join-Path $root 'scripts\maps\smoke-map.ps1') --base-url $baseUrl
  if ($LASTEXITCODE -ne 0) {
    throw 'PC map smoke test failed'
  }
  Write-Output "Public API address: http://$publicIPv4"

  Write-Output "PC staging is healthy at $baseUrl (image tag: $ImageTag)."
} finally {
  Pop-Location
  if ($hadImageTag) {
    $env:IMAGE_TAG = $previousImageTag
  } else {
    Remove-Item Env:IMAGE_TAG -ErrorAction SilentlyContinue
  }
  if ($hadParallelLimit) {
    $env:COMPOSE_PARALLEL_LIMIT = $previousParallelLimit
  } else {
    Remove-Item Env:COMPOSE_PARALLEL_LIMIT -ErrorAction SilentlyContinue
  }
}
