$ErrorActionPreference = 'Stop'

$wifiGuid = '{B24D21B6-4511-4CC6-89BB-95B93DFC5AC4}'
$testWanGuid = '{9D81C88F-F892-4F50-A0FB-FD6D0E39C82C}'
$stateDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$resultPath = Join-Path $stateDir 'wired_adapter_restore_result.json'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must run from an elevated PowerShell process.'
}

$manager = New-Object -ComObject HNetCfg.HNetShare
$enum = $manager.EnumEveryConnection
foreach ($netConnection in $enum) {
    $properties = $manager.NetConnectionProps($netConnection)
    if ($properties.Guid -in @($wifiGuid, $testWanGuid)) {
        $configuration = $manager.INetSharingConfigurationForINetConnection($netConnection)
        if ($configuration.SharingEnabled) {
            $configuration.DisableSharing()
        }
    }
}

# Restore the pre-test automatic addressing of Ethernet 3.
$e3 = Get-NetAdapter -Name 'Ethernet 3'
Set-NetIPInterface -InterfaceAlias 'Ethernet 3' -AddressFamily IPv4 -Dhcp Enabled
Set-DnsClientServerAddress -InterfaceAlias 'Ethernet 3' -ResetServerAddresses
Set-NetIPInterface -InterfaceAlias 'Ethernet 3' -AddressFamily IPv6 -Dhcp Enabled

Start-Sleep -Seconds 4

$e3Ip = Get-NetIPAddress -InterfaceAlias 'Ethernet 3' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Select-Object IPAddress, PrefixLength, AddressState
$lanIp = Get-NetIPAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Select-Object IPAddress, PrefixLength, AddressState
$ics = Get-CimInstance -Namespace root\Microsoft\HomeNet -Class HNet_ConnectionProperties |
    Where-Object { $_.Connection.Guid -in @($wifiGuid, $testWanGuid) } |
    Select-Object @{n='Guid';e={$_.Connection.Guid}}, IsIcsPublic, IsIcsPrivate

[pscustomobject]@{
    Success = $true
    Ethernet = @{
        Role = 'WNDR3800 LAN'
        Addressing = 'unchanged DHCP'
        Addresses = @($lanIp)
    }
    Ethernet3 = @{
        Role = 'Former temporary WAN upstream'
        Addressing = 'restored to DHCP'
        Addresses = @($e3Ip)
    }
    IcsState = @($ics)
    Note = 'The physical Ethernet 3 cable remains connected until it is unplugged.'
    RestoredAt = (Get-Date).ToString('o')
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding utf8
