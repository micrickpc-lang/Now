$ErrorActionPreference = 'Stop'
$baseUrl = 'http://127.0.0.1'
$timeoutSeconds = 15

for ($index = 0; $index -lt $args.Count; $index += 1) {
  switch ($args[$index]) {
    { $_ -in '--help', '-h' } {
      @'
Usage: ./scripts/maps/smoke-map.ps1 [options]

Probe staging health and versioned map resources. The report records HTTP
status, content type and byte count; it does not claim visual rendering works.

Options:
  --base-url <url>  Staging origin (default: http://127.0.0.1)
  --timeout <sec>   Per-request timeout (default: 15)
  --help            Show this help
'@
      exit 0
    }
    '--base-url' {
      $index += 1
      if ($index -ge $args.Count) { throw '--base-url requires a URL' }
      $baseUrl = $args[$index]
    }
    '--timeout' {
      $index += 1
      if ($index -ge $args.Count) { throw '--timeout requires seconds' }
      $timeoutSeconds = [int]$args[$index]
    }
    default { throw "Unknown option: $($args[$index])" }
  }
}

$origin = [Uri]$baseUrl
if ($origin.Scheme -notin 'http', 'https' -or $origin.Query -or $origin.Fragment) {
  throw '--base-url must be HTTP(S) without query or fragment data'
}
if ($timeoutSeconds -le 0) { throw '--timeout must be positive' }

Add-Type -AssemblyName System.Net.Http
$handler = [System.Net.Http.HttpClientHandler]::new()
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds($timeoutSeconds)
$failures = 0
$probes = @(
  @{ Path = '/health'; Kind = 'json'; Minimum = 2; Expected = 200 },
  @{ Path = '/api/v1/maps/style.json'; Kind = 'json'; Minimum = 100; Expected = 200; Needle = '/maps/v1/tiles/{z}/{x}/{y}.pbf' },
  @{ Path = '/api/v1/maps/tilejson.json'; Kind = 'json'; Minimum = 100; Expected = 200; Needle = '/api/v1/maps/tiles/{z}/{x}/{y}.pbf' },
  @{ Path = '/api/v1/maps/tiles/14/8529/5974.pbf'; Kind = 'pbf'; Minimum = 1; Expected = 200 },
  @{ Path = '/api/v1/maps/search'; Kind = 'json'; Minimum = 2; Expected = 401 },
  @{ Path = '/api/v1/maps/reverse'; Kind = 'json'; Minimum = 2; Expected = 401 },
  @{ Path = '/maps/v1/style.json'; Kind = 'json'; Minimum = 100; Expected = 200; Needle = '/maps/v1/sprites/sprite' },
  @{ Path = '/maps/v1/sprites/sprite.json'; Kind = 'json'; Minimum = 2; Expected = 200 },
  @{ Path = '/maps/v1/sprites/sprite.png'; Kind = 'png'; Minimum = 16; Expected = 200 },
  @{ Path = '/maps/v1/sprites/sprite@2x.json'; Kind = 'json'; Minimum = 2; Expected = 200 },
  @{ Path = '/maps/v1/sprites/sprite@2x.png'; Kind = 'png'; Minimum = 16; Expected = 200 },
  @{ Path = '/maps/v1/glyphs/Noto%20Sans%20Regular/0-255.pbf'; Kind = 'pbf'; Minimum = 8; Expected = 200 },
  @{ Path = '/maps/v1/tiles/14/8529/5974.pbf'; Kind = 'pbf'; Minimum = 1; Expected = 200 }
)

'{0,-52} {1,6} {2,-40} {3,10}' -f 'PATH', 'STATUS', 'CONTENT_TYPE', 'BYTES'
try {
  foreach ($probe in $probes) {
    $uri = [Uri]::new($origin, $probe.Path)
    $response = $null
    try {
      $response = $client.GetAsync($uri).GetAwaiter().GetResult()
      $body = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
      $status = [int]$response.StatusCode
      $contentType = $response.Content.Headers.ContentType.MediaType
      if (-not $contentType) { $contentType = '-' }
    } catch {
      $status = 0
      $contentType = '-'
      $body = [byte[]]::new(0)
    }
    '{0,-52} {1,6} {2,-40} {3,10}' -f $probe.Path, $status, $contentType, $body.Length

    $validType = switch ($probe.Kind) {
      'json' { $contentType -match '^application/(.+\+)?json$' }
      'png' { $contentType -eq 'image/png' }
      'pbf' { $contentType -in 'application/x-protobuf', 'application/vnd.mapbox-vector-tile', 'application/octet-stream' }
    }
    $needle = if ($probe.ContainsKey('Needle')) { [string]$probe.Needle } else { '' }
    $bodyMatches = -not $needle -or [System.Text.Encoding]::UTF8.GetString($body).Contains($needle)
    if ($status -ne $probe.Expected -or -not $validType -or $body.Length -lt $probe.Minimum -or -not $bodyMatches) {
      $failures += 1
    }
    if ($response) { $response.Dispose() }
  }
} finally {
  $client.Dispose()
  $handler.Dispose()
}

if ($failures -ne 0) { throw "$failures map smoke probe(s) failed" }
'Transport smoke passed. Device/MapLibre rendering remains a separate acceptance check.'
