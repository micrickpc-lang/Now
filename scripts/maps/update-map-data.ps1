$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$envFile = Join-Path $root '.env.staging'
$dataRoot = if ($env:NOW_DATA_ROOT) { $env:NOW_DATA_ROOT } else { '/opt/now/data' }
$restart = $true

for ($index = 0; $index -lt $args.Count; $index += 1) {
  switch ($args[$index]) {
    { $_ -in '--help', '-h' } {
      @'
Usage: ./scripts/maps/update-map-data.ps1 [options]

Download a checksum-verified Monaco PBF, rebuild v1 tiles, validate the result,
publish artifacts atomically to staging data, and restart Martin only.

Options:
  --env-file <path>   Staging env file (default: .env.staging)
  --data-root <path>  Persistent root (default: NOW_DATA_ROOT or /opt/now/data)
  --no-restart        Publish files without restarting Martin
  --help              Show this help

Nominatim is not re-imported by this command. Use the explicit maps-import
maintenance procedure for geocoder data changes.
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
    '--no-restart' { $restart = $false }
    default { throw "Unknown option: $($args[$index])" }
  }
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 24+ is required' }
$dataRoot = [System.IO.Path]::GetFullPath($dataRoot)
$rootPath = [System.IO.Path]::GetPathRoot($dataRoot)
if ($dataRoot -eq $rootPath) { throw '--data-root cannot be a filesystem root' }

& node (Join-Path $root 'scripts\maps\download-region.mjs') --force
if ($LASTEXITCODE -ne 0) { throw 'Region update download failed' }
& (Join-Path $root 'scripts\maps\build-tiles.ps1') --force
& node (Join-Path $root 'scripts\maps\validate-map-style.mjs') --mbtiles (Join-Path $root 'infra\maps\data\seychas-v1.mbtiles')
if ($LASTEXITCODE -ne 0) { throw 'Map validation failed' }

$target = Join-Path $dataRoot 'maps'
New-Item -ItemType Directory -Path $target -Force | Out-Null
foreach ($name in @('region.osm.pbf', 'region.osm.pbf.metadata.json', 'seychas-v1.mbtiles')) {
  $source = Join-Path $root "infra\maps\data\$name"
  $temporary = Join-Path $target "$name.new"
  Copy-Item -LiteralPath $source -Destination $temporary -Force
  Move-Item -LiteralPath $temporary -Destination (Join-Path $target $name) -Force
}

if ($restart) {
  if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) { throw "Staging env file not found: $envFile" }
  & docker compose --env-file $envFile -f (Join-Path $root 'docker-compose.staging.yml') restart martin
  if ($LASTEXITCODE -ne 0) { throw 'Martin restart failed' }
}
Write-Output 'Map tiles updated. Nominatim data was not re-imported.'
