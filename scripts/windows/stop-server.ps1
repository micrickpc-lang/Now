#requires -Version 5.1

[CmdletBinding()]
param([string]$EnvFile)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WindowsLocalTestCommon.ps1')

$environmentFile = Get-WindowsLocalTestEnvironmentPath $EnvFile
if (-not (Test-Path -LiteralPath $environmentFile -PathType Leaf)) {
  throw "Local-test environment was not found: $environmentFile"
}
$docker = Assert-PcDockerEngine
$compose = Get-WindowsLocalTestComposeArguments $environmentFile
Push-Location (Get-WindowsRepositoryRoot)
try {
  Invoke-WindowsNative $docker ($compose + @('down')) 'Unable to stop local-test server'
} finally {
  Pop-Location
}
