param(
    [string]$RemoteHost = 'xps13',
    [int]$BuildPid = 303058,
    [string]$RemoteSource = '/home/chenmo/Software/openwrt/openwrt-25.12.6-r66s',
    [string]$RemoteLog = '/home/chenmo/Software/openwrt/logs/r66s-build-20261101-111938.log',
    [string]$OutputDirectory = 'artifacts/r66s',
    [switch]$Download,
    [switch]$Watch,
    [ValidateRange(1, 1440)]
    [int]$IntervalMinutes = 15
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$scp = (Get-Command scp.exe -ErrorAction Stop).Source
$imageDir = "$RemoteSource/bin/targets/rockchip/armv8"
$outputPath = Join-Path $root $OutputDirectory

function Get-BuildStatus {
    $remoteScript = @"
set -u
printf 'TIME=%s\n' "`$(date '+%Y-%m-%d %H:%M:%S %z')"
if kill -0 $BuildPid 2>/dev/null; then
    printf 'PID_ALIVE=1\n'
    ps -p $BuildPid -o pid=,ppid=,stat=,%cpu=,%mem=,etime=,cmd=
else
    printf 'PID_ALIVE=0\n'
fi
printf 'LOG_TIME='
stat -c '%y' '$RemoteLog' 2>/dev/null || printf 'missing\n'
printf 'LOG_TAIL_BEGIN\n'
tail -n 30 '$RemoteLog' 2>/dev/null || true
printf 'LOG_TAIL_END\n'
printf 'ERRORS_BEGIN\n'
grep -nEi '(^|[^a-z])(error:|failed to build|make(\[[0-9]+\])?: \*\*\*|build rc=)' '$RemoteLog' 2>/dev/null | tail -20 || true
printf 'ERRORS_END\n'
printf 'ARTIFACTS_BEGIN\n'
find '$imageDir' -maxdepth 1 -type f \
    \( -iname '*fastrhino*r66s*' -o -name 'sha256sums' \
       -o -name 'config.buildinfo' -o -name 'version.buildinfo' \
       -o -name 'feeds.buildinfo' \) \
    -printf '%f\t%s\n' 2>/dev/null | sort || true
printf 'ARTIFACTS_END\n'
"@

    $lines = & $ssh -o BatchMode=yes -o ConnectTimeout=15 $RemoteHost $remoteScript
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to query $RemoteHost over SSH (exit $LASTEXITCODE)."
    }

    $text = $lines -join "`n"
    $pidAlive = $text -match '(?m)^PID_ALIVE=1$'
    $buildOk = $text -match '(?m)build rc=0'
    $hasError = $text -match '(?m)(^|[^a-z])(error:|failed to build|make(\[[0-9]+\])?: \*\*\*)'
    $artifactLines = @()
    if ($text -match '(?s)ARTIFACTS_BEGIN\n(.*?)\nARTIFACTS_END') {
        $artifactLines = $Matches[1] -split "`n" | Where-Object { $_ }
    }

    [pscustomobject]@{
        Text = $text
        PidAlive = $pidAlive
        BuildOk = $buildOk
        HasError = $hasError
        Artifacts = $artifactLines
    }
}

function Save-Artifacts {
    New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
    $files = @($status.Artifacts | ForEach-Object {
        ($_ -split "`t", 2)[0]
    } | Where-Object {
        $_ -match 'fastrhino-r66s' -or $_ -eq 'sha256sums' -or
        $_ -in @('config.buildinfo', 'version.buildinfo', 'feeds.buildinfo')
    })
    if (-not $files) {
        throw 'No downloadable R66S artifacts were found.'
    }

    foreach ($file in $files) {
        & $scp -o BatchMode=yes "${RemoteHost}:${imageDir}/${file}" $outputPath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to download $file (exit $LASTEXITCODE)."
        }
    }

    Get-ChildItem -LiteralPath $outputPath -File |
        Sort-Object Name |
        Select-Object Name, Length, LastWriteTime
    Get-FileHash -Algorithm SHA256 -LiteralPath (
        Join-Path $outputPath $files[0]
    ) | Select-Object Algorithm, Hash, Path
}

do {
    $status = Get-BuildStatus
    Write-Output $status.Text

    if ($status.BuildOk) {
        Write-Output 'BUILD_COMPLETE=1'
        if ($Download) {
            Save-Artifacts
        }
        exit 0
    }

    if (-not $status.PidAlive) {
        if ($status.HasError) {
            Write-Error 'The build process ended with an error marker in the log.'
        }
        else {
            Write-Error 'The build process is no longer alive, but build rc=0 was not found.'
        }
        exit 1
    }

    Write-Output "BUILD_RUNNING=1 NEXT_CHECK_MINUTES=$IntervalMinutes"
    if (-not $Watch) {
        exit 2
    }

    Start-Sleep -Seconds ($IntervalMinutes * 60)
    $status = $null
} while ($Watch)
