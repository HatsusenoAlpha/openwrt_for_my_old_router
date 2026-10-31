#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
failures=0

for relative in \
  README.md \
  AGENTS.md \
  .env.example \
  compile_plan.md \
  agent_execution_plan.md \
  y1_y1s/compile_plan.md \
  y1_y1s/merge_compile_tasks.json \
  x86_64/docs/merged-openwrt-build.md \
  agents/codex/profile-deepseek.config.toml.example \
  agents/dsh/cordis.patch.yml.example
do
  if [ ! -e "$root/$relative" ]; then
    echo "Missing required file: $relative" >&2
    failures=$((failures + 1))
  fi
done

for command in git ssh codex dsh; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing command: $command" >&2
    failures=$((failures + 1))
  fi
done

cd "$root"
remote=$(git remote get-url origin 2>/dev/null || true)
if [ "$remote" != "git@github.com:HatsusenoAlpha/openwrt_for_my_old_router.git" ]; then
  echo "Unexpected or missing origin: $remote" >&2
  failures=$((failures + 1))
fi

for ignored in artifacts backup r66s; do
  if [ -e "$ignored" ] && ! git check-ignore -q "$ignored/"; then
    echo "Directory is not ignored by Git: $ignored" >&2
    failures=$((failures + 1))
  fi
done

tracked_firmware=$(git ls-files | grep -E '\.(bin|img|qcow2|trx|chk)$' || true)
if [ -n "$tracked_firmware" ]; then
  echo "Firmware files are tracked in Git:" >&2
  printf '%s\n' "$tracked_firmware" >&2
  failures=$((failures + 1))
fi

tracked_env=$(git ls-files | grep -E '(^|/)\.env(\.|$)' | grep -v '^\.env\.example$' || true)
if [ -n "$tracked_env" ]; then
  echo "Secret environment files are tracked:" >&2
  printf '%s\n' "$tracked_env" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi
echo 'Workspace validation passed.'
