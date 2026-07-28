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
$environment = Read-PcEnvironment $environmentFile
$lan = ConvertTo-PcUsableIPv4 $environment['LAN_IP']
$docker = Assert-PcDockerEngine
$compose = Get-WindowsLocalTestComposeArguments $environmentFile
Push-Location (Get-WindowsRepositoryRoot)
try {
  Invoke-WindowsNative $docker ($compose + @('ps')) 'Unable to inspect local-test server'
  Assert-WindowsHttpOk "http://$lan`:8080/health"
  Assert-WindowsHttpOk "http://$lan`:8080/ready"
  Write-Output "Local-test server is healthy at http://$lan`:8080"
} finally {
  Pop-Location
}
