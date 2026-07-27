#requires -Version 5.1

<#
.SYNOPSIS
Stops PC/LAN containers while preserving containers, data, and named volumes.
#>

[CmdletBinding()]
param(
  [string]$EnvFile,

  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 60
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
[void](Read-PcEnvironment $resolvedEnv)
$docker = Assert-PcDockerEngine
$compose = Get-PcComposeArguments $resolvedEnv

Push-Location $root
try {
  Invoke-PcNativeCommand $docker (
    $compose + @(
      '--profile', 'maps-import',
      'stop', '--timeout', [string]$TimeoutSeconds
    )
  ) 'Unable to stop the PC stack'
  Invoke-PcNativeCommand $docker (
    $compose + @('--profile', 'maps-import', 'ps')
  ) 'Unable to inspect the stopped PC stack'
} finally {
  Pop-Location
}

Write-Output 'PC stack stopped. Containers and named volumes were preserved.'
