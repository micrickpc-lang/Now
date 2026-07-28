# Shared helpers for the native Windows PC/LAN scripts.

Set-StrictMode -Version Latest

$script:PcRepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:PcStagingCompose = Join-Path $script:PcRepositoryRoot 'docker-compose.staging.yml'
$script:PcWindowsCompose = Join-Path $script:PcRepositoryRoot 'docker-compose.windows-lan.yml'

function Get-PcRepositoryRoot {
  return $script:PcRepositoryRoot
}

function Resolve-PcPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $script:PcRepositoryRoot $Path))
}

function Read-PcEnvironment {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $resolved = Resolve-PcPath $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "PC environment file not found: $resolved"
  }

  $values = @{}
  $lineNumber = 0
  foreach ($rawLine in [System.IO.File]::ReadAllLines($resolved)) {
    $lineNumber += 1
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith('#')) {
      continue
    }

    $separator = $line.IndexOf('=')
    if ($separator -le 0) {
      throw "Malformed PC environment entry at line $lineNumber"
    }
    $name = $line.Substring(0, $separator).Trim()
    if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
      throw "Invalid PC environment key at line $lineNumber"
    }
    if ($values.ContainsKey($name)) {
      throw "Duplicate PC environment key at line $lineNumber"
    }
    $values[$name] = $line.Substring($separator + 1).Trim()
  }

  return $values
}

function ConvertTo-PcUsableIPv4 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $address = $null
  if (
    -not [System.Net.IPAddress]::TryParse($Value.Trim(), [ref]$address) -or
    $address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork
  ) {
    throw 'The LAN address must be an IPv4 address'
  }

  $octets = $address.GetAddressBytes()
  if (
    $octets[0] -eq 0 -or
    $octets[0] -eq 127 -or
    ($octets[0] -eq 169 -and $octets[1] -eq 254) -or
    $octets[0] -ge 224
  ) {
    throw 'The LAN address must be a usable, non-loopback IPv4 address'
  }

  return $address.ToString()
}

function Test-PcPrivateIPv4 {
  param(
    [Parameter(Mandatory = $true)]
    [System.Net.IPAddress]$Address
  )

  $octets = $Address.GetAddressBytes()
  return (
    $octets[0] -eq 10 -or
    ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) -or
    ($octets[0] -eq 192 -and $octets[1] -eq 168)
  )
}

function Get-PcLanIPv4 {
  # A connected UDP socket asks Windows which source address backs the default
  # IPv4 route. Connect does not transmit a datagram. A VPN may own that route,
  # so prefer the result only when it belongs to a physical LAN adapter.
  $routeCandidate = $null
  $socket = $null
  try {
    $socket = New-Object System.Net.Sockets.Socket(
      [System.Net.Sockets.AddressFamily]::InterNetwork,
      [System.Net.Sockets.SocketType]::Dgram,
      [System.Net.Sockets.ProtocolType]::Udp
    )
    $socket.Connect('1.1.1.1', 53)
    $candidate = $socket.LocalEndPoint.Address.ToString()
    $routeCandidate = ConvertTo-PcUsableIPv4 $candidate
  } catch {
    $routeCandidate = $null
  } finally {
    if ($null -ne $socket) {
      $socket.Dispose()
    }
  }

  $physicalTypes = @(
    'Ethernet',
    'Ethernet3Megabit',
    'FastEthernetT',
    'FastEthernetFx',
    'GigabitEthernet',
    'Wireless80211'
  )
  $virtualPattern =
    '(?i)(docker|hamachi|hyper-v|tailscale|tap|tunnel|tun\b|virtual|' +
    'virtualbox|vmware|vpn|vethernet|wireguard|wsl|zerotier)'
  $candidates = @()
  foreach (
    $adapter in
      [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
  ) {
    if (
      $adapter.OperationalStatus -ne
        [System.Net.NetworkInformation.OperationalStatus]::Up -or
      $adapter.NetworkInterfaceType -in @(
        [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback,
        [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel
      )
    ) {
      continue
    }

    try {
      $properties = $adapter.GetIPProperties()
      $adapterLabel = "$($adapter.Name) $($adapter.Description)"
      $isLikelyPhysical = (
        $adapter.NetworkInterfaceType.ToString() -in $physicalTypes -and
        $adapterLabel -notmatch $virtualPattern
      )
      $hasGateway = @(
        $properties.GatewayAddresses |
          Where-Object {
            $_.Address.AddressFamily -eq
              [System.Net.Sockets.AddressFamily]::InterNetwork -and
            $_.Address.ToString() -ne '0.0.0.0'
          }
      ).Count -gt 0
      foreach ($unicast in $properties.UnicastAddresses) {
        if (
          $unicast.Address.AddressFamily -ne
            [System.Net.Sockets.AddressFamily]::InterNetwork
        ) {
          continue
        }
        try {
          $usable = ConvertTo-PcUsableIPv4 $unicast.Address.ToString()
          $candidates += [pscustomobject]@{
            Address = $usable
            HasGateway = [int]$hasGateway
            IsPrivate = [int](Test-PcPrivateIPv4 $unicast.Address)
            IsLikelyPhysical = [int]$isLikelyPhysical
            Speed = [uint64]$adapter.Speed
          }
        } catch {
          continue
        }
      }
    } catch {
      continue
    }
  }

  if ($routeCandidate) {
    $routedPhysical = @(
      $candidates |
        Where-Object {
          $_.Address -eq $routeCandidate -and $_.IsLikelyPhysical -eq 1
        }
    )
    if ($routedPhysical.Count -gt 0) {
      return $routeCandidate
    }
  }

  $preferred = @(
    $candidates | Where-Object { $_.IsLikelyPhysical -eq 1 }
  )
  if ($preferred.Count -eq 0) {
    $preferred = $candidates
  }
  if ($preferred.Count -eq 0 -and $routeCandidate) {
    return $routeCandidate
  }
  if ($preferred.Count -eq 0) {
    throw 'No usable LAN IPv4 address was detected; pass -LanIPv4 explicitly'
  }
  $ordered = @(
    $preferred |
      Sort-Object -Property @(
        @{ Expression = 'HasGateway'; Descending = $true },
        @{ Expression = 'IsPrivate'; Descending = $true },
        @{ Expression = 'Speed'; Descending = $true },
        @{ Expression = 'Address'; Descending = $false }
      )
  )
  return $ordered[0].Address
}

function Get-PcEnvironmentLanIPv4 {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Environment
  )

  $configuredLan = $Environment['LAN_IP']
  $lanIp = if ($configuredLan) {
    ConvertTo-PcUsableIPv4 $configuredLan
  } else {
    # Backward compatibility for environments created before PUBLIC_IP meant
    # the externally routable address.
    ConvertTo-PcUsableIPv4 $Environment['PUBLIC_IP']
  }

  $bindAddress = $Environment['STAGING_BIND_ADDRESS']
  if (-not $bindAddress) {
    throw 'PC environment is missing STAGING_BIND_ADDRESS'
  }
  if ($bindAddress -ne '0.0.0.0') {
    $validatedBindAddress = ConvertTo-PcUsableIPv4 $bindAddress
    if ($validatedBindAddress -ne $lanIp) {
      throw 'STAGING_BIND_ADDRESS must be 0.0.0.0 or match LAN_IP'
    }
  }
  return $lanIp
}

function Get-PcPublicIPv4 {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Environment
  )

  if (-not $Environment.ContainsKey('PUBLIC_IP') -or -not $Environment['PUBLIC_IP']) {
    throw 'PC environment is missing PUBLIC_IP'
  }
  return ConvertTo-PcUsableIPv4 $Environment['PUBLIC_IP']
}

function Assert-PcDockerEngine {
  $dockerPaths = @(
    Get-Command docker -CommandType Application -ErrorAction SilentlyContinue |
      ForEach-Object { $_.Source } |
      Where-Object { $_ } |
      Select-Object -Unique
  )
  if ($dockerPaths.Count -eq 0) {
    throw 'Docker Desktop with Compose v2 is required'
  }

  $docker = [string]$dockerPaths[0]
  & $docker info --format '{{.ServerVersion}}' *> $null
  if ($LASTEXITCODE -ne 0) {
    throw 'Docker Engine is not running; start Docker Desktop and retry'
  }
  & $docker compose version *> $null
  if ($LASTEXITCODE -ne 0) {
    throw 'Docker Compose v2 is required'
  }
  return $docker
}

function Get-PcComposeArguments {
  param(
    [Parameter(Mandatory = $true)]
    [string]$EnvFile
  )

  return @(
    'compose',
    '--env-file', (Resolve-PcPath $EnvFile),
    '-f', $script:PcStagingCompose,
    '-f', $script:PcWindowsCompose
  )
}

function Invoke-PcNativeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $true)]
    [object[]]$ArgumentList,

    [Parameter(Mandatory = $true)]
    [string]$FailureMessage
  )

  & $FilePath @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw $FailureMessage
  }
}

function Test-PcNominatimMarker {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Docker,

    [Parameter(Mandatory = $true)]
    [object[]]$ComposeArguments,

    [Parameter(Mandatory = $true)]
    [ValidateSet('PG_VERSION', 'import-finished')]
    [string]$Marker
  )

  $arguments = $ComposeArguments + @(
    'run', '--rm', '--no-deps',
    '--entrypoint', 'test',
    'nominatim',
    '-f', "/var/lib/postgresql/16/main/$Marker"
  )
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    # A missing marker is the expected state before the first import. Docker
    # exits with 1 for `test -f`; use that exit code instead of treating its
    # stderr (including Compose's progress messages) as a terminating error.
    $ErrorActionPreference = 'Continue'
    & $Docker @arguments *> $null
    return $LASTEXITCODE -eq 0
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
}
