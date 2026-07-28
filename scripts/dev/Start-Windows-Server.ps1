#requires -Version 5.1

[CmdletBinding()]
param(
  [string]$EnvFile,
  [string]$ImageTag
)

$arguments = @{}
if ($EnvFile) { $arguments.EnvFile = $EnvFile }
if ($ImageTag) { $arguments.ImageTag = $ImageTag }
& (Join-Path $PSScriptRoot '..\pc\Start-PcStack.ps1') @arguments
