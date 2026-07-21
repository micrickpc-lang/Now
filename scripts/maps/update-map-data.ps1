$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Push-Location $root
try {
  node scripts/maps/download-region.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Region update download failed' }
  & scripts/maps/build-tiles.ps1
  node scripts/maps/validate-map-style.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Map style validation failed' }
  docker compose --profile maps restart martin
} finally {
  Pop-Location
}
