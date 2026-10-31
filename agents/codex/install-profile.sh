#!/usr/bin/env sh
set -eu

codex_home="${CODEX_HOME:-$HOME/.codex}"
source_file="$(dirname "$0")/profile-deepseek.config.toml.example"
target_file="$codex_home/profile-deepseek.config.toml"

mkdir -p "$codex_home"
if [ -e "$target_file" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "Target profile already exists: $target_file" >&2
  echo "Set FORCE=1 to overwrite." >&2
  exit 1
fi

cp "$source_file" "$target_file"
echo "Installed Codex profile template: $target_file"
echo "Edit the model and Responses-compatible base_url before use."
