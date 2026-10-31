param(
    [string]$EnvFile = '.env.local',
    [switch]$Override
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($EnvFile)) {
    $EnvFile = Join-Path $root $EnvFile
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
    $fallback = Join-Path $root '.env'
    if (Test-Path -LiteralPath $fallback) {
        $EnvFile = $fallback
    }
    else {
        throw "Environment file not found. Copy .env.example to .env.local first."
    }
}

$loaded = @()
foreach ($line in Get-Content -LiteralPath $EnvFile) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    $parts = $trimmed -split '=', 2
    if ($parts.Count -ne 2) { continue }
    $name = $parts[0].Trim()
    $value = $parts[1].Trim().Trim('"').Trim("'")
    if (-not $Override -and [Environment]::GetEnvironmentVariable($name)) { continue }
    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    $loaded += $name
}

Write-Output ("Loaded environment variables: " + ($loaded -join ', '))
