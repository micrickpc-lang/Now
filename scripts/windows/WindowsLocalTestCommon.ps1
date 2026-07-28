#requires -Version 5.1

Set-StrictMode -Version Latest
$script:WindowsRepositoryRoot = (
  Resolve-Path (Join-Path $PSScriptRoot '..\..')
).Path
. (Join-Path $script:WindowsRepositoryRoot 'scripts\pc\PcCommon.ps1')

function Get-WindowsRepositoryRoot {
  return $script:WindowsRepositoryRoot
}

function Get-WindowsLocalTestEnvironmentPath {
  param([string]$EnvFile)
  if ($EnvFile) { return Resolve-PcPath $EnvFile }
  return Join-Path $script:WindowsRepositoryRoot '.env.local-test'
}

function Get-WindowsLocalTestComposeArguments {
  param([Parameter(Mandatory = $true)][string]$EnvFile)
  return @(
    'compose', '--env-file', $EnvFile,
    '-f', (Join-Path $script:WindowsRepositoryRoot 'docker-compose.windows-local-test.yml')
  )
}

function New-WindowsRandomHex {
  $bytes = New-Object byte[] 32
  $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $random.GetBytes($bytes)
    return [System.BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
  } finally {
    $random.Dispose()
  }
}

function New-WindowsRandomBase64 {
  $bytes = New-Object byte[] 32
  $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $random.GetBytes($bytes)
    return [System.Convert]::ToBase64String($bytes)
  } finally {
    $random.Dispose()
  }
}

function Set-WindowsPrivateFileAcl {
  param([Parameter(Mandatory = $true)][string]$Path)
  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  if ($null -eq $identity.User) {
    throw 'Unable to resolve the current Windows identity for the environment file'
  }
  $security = New-Object System.Security.AccessControl.FileSecurity
  $security.SetAccessRuleProtection($true, $false)
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $identity.User,
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    [System.Security.AccessControl.AccessControlType]::Allow
  )
  [void]$security.AddAccessRule($rule)
  [System.IO.File]::SetAccessControl($Path, $security)
}

function Initialize-WindowsLocalTestEnvironment {
  param(
    [Parameter(Mandatory = $true)][string]$EnvFile,
    [string]$LanIPv4
  )
  if (Test-Path -LiteralPath $EnvFile -PathType Leaf) { return }
  if (Test-Path -LiteralPath $EnvFile) {
    throw 'The local-test environment path must be a file path'
  }
  $lan = if ($LanIPv4) {
    ConvertTo-PcUsableIPv4 $LanIPv4
  } else {
    Get-PcLanIPv4
  }
  $parent = Split-Path -Parent $EnvFile
  [void][System.IO.Directory]::CreateDirectory($parent)
  $lines = @(
    "LAN_IP=$lan",
    'POSTGRES_DB=seychas',
    'POSTGRES_USER=seychas',
    "POSTGRES_PASSWORD=$(New-WindowsRandomHex)",
    "JWT_SECRET=$(New-WindowsRandomHex)",
    "TOKEN_HASH_SECRET=$(New-WindowsRandomHex)",
    "PHONE_HASH_SECRET=$(New-WindowsRandomHex)",
    "LOCATION_MASTER_KEY_BASE64=$(New-WindowsRandomBase64)",
    "LOCATION_PRIVACY_SECRET=$(New-WindowsRandomHex)",
    "ADMIN_SESSION_SECRET=$(New-WindowsRandomHex)",
    'AUTH_MODE=local_test',
    'ALLOW_LOCAL_TEST_OTP=true',
    'LOCAL_TEST_OTP=123456',
    'MAP_MODE=global_provider',
    'MAP_STYLE_URL=https://tiles.openfreemap.org/styles/liberty',
    'MAP_API_KEY=',
    'MAP_DEFAULT_LAT=20',
    'MAP_DEFAULT_LNG=0',
    'MAP_DEFAULT_ZOOM=1.5',
    'MAP_MIN_ZOOM=1',
    'MAP_MAX_ZOOM=20',
    'GEOCODING_BASE_URL=https://nominatim.openstreetmap.org/search',
    'REVERSE_GEOCODING_BASE_URL=https://nominatim.openstreetmap.org/reverse',
    'GEOCODING_API_KEY=',
    'MAP_GEOCODER_RETRY_DELAY_MS=1200'
  )
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllLines($EnvFile, $lines, $encoding)
  Set-WindowsPrivateFileAcl $EnvFile
  Write-Output "Created private local-test environment: $EnvFile"
}

function Assert-WindowsHttpOk {
  param([Parameter(Mandatory = $true)][string]$Uri)
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 20
  } catch {
    throw "HTTP probe failed: $Uri"
  }
  if ([int]$response.StatusCode -ne 200) {
    throw "HTTP probe returned $($response.StatusCode): $Uri"
  }
}

function Invoke-WindowsJson {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
    [Parameter(Mandatory = $true)][string]$Uri,
    [hashtable]$Body,
    [hashtable]$Headers
  )
  $parameters = @{
    Method = $Method
    Uri = $Uri
    UseBasicParsing = $true
    TimeoutSec = 20
    ContentType = 'application/json'
  }
  if ($Body) {
    $parameters.Body = $Body | ConvertTo-Json -Depth 8 -Compress
  }
  if ($Headers) { $parameters.Headers = $Headers }
  return Invoke-RestMethod @parameters
}

function Get-WindowsHttpStatus {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
    [Parameter(Mandatory = $true)][string]$Uri,
    [hashtable]$Body,
    [hashtable]$Headers
  )
  $parameters = @{
    Method = $Method
    Uri = $Uri
    UseBasicParsing = $true
    TimeoutSec = 20
  }
  if ($Body) {
    $parameters.ContentType = 'application/json'
    $parameters.Body = $Body | ConvertTo-Json -Depth 8 -Compress
  }
  if ($Headers) { $parameters.Headers = $Headers }
  try {
    $response = Invoke-WebRequest @parameters
    return [int]$response.StatusCode
  } catch {
    $response = $_.Exception.Response
    if ($null -eq $response) { throw }
    return [int]$response.StatusCode
  }
}

function Test-WindowsSocketIoAuthentication {
  param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$AccessToken
  )
  $uri = [Uri](
    $BaseUrl.Replace('http://', 'ws://').Replace('https://', 'wss://') +
    '/socket.io/?EIO=4&transport=websocket'
  )
  $socket = New-Object System.Net.WebSockets.ClientWebSocket
  $cancellation = New-Object System.Threading.CancellationTokenSource
  $cancellation.CancelAfter([TimeSpan]::FromSeconds(12))
  try {
    [void]$socket.ConnectAsync(
      $uri,
      $cancellation.Token
    ).GetAwaiter().GetResult()
    $buffer = New-Object byte[] 8192
    $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $buffer)
    $opened = $socket.ReceiveAsync($segment, $cancellation.Token).GetAwaiter().GetResult()
    $openMessage = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $opened.Count)
    if (-not $openMessage.StartsWith('0')) {
      throw 'Socket.IO did not return an Engine.IO open packet'
    }
    $connectPayload = '40/realtime,' + (@{ token = $AccessToken } | ConvertTo-Json -Compress)
    $connectBytes = [System.Text.Encoding]::UTF8.GetBytes($connectPayload)
    $connectSegment = New-Object System.ArraySegment[byte] -ArgumentList (, $connectBytes)
    [void]$socket.SendAsync(
      $connectSegment,
      [System.Net.WebSockets.WebSocketMessageType]::Text,
      $true,
      $cancellation.Token
    ).GetAwaiter().GetResult()

    $ready = $false
    for ($attempt = 0; $attempt -lt 4 -and -not $ready; $attempt += 1) {
      $result = $socket.ReceiveAsync($segment, $cancellation.Token).GetAwaiter().GetResult()
      $message = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
      if ($message.Contains('"ready"')) { $ready = $true }
      if ($message.Contains('"auth.error"')) {
        throw 'Socket.IO rejected the authenticated session'
      }
    }
    if (-not $ready) { throw 'Socket.IO did not emit its ready event' }
  } finally {
    $cancellation.Dispose()
    if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
      $socket.Dispose()
    } else {
      $socket.Dispose()
    }
  }
}

function Invoke-WindowsNative {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][object[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$FailureMessage
  )
  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}
