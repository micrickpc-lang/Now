#requires -Version 5.1

[CmdletBinding()]
param(
  [string]$EnvFile,
  [string]$Phone = '+79991234567',
  [switch]$SkipWebSocket,
  [switch]$KeepSession
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WindowsLocalTestCommon.ps1')

$environmentFile = Get-WindowsLocalTestEnvironmentPath $EnvFile
if (-not (Test-Path -LiteralPath $environmentFile -PathType Leaf)) {
  throw "Local-test environment was not found: $environmentFile"
}
$environment = Read-PcEnvironment $environmentFile
if ($environment['AUTH_MODE'] -ne 'local_test') {
  throw 'test-auth.ps1 requires AUTH_MODE=local_test'
}
if ($environment['ALLOW_LOCAL_TEST_OTP'] -ne 'true') {
  throw 'test-auth.ps1 requires ALLOW_LOCAL_TEST_OTP=true'
}
$otp = $environment['LOCAL_TEST_OTP']
if ($otp -notmatch '^\d{6}$') {
  throw 'LOCAL_TEST_OTP must be a six-digit code'
}
$lan = ConvertTo-PcUsableIPv4 $environment['LAN_IP']
$server = "http://$lan`:8080"
$api = "$server/api/v1"

Write-Host 'Checking local_test OTP flow...'
$request = Invoke-WindowsJson POST "$api/auth/otp/request" @{ phone = $Phone }
if ($request.accepted -ne $true) { throw 'OTP request was not accepted' }
$resend = Invoke-WindowsJson POST "$api/auth/otp/resend" @{ phone = $Phone }
if ($resend.accepted -ne $true) { throw 'OTP resend was not accepted' }

$verified = Invoke-WindowsJson POST "$api/auth/otp/verify" @{
  phone = $Phone
  code = $otp
  birthDate = '1990-01-01'
  displayName = 'LAN Smoke Test'
  installationId = [guid]::NewGuid().ToString()
  platform = 'android'
  deviceLabel = 'Windows LAN smoke test'
}
if ([string]::IsNullOrWhiteSpace($verified.accessToken) -or
    [string]::IsNullOrWhiteSpace($verified.refreshToken)) {
  throw 'OTP verification did not return both tokens'
}

$access = [string]$verified.accessToken
$refresh = [string]$verified.refreshToken
$authorization = @{ Authorization = "Bearer $access" }
$session = Invoke-WindowsJson GET "$api/auth/session" $null $authorization
if ([string]::IsNullOrWhiteSpace($session.id)) {
  throw 'Authenticated session endpoint returned no session id'
}

$rotated = Invoke-WindowsJson POST "$api/auth/refresh" @{ refreshToken = $refresh }
if ([string]::IsNullOrWhiteSpace($rotated.accessToken) -or
    [string]::IsNullOrWhiteSpace($rotated.refreshToken) -or
    $rotated.refreshToken -eq $refresh) {
  throw 'Refresh rotation did not return a new token pair'
}
$oldRefreshStatus = Get-WindowsHttpStatus POST "$api/auth/refresh" @{ refreshToken = $refresh }
if ($oldRefreshStatus -ne 401) {
  throw "The prior refresh token was expected to be rejected with 401, got $oldRefreshStatus"
}

$freshAccess = [string]$rotated.accessToken
$freshRefresh = [string]$rotated.refreshToken
$freshAuthorization = @{ Authorization = "Bearer $freshAccess" }
[void](Invoke-WindowsJson GET "$api/auth/session" $null $freshAuthorization)
if (-not $SkipWebSocket) {
  Test-WindowsSocketIoAuthentication $server $freshAccess
}

if ($KeepSession) {
  return [pscustomobject]@{
    AccessToken = $freshAccess
    RefreshToken = $freshRefresh
  }
}

$logout = Invoke-WindowsJson POST "$api/auth/logout" @{ refreshToken = $freshRefresh } $freshAuthorization
if ($logout.success -ne $true) { throw 'Logout was not acknowledged' }
$revokedRefreshStatus = Get-WindowsHttpStatus POST "$api/auth/refresh" @{ refreshToken = $freshRefresh }
if ($revokedRefreshStatus -ne 401) {
  throw "Logout did not revoke the refresh token; got HTTP $revokedRefreshStatus"
}

Write-Host 'Auth smoke test passed: OTP, session, WebSocket, refresh rotation and logout.'
