$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw 'Node.js 24+ is required'
}

& node (Join-Path $root 'scripts\maps\validate-map-style.mjs') @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
