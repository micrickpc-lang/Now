#requires -Version 5.1

[CmdletBinding()]
param(
  [string]$EnvFile,
  [string]$LanIPv4
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WindowsLocalTestCommon.ps1')

$environmentFile = Get-WindowsLocalTestEnvironmentPath $EnvFile
Initialize-WindowsLocalTestEnvironment $environmentFile $LanIPv4
$environment = Read-PcEnvironment $environmentFile
$lan = ConvertTo-PcUsableIPv4 $environment['LAN_IP']
$docker = Assert-PcDockerEngine
$compose = Get-WindowsLocalTestComposeArguments $environmentFile

Push-Location (Get-WindowsRepositoryRoot)
try {
  Invoke-WindowsNative $docker ($compose + @('config', '--quiet')) `
    'The local-test Compose configuration is invalid'
  Invoke-WindowsNative $docker ($compose + @('up', '-d', '--build', '--wait', '--wait-timeout', '300')) `
    'The local-test server did not become healthy'
  Assert-WindowsHttpOk "http://$lan`:8080/health"
  Assert-WindowsHttpOk "http://$lan`:8080/ready"
  & (Join-Path $PSScriptRoot 'smoke-test.ps1') -EnvFile $environmentFile
  if ($LASTEXITCODE -ne 0) { throw 'The local-test smoke test failed' }
} finally {
  Pop-Location
}

Write-Output ''
Write-Output 'Server ready:'
Write-Output "API: http://$lan`:8080/api/v1"
Write-Output "WebSocket: ws://$lan`:8080"
Write-Output "Swagger: http://$lan`:8080/docs"
Write-Output 'Health: OK'
Write-Output 'Auth mode: local_test'
Write-Output "Test OTP: $($environment['LOCAL_TEST_OTP'])"
Write-Output ''
Write-Output 'Flutter command:'
Write-Output 'flutter run ^'
Write-Output '  --dart-define=APP_ENV=development ^'
Write-Output "  --dart-define=API_BASE_URL=http://$lan`:8080/api/v1 ^"
Write-Output "  --dart-define=WS_BASE_URL=ws://$lan`:8080 ^"
Write-Output "  --dart-define=MAP_STYLE_URL=$($environment['MAP_STYLE_URL']) ^"
Write-Output "  --dart-define=FIRST_PARTY_DOMAINS=$lan"
Write-Output ''
Write-Output 'Windows Firewall: allow inbound TCP 8080 only for the Private profile; do not add a Public-profile rule automatically.'
