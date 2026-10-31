# Agent Instructions

This file applies to the whole repository and to both Codex and `dsh`.

## First Steps

1. Read this file, `README.md`, and the plan relevant to the requested target.
2. Inspect `git status` before editing.
3. Keep firmware binaries, Flash backups, disk images, logs, credentials, and
   local `.env` files out of Git.
4. Do not run a full firmware build, flash a router, change host networking, or
   enable/disable sharing services without explicit user approval.

## Build Workspace

- Remote build host alias: `xps13`
- Remote OpenWrt source: `/home/chenmo/Software/openwrt/lede`
- Local plans are portable; the OpenWrt source tree is not included.
- Use long-running remote builds through a detached process and persistent log.
- Reserve enough image-space headroom; never use `--force` or `-F` blindly.

## Device Plans

- WNDR3800: `compile_plan.md`, `agent_execution_plan.md`,
  `WNDR3800_backup_comparison.md`
- x86/64: `x86_64/docs/merged-openwrt-build.md`
- Y1/Y1s: `y1_y1s/compile_plan.md`
- Multi-task merge manifest: `y1_y1s/merge_compile_tasks.json`

## WNDR3800 Critical Facts

- LAN default: `192.168.10.1/24`
- WAN NIC: `eth1`
- Switch: Realtek RTL8366S/SR
- Required image package: `kmod-switch-rtl8366s`
- `v2ray-plugin` is not a VMess client; VMess requires `v2ray-core`.
- HP 1020 printing files must be preserved.

## Y1 / Y1s Critical Facts

- Y1 LAN: `192.168.6.1/24`
- Y1s LAN: `192.168.4.1/24`
- Architecture: MIPS32 little-endian.
- Use the mips32le V2Ray package, not the WNDR3800 mips32 big-endian package.
- Long builds use the scripts in `y1_y1s/scripts/`; they detach with
  `setsid`/`nohup` and serialize through `flock`.

## Secrets

- Never write API keys or router passwords into tracked files.
- Local environment values belong in `.env.local` or the operating-system
  environment.
- Provider configuration for Codex belongs in the user-level Codex profile,
  not project-local `.codex/config.toml`.

## Validation

- Run `scripts/validate-workspace.ps1` on Windows or
  `scripts/validate-workspace.sh` on Unix-like hosts.
- Verify manifest membership and final image size before flashing.
- Preserve unrelated user changes and never reset the worktree.
