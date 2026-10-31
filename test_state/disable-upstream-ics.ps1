$ErrorActionPreference = 'Stop'

$wifiGuid = '{B24D21B6-4511-4CC6-89BB-95B93DFC5AC4}'
$wanGuid = '{9D81C88F-F892-4F50-A0FB-FD6D0E39C82C}'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must run from an elevated PowerShell process.'
}

$manager = New-Object -ComObject HNetCfg.HNetShare
$enum = $manager.EnumEveryConnection
foreach ($netConnection in $enum) {
    $properties = $manager.NetConnectionProps($netConnection)
    if ($properties.Guid -in @($wifiGuid, $wanGuid)) {
        $configuration = $manager.INetSharingConfigurationForINetConnection($netConnection)
        if ($configuration.SharingEnabled) {
            $configuration.DisableSharing()
        }
    }
}
Write-Output 'ICS public/private sharing disabled for Wi-Fi and Ethernet 3.'
