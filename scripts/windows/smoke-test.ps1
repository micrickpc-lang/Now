#requires -Version 5.1

[CmdletBinding()]
param(
  [string]$EnvFile,
  [string]$Phone
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WindowsLocalTestCommon.ps1')

$environmentFile = Get-WindowsLocalTestEnvironmentPath $EnvFile
if (-not (Test-Path -LiteralPath $environmentFile -PathType Leaf)) {
  throw "Local-test environment was not found: $environmentFile"
}
$environment = Read-PcEnvironment $environmentFile
$lan = ConvertTo-PcUsableIPv4 $environment['LAN_IP']
$server = "http://$lan`:8080"
$api = "$server/api/v1"

Write-Output 'Checking ingress, API, OpenAPI and global map provider...'
Assert-WindowsHttpOk "$server/health"
Assert-WindowsHttpOk "$server/ready"
Assert-WindowsHttpOk "$server/docs"
Assert-WindowsHttpOk "$api/maps/style.json"

$testPhone = if ($Phone) { $Phone } else {
  '+1555' + (Get-Random -Minimum 1000000 -Maximum 9999999)
}
$auth = & (Join-Path $PSScriptRoot 'test-auth.ps1') `
  -EnvFile $environmentFile -Phone $testPhone -KeepSession
if ($null -eq $auth -or [string]::IsNullOrWhiteSpace($auth.AccessToken)) {
  throw 'Authentication smoke test did not return a test session'
}
$authorization = @{ Authorization = "Bearer $($auth.AccessToken)" }
$search = Invoke-WindowsJson GET "$api/maps/search?q=New%20York" $null $authorization
if (@($search).Count -lt 1) { throw 'Global geocoding search returned no places' }
# Public Nominatim permits one request per second. Production deployments use
# a credentialed provider through the same API proxy and do not need this wait.
Start-Sleep -Seconds 2
$reverse = Invoke-WindowsJson GET "$api/maps/reverse?lat=40.7484&lng=-73.9857" $null $authorization
if ($null -eq $reverse) { throw 'Global reverse geocoding returned no result' }
$logout = Invoke-WindowsJson POST "$api/auth/logout" @{ refreshToken = $auth.RefreshToken } $authorization
if ($logout.success -ne $true) { throw 'Smoke-test logout was not acknowledged' }
$revokedStatus = Get-WindowsHttpStatus POST "$api/auth/refresh" @{ refreshToken = $auth.RefreshToken }
if ($revokedStatus -ne 401) { throw "Smoke-test logout left refresh token active: HTTP $revokedStatus" }
Write-Output 'Full Windows LAN smoke test passed.'
