#requires -Version 5.1

<#
.SYNOPSIS
Creates a private environment file for the Windows PC/LAN staging stack.
#>

[CmdletBinding()]
param(
  [Alias('LanIp')]
  [string]$LanIPv4,

  [Alias('PublicIp')]
  [string]$PublicIPv4,

  [Parameter(Mandatory = $true)]
  [string]$PhoneAllowlist,

  [string]$OutputPath,

  [string]$DataRoot = 'D:\Projects\seychas-runtime',

  [ValidateSet('staging', 'smsru')]
  [string]$SmsProvider = 'staging',

  [string]$SmsRuFrom = '',

  [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PcCommon.ps1')

function New-PcHexSecret {
  $bytes = New-Object byte[] 32
  $script:PcRandom.GetBytes($bytes)
  return [System.BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
}

function New-PcBase64Secret {
  $bytes = New-Object byte[] 32
  $script:PcRandom.GetBytes($bytes)
  return [System.Convert]::ToBase64String($bytes)
}

function New-PcSixDigitOtp {
  # Rejection sampling avoids modulo bias while retaining the full 000000-
  # 999999 range.
  do {
    $bytes = New-Object byte[] 4
    $script:PcRandom.GetBytes($bytes)
    $value = [System.BitConverter]::ToUInt32($bytes, 0)
  } while ([uint64]$value -ge [uint64]4294000000)
  return '{0:D6}' -f ($value % 1000000)
}

function Set-PcPrivateFileAcl {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  if ($null -eq $identity.User) {
    throw 'Unable to identify the current Windows user for the private ACL'
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

if (-not $LanIPv4) {
  $LanIPv4 = Get-PcLanIPv4
  Write-Output "Detected LAN IPv4: $LanIPv4"
} else {
  $LanIPv4 = ConvertTo-PcUsableIPv4 $LanIPv4
}

if (-not $PublicIPv4) {
  $PublicIPv4 = $LanIPv4
} else {
  $PublicIPv4 = ConvertTo-PcUsableIPv4 $PublicIPv4
}

$phones = @(
  $PhoneAllowlist.Split(',') |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ }
)
if (
  $phones.Count -eq 0 -or
  @($phones | Where-Object { $_ -notmatch '^\+\d{8,15}$' }).Count -ne 0
) {
  throw 'PhoneAllowlist must contain comma-separated normalized E.164 numbers'
}
$normalizedPhones = $phones -join ','

if ($SmsRuFrom.Length -gt 32 -or $SmsRuFrom -match '[\r\n]') {
  throw 'SmsRuFrom must be a single-line value of at most 32 characters'
}

$resolvedOutput = if ($OutputPath) {
  Resolve-PcPath $OutputPath
} else {
  Join-Path (Get-PcRepositoryRoot) '.env.pc'
}
$resolvedDataRoot = [System.IO.Path]::GetFullPath($DataRoot)
$dataRootVolume = [System.IO.Path]::GetPathRoot($resolvedDataRoot)
if (
  -not $dataRootVolume -or
  $resolvedDataRoot.TrimEnd('\') -eq $dataRootVolume.TrimEnd('\') -or
  $resolvedDataRoot -match '[\r\n]'
) {
  throw 'DataRoot must be a safe absolute directory below a drive root'
}

if (Test-Path -LiteralPath $resolvedOutput) {
  if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
    throw 'OutputPath must identify a file'
  }
  if (-not $Force) {
    throw 'The PC environment already exists; pass -Force to replace it'
  }
}

$parent = Split-Path -Parent $resolvedOutput
if (-not $parent) {
  throw 'OutputPath must have a parent directory'
}
[void][System.IO.Directory]::CreateDirectory($parent)
[void][System.IO.Directory]::CreateDirectory($resolvedDataRoot)

$smsRuApiId = ''
if ($SmsProvider -eq 'smsru') {
  $secureApiId = Read-Host -Prompt 'SMS.RU API ID (input hidden)' -AsSecureString
  $secretPointer = [System.IntPtr]::Zero
  try {
    $secretPointer =
      [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiId)
    $smsRuApiId =
      [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
  } finally {
    if ($secretPointer -ne [System.IntPtr]::Zero) {
      [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
    }
    $secureApiId.Dispose()
  }
  if ($smsRuApiId.Length -lt 16 -or $smsRuApiId -match '\s') {
    $smsRuApiId = $null
    throw 'The SMS.RU API ID must contain at least 16 non-whitespace characters'
  }
}

$script:PcRandom = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$temporary = Join-Path $parent (
  '.{0}.{1}.new' -f
    [System.IO.Path]::GetFileName($resolvedOutput),
    [System.IO.Path]::GetRandomFileName()
)
try {
  $lines = @(
    "PUBLIC_IP=$PublicIPv4",
    "LAN_IP=$LanIPv4",
    'STAGING_BIND_ADDRESS=0.0.0.0',
    "NOW_DATA_ROOT=$resolvedDataRoot",
    'IMAGE_TAG=pc',
    'POSTGRES_DB=seychas',
    'POSTGRES_USER=seychas',
    "POSTGRES_PASSWORD=$(New-PcHexSecret)",
    "NOMINATIM_PASSWORD=$(New-PcHexSecret)",
    "JWT_SECRET=$(New-PcHexSecret)",
    "TOKEN_HASH_SECRET=$(New-PcHexSecret)",
    "PHONE_HASH_SECRET=$(New-PcHexSecret)",
    "LOCATION_MASTER_KEY_BASE64=$(New-PcBase64Secret)",
    "LOCATION_PRIVACY_SECRET=$(New-PcHexSecret)",
    "ADMIN_SESSION_SECRET=$(New-PcHexSecret)",
    "SMS_PROVIDER=$SmsProvider",
    "SMS_RU_API_ID=$smsRuApiId",
    "SMS_RU_FROM=$SmsRuFrom",
    'SMS_RU_TIMEOUT_MS=5000',
    "STAGING_TEST_PHONE_ALLOWLIST=$normalizedPhones",
    "STAGING_TEST_OTP=$(New-PcSixDigitOtp)"
  )

  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($temporary, '', $encoding)
  Set-PcPrivateFileAcl $temporary
  [System.IO.File]::WriteAllLines($temporary, $lines, $encoding)
  Move-Item -LiteralPath $temporary -Destination $resolvedOutput -Force
  Set-PcPrivateFileAcl $resolvedOutput

  $acl = [System.IO.File]::GetAccessControl($resolvedOutput)
  if (-not $acl.AreAccessRulesProtected) {
    throw 'The PC environment ACL still inherits permissions'
  }
} finally {
  $lines = $null
  $smsRuApiId = $null
  if ($null -ne $script:PcRandom) {
    $script:PcRandom.Dispose()
  }
  if (Test-Path -LiteralPath $temporary -PathType Leaf) {
    Remove-Item -LiteralPath $temporary -Force
  }
}

Write-Output "Created private PC environment at $resolvedOutput; secret values were not printed."
