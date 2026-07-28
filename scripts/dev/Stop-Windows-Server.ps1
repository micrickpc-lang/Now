#requires -Version 5.1

[CmdletBinding()]
param(
  [string]$EnvFile,
  [ValidateRange(1, 600)]
  [int]$TimeoutSeconds = 60
)

$arguments = @{ TimeoutSeconds = $TimeoutSeconds }
if ($EnvFile) { $arguments.EnvFile = $EnvFile }
& (Join-Path $PSScriptRoot '..\pc\Stop-PcStack.ps1') @arguments
