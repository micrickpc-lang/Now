$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$force = $false

foreach ($argument in $args) {
  switch ($argument) {
    { $_ -in '--help', '-h' } {
      @'
Usage: ./scripts/maps/build-tiles.ps1 [options]

Build infra/maps/data/seychas-v1.mbtiles with the repository-pinned Tilemaker
image and profile. The verified PBF and checksum sidecar must already exist.

Options:
  --force  Atomically replace an existing v1 MBTiles file
  --help   Show this help
'@
      exit 0
    }
    '--force' { $force = $true }
    default { throw "Unknown option: $argument" }
  }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'Docker Engine is required'
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw 'Node.js 24+ is required'
}

$data = Join-Path $root 'infra\maps\data'
$source = Join-Path $data 'region.osm.pbf'
$output = Join-Path $data 'seychas-v1.mbtiles'
$partial = "$output.partial"
$tilemaker = Join-Path $root 'infra\maps\tilemaker'
$image = (Get-Content -Raw -Encoding utf8 (Join-Path $tilemaker 'image.txt')).Trim()
if ($image -notmatch '^ghcr\.io/systemed/tilemaker:\d+\.\d+\.\d+$') {
  throw 'Tilemaker image must be pinned to a semantic version'
}
if ((Test-Path -LiteralPath $output) -and -not $force) {
  throw 'Versioned MBTiles already exists; pass --force to replace it'
}

& node (Join-Path $root 'scripts\maps\download-region.mjs') --verify-only
if ($LASTEXITCODE -ne 0) { throw 'PBF checksum verification failed' }
& node (Join-Path $root 'scripts\maps\generate-assets.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Map asset generation failed' }

if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
$dockerArgs = @(
  'run', '--rm', '--network', 'none', '--cpus', '1.5', '--memory', '768m',
  '--pids-limit', '256',
  '-v', "${data}:/data",
  '-v', "${tilemaker}:/config:ro",
  $image,
  '/data/region.osm.pbf',
  '--output', '/data/seychas-v1.mbtiles.partial',
  '--config', '/config/config.json',
  '--process', '/config/process.lua'
)
& docker @dockerArgs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $partial)) {
  throw 'Tilemaker failed to produce the versioned MBTiles file'
}

& node (Join-Path $root 'scripts\maps\validate-map-style.mjs') --mbtiles $partial
if ($LASTEXITCODE -ne 0) { throw 'Generated MBTiles validation failed' }
Move-Item -LiteralPath $partial -Destination $output -Force
Write-Output "Built $output with $image"
