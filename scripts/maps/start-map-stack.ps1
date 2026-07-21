$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
docker compose --project-directory $root --profile maps up -d martin nominatim nginx
if ($LASTEXITCODE -ne 0) { throw 'Map stack failed to start' }
