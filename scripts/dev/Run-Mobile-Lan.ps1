#requires -Version 5.1

[CmdletBinding()]
param(
  [string]$EnvFile,
  [string]$DeviceId
)

$arguments = @{ UseLanApi = $true }
if ($EnvFile) { $arguments.EnvFile = $EnvFile }
if ($DeviceId) { $arguments.DeviceId = $DeviceId }
& (Join-Path $PSScriptRoot '..\pc\Run-AndroidPhone.ps1') @arguments
