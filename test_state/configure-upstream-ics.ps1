$ErrorActionPreference = 'Stop'

$wifiGuid = '{B24D21B6-4511-4CC6-89BB-95B93DFC5AC4}'
$wanGuid = '{9D81C88F-F892-4F50-A0FB-FD6D0E39C82C}'
$stateDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resultPath = Join-Path $stateDir 'upstream_ics_result.json'
$beforePath = Join-Path $stateDir 'upstream_ics_before.json'
$errorPath = Join-Path $stateDir 'upstream_ics_error.txt'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must run from an elevated PowerShell process.'
}

$manager = New-Object -ComObject HNetCfg.HNetShare
$enum = $manager.EnumEveryConnection
if ($null -eq $enum) {
    throw 'HNetCfg.HNetShare returned no connection enumerator; run in STA PowerShell.'
}

$connections = @()
$index = 0
foreach ($netConnection in $enum) {
    $properties = $manager.NetConnectionProps($netConnection)
    $configuration = $manager.INetSharingConfigurationForINetConnection($netConnection)
    $connections += [pscustomobject]@{
        Index = $index
        Name = $properties.Name
        Guid = $properties.Guid
        Connection = $netConnection
        Configuration = $configuration
        SharingEnabled = [bool]$configuration.SharingEnabled
        SharingConnectionType = [int]$configuration.SharingConnectionType
    }
    $index++
}

$before = $connections | Select-Object Name, Guid, SharingEnabled, SharingConnectionType
$before | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $beforePath -Encoding utf8

$wifi = $connections | Where-Object Guid -eq $wifiGuid | Select-Object -First 1
$wan = $connections | Where-Object Guid -eq $wanGuid | Select-Object -First 1
if (-not $wifi) { throw 'Wi-Fi ICS connection was not found.' }
if (-not $wan) { throw 'Ethernet 3 ICS connection was not found.' }

try {
    if ($wifi.Configuration.SharingEnabled) {
        $wifi.Configuration.DisableSharing()
    }
    if ($wan.Configuration.SharingEnabled) {
        $wan.Configuration.DisableSharing()
    }

    # 0 = public/shared Internet connection, 1 = private/home connection.
    $wifi.Configuration.EnableSharing(0)
    $wan.Configuration.EnableSharing(1)

    $service = Get-Service SharedAccess
    if ($service.Status -ne 'Running') {
        Start-Service SharedAccess
    }
    Start-Sleep -Seconds 5

    $checkManager = New-Object -ComObject HNetCfg.HNetShare
    $checkEnum = $checkManager.EnumEveryConnection
    $after = @()
    foreach ($netConnection in $checkEnum) {
        $properties = $checkManager.NetConnectionProps($netConnection)
        $configuration = $checkManager.INetSharingConfigurationForINetConnection($netConnection)
        $after += [pscustomobject]@{
            Name = $properties.Name
            Guid = $properties.Guid
            SharingEnabled = [bool]$configuration.SharingEnabled
            SharingConnectionType = [int]$configuration.SharingConnectionType
        }
    }

    $wifiAfter = $after | Where-Object Guid -eq $wifiGuid | Select-Object -First 1
    $wanAfter = $after | Where-Object Guid -eq $wanGuid | Select-Object -First 1
    if (-not $wifiAfter.SharingEnabled -or $wifiAfter.SharingConnectionType -ne 0) {
        throw 'Wi-Fi did not become the ICS public connection.'
    }
    if (-not $wanAfter.SharingEnabled -or $wanAfter.SharingConnectionType -ne 1) {
        throw 'Ethernet 3 did not become the ICS private connection.'
    }

    $ip = Get-NetIPAddress -InterfaceAlias 'Ethernet 3' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object AddressState -ne 'Tentative' |
        Select-Object -First 1

    [pscustomobject]@{
        Success = $true
        PublicInterface = 'Wi-Fi'
        PublicGuid = $wifiGuid
        PrivateInterface = 'Ethernet 3'
        PrivateGuid = $wanGuid
        SharedSubnet = '192.168.137.0/24'
        SharedGateway = if ($ip) { $ip.IPAddress } else { 'assigned by ICS when the link becomes active' }
        DhcpEnabled = $true
        DnsEnabled = $true
        SharedAccessStatus = (Get-Service SharedAccess).Status
        CompletedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding utf8
}
catch {
    $originalError = $_.Exception.ToString()
    try {
        if ($wifi.Configuration.SharingEnabled) {
            $wifi.Configuration.DisableSharing()
        }
        if ($wan.Configuration.SharingEnabled) {
            $wan.Configuration.DisableSharing()
        }
    }
    catch {
        $originalError += "`nRollback error: " + $_.Exception.ToString()
    }
    $originalError | Set-Content -LiteralPath $errorPath -Encoding utf8
    [pscustomobject]@{
        Success = $false
        Error = $_.Exception.Message
        CompletedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding utf8
    throw $originalError
}
