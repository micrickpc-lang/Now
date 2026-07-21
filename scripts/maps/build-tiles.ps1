$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$data = Join-Path $root 'infra\maps\data'
$source = Join-Path $data 'region.osm.pbf'
$output = Join-Path $data 'seychas.mbtiles'
if (-not (Test-Path -LiteralPath $source)) { throw 'Run npm run maps:download first' }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Engine with Compose v2 is required' }
docker run --rm --network none -v "${data}:/data" ghcr.io/systemed/tilemaker:master /data/region.osm.pbf --output /data/seychas.mbtiles
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) { throw 'Tile build failed' }
Write-Output "Built $output"
