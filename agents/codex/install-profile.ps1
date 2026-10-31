param(
    [string]$CodexHome = (Join-Path $HOME '.codex'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'profile-deepseek.config.toml.example'
$target = Join-Path $CodexHome 'profile-deepseek.config.toml'

New-Item -ItemType Directory -Force -Path $CodexHome | Out-Null
if ((Test-Path $target) -and -not $Force) {
    throw "Target profile already exists: $target. Use -Force to overwrite."
}

Copy-Item -LiteralPath $source -Destination $target -Force:$Force
Write-Output "Installed Codex profile template: $target"
Write-Output 'Edit the model and Responses-compatible base_url before use.'
