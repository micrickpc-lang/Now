$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$envFile = Join-Path $root '.env.staging'
$dataRoot = if ($env:NOW_DATA_ROOT) { $env:NOW_DATA_ROOT } else { '/opt/now/data' }
$wait = $true

for ($index = 0; $index -lt $args.Count; $index += 1) {
  switch ($args[$index]) {
    { $_ -in '--help', '-h' } {
      @'
Usage: ./scripts/maps/start-map-stack.ps1 [options]

Start the internal Martin and Nominatim runtime services from the standalone
staging Compose file. A completed Nominatim import is required.

Options:
  --env-file <path>   Staging env file (default: .env.staging)
  --data-root <path>  Persistent root (default: NOW_DATA_ROOT or /opt/now/data)
  --no-wait           Do not wait for service health
  --help              Show this help
'@
      exit 0
    }
    '--env-file' {
      $index += 1
      if ($index -ge $args.Count) { throw '--env-file requires a path' }
      $envFile = [System.IO.Path]::GetFullPath($args[$index])
    }
    '--data-root' {
      $index += 1
      if ($index -ge $args.Count) { throw '--data-root requires a path' }
      $dataRoot = [System.IO.Path]::GetFullPath($args[$index])
    }
    '--no-wait' { $wait = $false }
    default { throw "Unknown option: $($args[$index])" }
  }
}

if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
  throw "Staging env file not found: $envFile"
}
foreach ($required in @(
  (Join-Path $dataRoot 'maps\region.osm.pbf'),
  (Join-Path $dataRoot 'maps\seychas-v1.mbtiles'),
  (Join-Path $dataRoot 'nominatim\PG_VERSION')
)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "Required map runtime artifact is missing: $required. Complete the maps-import profile first."
  }
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'Docker Engine with Compose v2 is required'
}

$compose = Join-Path $root 'docker-compose.staging.yml'
$dockerArgs = @('compose', '--env-file', $envFile, '-f', $compose, 'up', '-d')
if ($wait) { $dockerArgs += '--wait' }
$dockerArgs += @('martin', 'nominatim')
& docker @dockerArgs
if ($LASTEXITCODE -ne 0) { throw 'Map runtime failed to start' }
