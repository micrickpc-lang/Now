#requires -Version 5.1

[CmdletBinding()]
param([string]$EnvFile)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\pc\PcCommon.ps1')

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
  Invoke-PcNativeCommand $docker ($compose + @('ps')) `
    'Unable to inspect the PC stack'
} finally {
  Pop-Location
}
