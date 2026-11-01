# R66S build handoff

Snapshot time: 2026-11-01 17:42 +08:00

## Current state

The R66S build is still running in a detached process on `xps13`.
Shutting down the computer that submitted the build does not stop it.

| Item | Value |
| --- | --- |
| Remote host | `xps13` |
| Source tree | `/home/chenmo/Software/openwrt/openwrt-25.12.6-r66s` |
| Branch | `r66s-build` |
| Upstream baseline | OpenWrt `v25.12.6`, commit `64900e756efa667774214f9c6b17c113222e01f7` |
| Build PID | `303058` (`flock`; child `make` was PID `303069`) |
| Build log | `/home/chenmo/Software/openwrt/logs/r66s-build-20261101-111938.log` |
| Target | `rockchip/armv8` |
| Device | `lunzn_fastrhino-r66s` |
| Kernel | Linux 6.12.112 |
| Configured rootfs size | 4096 MiB |
| `.config` SHA-256 | `ec9e965626909da82abd2d848a94e3e4abecf047e428f912852eca712925ab3d` |
| Last checked | 2026-11-01 17:42 +08:00 |
| Last observed elapsed time | 6 hours 22 minutes |
| Last observed images | None yet; only build metadata exists |

The remote source tree intentionally has one applied working-tree change:

```text
M target/linux/rockchip/image/armv8.mk
```

That change and its full reproducer are stored in
`patches/0001-rockchip-r66s-use-r8125-driver.patch`.

## Do not disrupt the remote build

While PID `303058` is alive:

- Do not start another full build against the same source tree.
- Do not delete `build_dir`, `staging_dir`, or `dl`.
- Do not force-kill the build unless the log proves the process is stuck and
  recovery has been discussed with the user.
- Keep checking the persistent log rather than relying on the initiating SSH
  session.

## Continue on another computer

1. Clone or update the repository:

   ```powershell
   git clone git@github.com:HatsusenoAlpha/openwrt_for_my_old_router.git
   cd openwrt_for_my_old_router
   ```

2. Configure an SSH host alias named `xps13` for the same remote account and
   key. Do not store credentials in this repository.

3. Run the one-shot status check:

   ```powershell
   .\scripts\monitor-r66s-build.ps1
   ```

4. To monitor continuously at the requested 15-minute interval:

   ```powershell
   .\scripts\monitor-r66s-build.ps1 -Watch -IntervalMinutes 15
   ```

5. When the log contains `build rc=0`, fetch and validate the artifacts:

   ```powershell
   .\scripts\monitor-r66s-build.ps1 -Download
   ```

The script writes deliverables under `artifacts/r66s`, which is ignored by Git.

## Manual monitoring commands

```sh
ps -p 303058,303069 -o pid=,ppid=,stat=,%cpu=,%mem=,etime=,cmd=
tail -n 80 /home/chenmo/Software/openwrt/logs/r66s-build-20261101-111938.log
grep -nEi 'error:|failed to build|make(\[[0-9]+\])?: \*\*\*|build rc=' \
  /home/chenmo/Software/openwrt/logs/r66s-build-20261101-111938.log
find /home/chenmo/Software/openwrt/openwrt-25.12.6-r66s/bin/targets/rockchip/armv8 \
  -maxdepth 1 -type f -iname '*fastrhino*r66s*' \
  -printf '%f %s bytes\n'
```

Success is defined by the explicit final log line `build rc=0` together with a
complete R66S image and checksum file. A live process alone is not success.

## Expected image and post-build checks

The expected artifact is the R66S combined disk image, normally named like:

```text
openwrt-25.12.6-rockchip-armv8-lunzn_fastrhino-r66s-squashfs-sysupgrade.img.gz
```

Before flashing:

- Verify the SHA-256 against the remote checksum file.
- Run a gzip integrity test.
- Confirm the image partition layout has a 64 MiB kernel partition and a
  4096 MiB software/rootfs partition.
- Confirm the R66S DTB is present as a real file.
- Confirm `kmod-r8125`, `luci-app-ssr-plus`, OpenClash, and Xray are installed.
- Do not apply the WNDR3800 factory/sysupgrade flashing procedure to R66S.
  R66S uses its RK3568 TF-card/U-Boot disk-image workflow.

## Suggested prompt for the receiving agent

```text
Read AGENTS.md, README.md, and build-spec/R66S_BUILD_HANDOFF.md. Continue
monitoring the detached R66S build on xps13 every 15 minutes. Do not restart or
clean the build while PID 303058 is alive. When the log contains build rc=0,
validate and retrieve the R66S image into artifacts/r66s, report its size,
SHA-256, and flashing method, and do not commit firmware binaries.
```
