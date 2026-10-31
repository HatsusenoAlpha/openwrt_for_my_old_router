$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

$requiredFiles = @(
    'README.md',
    'AGENTS.md',
    '.env.example',
    'compile_plan.md',
    'agent_execution_plan.md',
    'y1_y1s/compile_plan.md',
    'y1_y1s/merge_compile_tasks.json',
    'x86_64/docs/merged-openwrt-build.md',
    'agents/codex/profile-deepseek.config.toml.example',
    'agents/dsh/cordis.patch.yml.example'
)

foreach ($relative in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative))) {
        $failures.Add("Missing required file: $relative")
    }
}

$requiredCommands = @('git', 'ssh', 'codex', 'dsh')
foreach ($command in $requiredCommands) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        $failures.Add("Missing command: $command")
    }
}

Push-Location $root
try {
    $remote = git remote get-url origin 2>$null
    if ($remote -ne 'git@github.com:HatsusenoAlpha/openwrt_for_my_old_router.git') {
        $failures.Add("Unexpected or missing origin: $remote")
    }

    foreach ($ignored in @('artifacts', 'backup', 'r66s')) {
        if (Test-Path -LiteralPath $ignored) {
            git check-ignore -q "$ignored/" 2>$null
            if ($LASTEXITCODE -ne 0) {
                $failures.Add("Directory is not ignored by Git: $ignored")
            }
        }
    }

    $trackedFirmware = git ls-files |
        Where-Object { $_ -match '\.(bin|img|qcow2|trx|chk)$' }
    if ($trackedFirmware) {
        $failures.Add("Firmware files are tracked in Git: $($trackedFirmware -join ', ')")
    }

    $trackedSecrets = git ls-files |
        Where-Object { $_ -match '(^|/)\.env(\.|$)' -and $_ -ne '.env.example' }
    if ($trackedSecrets) {
        $failures.Add("Secret environment files are tracked: $($trackedSecrets -join ', ')")
    }
}
finally {
    Pop-Location
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'Workspace validation passed.'
Write-Output "Required files: $($requiredFiles.Count)"
Write-Output "Required commands: $($requiredCommands -join ', ')"
