#!/usr/bin/env bash

# Detached coordinator for:
#   1. OpenWrt 25.12.6 x86/64 PVE bypass gateway
#   2. Lenovo Newifi Y1
#   3. Lenovo Newifi Y1s
#
# Nothing is built by this file until "preflight", "run", or "start" is
# explicitly invoked. Use "start" for a detached run.

set -Eeuo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
TASK_HOME="$(cd "$(dirname "$SELF")/.." && pwd)"

LEDE_ROOT="/home/chenmo/Software/openwrt/lede"
X86_ROOT="/home/chenmo/Software/openwrt/openwrt-25.12.6-x86-pve-aio"
Y1_TASK_ROOT="$LEDE_ROOT/.codex-autobuild/y1-y1s"
Y1_SCRIPT="$Y1_TASK_ROOT/scripts/build-y1.sh"
Y1S_SCRIPT="$Y1_TASK_ROOT/scripts/build-y1s.sh"

GLOBAL_LOCK="$LEDE_ROOT/.codex-autobuild/openwrt-build.lock"
Y1_TASK_LOCK="$LEDE_ROOT/.codex-autobuild/y1-y1s.lock"
STATE_ROOT="$TASK_HOME/state/merged"
ARTIFACT_ROOT="$TASK_HOME/artifacts"
X86_STATE="$TASK_HOME/state/x86_64"
X86_ARTIFACT="$ARTIFACT_ROOT/x86_64"
PID_FILE="$STATE_ROOT/build.pid"
STATUS_FILE="$STATE_ROOT/status"
RC_FILE="$STATE_ROOT/rc"
LOG_FILE="$STATE_ROOT/build.log"
TASK_RESULT_FILE="$STATE_ROOT/task-results.tsv"
ARTIFACT_INDEX="$STATE_ROOT/artifacts.tsv"

OPENWRT_TAG="v25.12.6"
OPENWRT_COMMIT="64900e756efa667774214f9c6b17c113222e01f7"
PACKAGES_COMMIT="1846886aabcb0bf29ba5ed041ac16c84fb95ed5f"
LUCI_COMMIT="75a306df84a020c57a631ef5b4c02ace56d93387"
ROUTING_COMMIT="48c808034414a2112cf9d5261a20a320e8d0d170"
TELEPHONY_COMMIT="2618106d5846a4a542fdf5809f0d3ed228ce439b"
HELLOWORLD_COMMIT="f619ed60cf23ed578bbf6ff0688e1f8a97bb4da8"
LEAN_PACKAGES_COMMIT="360859c8a6dcb7dc294dfc68389a8eeec8c8392a"
LEAN_LUCI_COMMIT="0631d439f5d57fab7f077a70e10e3b81809ae5e3"

JOBS="${AUTOBUILD_JOBS:-4}"
DOWNLOAD_JOBS="${AUTOBUILD_DOWNLOAD_JOBS:-8}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-0}"
KEEP_SOURCE_STATE="${KEEP_SOURCE_STATE:-0}"
DDNS_PROVIDER_PACKAGES="${DDNS_PROVIDER_PACKAGES:-}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"
AUTOBUILD_SOCKS_PROXY="${AUTOBUILD_SOCKS_PROXY:-socks5://192.168.100.1:1080}"

if [[ -f "$TASK_HOME/build.env" ]]; then
  # shellcheck disable=SC1091
  source "$TASK_HOME/build.env"
fi

export AUTOBUILD_SOCKS_PROXY
export ALL_PROXY="$AUTOBUILD_SOCKS_PROXY"
export all_proxy="$AUTOBUILD_SOCKS_PROXY"
export HTTP_PROXY="$AUTOBUILD_SOCKS_PROXY"
export HTTPS_PROXY="$AUTOBUILD_SOCKS_PROXY"
export http_proxy="$AUTOBUILD_SOCKS_PROXY"
export https_proxy="$AUTOBUILD_SOCKS_PROXY"
export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,::1}"
export no_proxy="$NO_PROXY"

# Feed updates spawn Git in independent directories. Supplying Git's proxy
# through its environment configuration makes the setting apply there too.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=http.proxy
export GIT_CONFIG_VALUE_0="$AUTOBUILD_SOCKS_PROXY"

mkdir -p "$STATE_ROOT" "$ARTIFACT_ROOT" "$X86_STATE" "$X86_ARTIFACT"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

die() {
  log "ERROR: $*" >&2
  return 1
}

write_status() {
  printf '%s\n' "$*" > "$STATUS_FILE"
}

show_help() {
  cat <<EOF
Usage: $(basename "$SELF") <preflight|start|run|status|help>

  preflight  Validate files, tools, lock and disk space. Does not compile.
  start      Detach with setsid/nohup and run all three tasks.
  run        Run all three tasks in the foreground.
  status     Show PID, phase, log and artifact locations.

Build order:
  x86_64 -> y1 -> y1s

Environment:
  AUTOBUILD_JOBS=4
  AUTOBUILD_DOWNLOAD_JOBS=8
  CONTINUE_ON_ERROR=0
  DDNS_PROVIDER_PACKAGES="ddns-scripts-cloudflare ..."
  EXTRA_PACKAGES="package-name ..."
  KEEP_SOURCE_STATE=0

Optional configuration file:
  $TASK_HOME/build.env
EOF
}

show_status() {
  local running=0
  echo "coordinator: $SELF"
  echo "state: $STATE_ROOT"
  echo "log: $LOG_FILE"
  echo "artifacts: $ARTIFACT_ROOT"
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    running=1
    echo "process: RUNNING pid=$(cat "$PID_FILE")"
  else
    echo "process: NOT_RUNNING"
  fi
  [[ -f "$STATUS_FILE" ]] && echo "status: $(cat "$STATUS_FILE")" || true
  if (( running == 0 )) && [[ -f "$RC_FILE" ]]; then
    echo "rc: $(cat "$RC_FILE")"
  fi
  [[ -f "$TASK_RESULT_FILE" ]] && {
    echo "task results:"
    sed 's/^/  /' "$TASK_RESULT_FILE"
  }
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

check_feed_commit() {
  local feed="$1"
  local expected="$2"
  local actual
  actual="$(git -C "$X86_ROOT/feeds/$feed" rev-parse HEAD)"
  [[ "$actual" == "$expected" ]] ||
    die "feed $feed commit mismatch: expected $expected, got $actual"
}

preflight() {
  log "starting preflight"
  log "network proxy: $AUTOBUILD_SOCKS_PROXY"

  for cmd in git make bash flock sha256sum find awk sed curl python3 qemu-img; do
    need_command "$cmd"
  done

  [[ -d "$LEDE_ROOT" ]] || die "missing LEDE root: $LEDE_ROOT"
  [[ -f "$Y1_SCRIPT" ]] || die "missing Y1 entrypoint: $Y1_SCRIPT"
  [[ -f "$Y1S_SCRIPT" ]] || die "missing Y1s entrypoint: $Y1S_SCRIPT"
  [[ -f "$Y1_TASK_ROOT/configs/y1.previous.config" ]] ||
    die "missing Y1 base config"
  [[ -f "$Y1_TASK_ROOT/configs/y1s.previous.config" ]] ||
    die "missing Y1s base config"
  [[ -f "$Y1_TASK_ROOT/assets/v2ray-core-mipsel.Makefile" ]] ||
    die "missing Y1/Y1s V2Ray Makefile"
  [[ -f "$Y1_TASK_ROOT/assets/luci-app-ssr-plus.Makefile" ]] ||
    die "missing Y1/Y1s SSR Plus Makefile"
  [[ -f "$LEDE_ROOT/feeds/packages/net/vlmcsd/Makefile" ]] ||
    die "missing pinned vlmcsd package source"
  [[ -f "$LEDE_ROOT/feeds/luci/applications/luci-app-vlmcsd/Makefile" ]] ||
    die "missing pinned vlmcsd LuCI source"
  [[ -f "$LEDE_ROOT/feeds/luci/applications/luci-app-zerotier/Makefile" ]] ||
    die "missing pinned ZeroTier LuCI source"

  local free_kb
  free_kb="$(df -Pk "$LEDE_ROOT" | awk 'NR==2 {print $4}')"
  (( free_kb >= 50 * 1024 * 1024 )) ||
    die "need at least 50 GiB free space, found $((free_kb / 1024 / 1024)) GiB"

  if [[ -e "$X86_ROOT" ]]; then
    [[ -d "$X86_ROOT/.git" ]] ||
      die "existing x86 path is not a git checkout: $X86_ROOT"
    local actual
    actual="$(git -C "$X86_ROOT" rev-parse HEAD)"
    [[ "$actual" == "$OPENWRT_COMMIT" ]] ||
      die "x86 source commit mismatch: expected $OPENWRT_COMMIT, got $actual"
  else
    log "x86 source is absent; run mode will clone $OPENWRT_TAG"
  fi

  log "preflight passed"
}

snapshot_shared_source() {
  local backup="$STATE_ROOT/wndr-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup"
  printf '%s\n' "$backup" > "$STATE_ROOT/wndr-backup-path"

  local item
  for item in \
    "$LEDE_ROOT/.config" \
    "$LEDE_ROOT/feeds/helloworld/v2ray-core/Makefile" \
    "$LEDE_ROOT/feeds/helloworld/luci-app-ssr-plus/Makefile"; do
    if [[ -f "$item" ]]; then
      local rel="${item#"$LEDE_ROOT"/}"
      mkdir -p "$backup/$(dirname "$rel")"
      cp -fp "$item" "$backup/$rel"
      printf '%s\n' "$rel" >> "$backup/files.list"
    fi
  done
}

restore_shared_source() {
  local rc=$?
  set +e
  if [[ "$KEEP_SOURCE_STATE" != "1" && -f "$STATE_ROOT/wndr-backup-path" ]]; then
    local backup
    backup="$(cat "$STATE_ROOT/wndr-backup-path")"
    if [[ -d "$backup" && -f "$backup/files.list" ]]; then
      while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        cp -fp "$backup/$rel" "$LEDE_ROOT/$rel"
      done < "$backup/files.list"
      log "restored shared WNDR source files from $backup"
    fi
  fi
  if (( rc == 0 )) && [[ ! -f "$STATUS_FILE" ]]; then
    write_status COMPLETED
  elif (( rc != 0 )); then
    write_status "FAILED rc=$rc"
  fi
  printf '%s\n' "$rc" > "$RC_FILE"
  date -Is > "$STATE_ROOT/finished_at"
  exit "$rc"
}

handle_signal() {
  local signal="$1"
  local code="$2"
  set +e
  write_status "FAILED signal=$signal"
  log "received signal $signal"
  exit "$code"
}

prepare_x86_source() {
  if [[ ! -e "$X86_ROOT" ]]; then
    log "cloning OpenWrt $OPENWRT_TAG"
    git clone --branch "$OPENWRT_TAG" --depth=1 \
      https://github.com/openwrt/openwrt.git "$X86_ROOT"
  fi

  local actual
  actual="$(git -C "$X86_ROOT" rev-parse HEAD)"
  [[ "$actual" == "$OPENWRT_COMMIT" ]] ||
    die "x86 source commit mismatch after clone/check: $actual"

  cat > "$X86_ROOT/feeds.conf.default" <<EOF
src-git packages https://github.com/openwrt/packages.git^$PACKAGES_COMMIT
src-git luci https://github.com/openwrt/luci.git^$LUCI_COMMIT
src-git routing https://github.com/openwrt/routing.git^$ROUTING_COMMIT
src-git telephony https://github.com/openwrt/telephony.git^$TELEPHONY_COMMIT
src-git helloworld https://github.com/fw876/helloworld.git^$HELLOWORLD_COMMIT
EOF

  cd "$X86_ROOT"
  update_feeds_with_retry
  install_compat_sources
  ./scripts/feeds update -i
  ./scripts/feeds install -a

  check_feed_commit packages "$PACKAGES_COMMIT"
  check_feed_commit luci "$LUCI_COMMIT"
  check_feed_commit routing "$ROUTING_COMMIT"
  check_feed_commit telephony "$TELEPHONY_COMMIT"
  check_feed_commit helloworld "$HELLOWORLD_COMMIT"

  grep -q '^PKG_VERSION:=190$' \
    "$X86_ROOT/feeds/helloworld/luci-app-ssr-plus/Makefile" ||
    die "SSR Plus package is not pinned to v190"
  grep -q '^PKG_VERSION:=5.47.0$' \
    "$X86_ROOT/feeds/helloworld/v2ray-core/Makefile" ||
    die "V2Ray package is not pinned to 5.47.0"
  grep -q 'alterId' \
    "$X86_ROOT/feeds/helloworld/luci-app-ssr-plus/root/usr/share/shadowsocksr/gen_config.lua" ||
    die "SSR Plus generator lacks alterId support"
  grep -q 'result.alter_id' \
    "$X86_ROOT/feeds/helloworld/luci-app-ssr-plus/root/usr/share/shadowsocksr/subscribe.lua" ||
    die "SSR Plus subscription parser lacks alter_id support"
}

install_compat_sources() {
  local packages_head luci_head vlmcsd_makefile
  packages_head="$(git -C "$LEDE_ROOT/feeds/packages" rev-parse HEAD)"
  luci_head="$(git -C "$LEDE_ROOT/feeds/luci" rev-parse HEAD)"
  [[ "$packages_head" == "$LEAN_PACKAGES_COMMIT" ]] ||
    die "Lean packages feed moved; expected $LEAN_PACKAGES_COMMIT, got $packages_head"
  [[ "$luci_head" == "$LEAN_LUCI_COMMIT" ]] ||
    die "Lean LuCI feed moved; expected $LEAN_LUCI_COMMIT, got $luci_head"

  mkdir -p \
    "$X86_ROOT/feeds/packages/net/vlmcsd" \
    "$X86_ROOT/feeds/luci/applications/luci-app-vlmcsd" \
    "$X86_ROOT/feeds/luci/applications/luci-app-zerotier"
  cp -a "$LEDE_ROOT/feeds/packages/net/vlmcsd/." \
    "$X86_ROOT/feeds/packages/net/vlmcsd/"
  cp -a "$LEDE_ROOT/feeds/luci/applications/luci-app-vlmcsd/." \
    "$X86_ROOT/feeds/luci/applications/luci-app-vlmcsd/"
  cp -a "$LEDE_ROOT/feeds/luci/applications/luci-app-zerotier/." \
    "$X86_ROOT/feeds/luci/applications/luci-app-zerotier/"

  # OpenWrt 25.12 uses apk-tools, which rejects the legacy package version
  # "svn1113". Keep the upstream source tag while exposing a numeric package
  # version compatible with apk.
  vlmcsd_makefile="$X86_ROOT/feeds/packages/net/vlmcsd/Makefile"
  sed -i \
    -e 's/^PKG_VERSION:=svn1113$/PKG_VERSION:=1113\nPKG_SOURCE_VERSION:=svn1113/' \
    -e 's#^PKG_SOURCE:=.*#PKG_SOURCE:=$(PKG_NAME)-$(PKG_SOURCE_VERSION).tar.gz#' \
    -e 's#^PKG_SOURCE_URL:=.*#PKG_SOURCE_URL:=https://codeload.github.com/Wind4/vlmcsd/tar.gz/$(PKG_SOURCE_VERSION)?#' \
    -e '/^PKG_HASH:=/a PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_SOURCE_VERSION)' \
    "$vlmcsd_makefile"
  grep -q '^PKG_VERSION:=1113$' "$vlmcsd_makefile" ||
    die "failed to normalize vlmcsd package version"
  grep -q '^PKG_SOURCE_VERSION:=svn1113$' "$vlmcsd_makefile" ||
    die "failed to preserve vlmcsd upstream source version"
}

update_feeds_with_retry() {
  local attempt feed stamp
  for attempt in 1 2 3 4; do
    log "updating feeds: attempt $attempt/4"
    if ./scripts/feeds update -a; then
      return 0
    fi

    log "feed update attempt $attempt failed; preserving incomplete temporary feeds"
    stamp="$(date +%Y%m%d-%H%M%S)"
    for feed in packages luci routing telephony helloworld; do
      if [[ -d "$X86_ROOT/feeds/$feed" ]] &&
        ! git -C "$X86_ROOT/feeds/$feed" rev-parse --verify HEAD >/dev/null 2>&1; then
        mv "$X86_ROOT/feeds/$feed" \
          "$X86_ROOT/feeds/$feed.incomplete-$stamp-$attempt"
      fi
      if [[ -d "$X86_ROOT/feeds/$feed.tmp" ]]; then
        mv "$X86_ROOT/feeds/$feed.tmp" \
          "$X86_ROOT/feeds/$feed.tmp.failed-$stamp-$attempt"
      fi
    done
    sleep 5
  done
  die "feed update failed after 4 attempts"
}

write_x86_config() {
  local config="$1"
  cat > "$config" <<'EOF'
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_ROOTFS_PARTSIZE=8192
CONFIG_GRUB_EFI_IMAGES=y
CONFIG_QCOW2_IMAGES=y
CONFIG_TARGET_IMAGES_GZIP=y

CONFIG_PACKAGE_firewall4=y
CONFIG_PACKAGE_nftables=y
CONFIG_PACKAGE_kmod-nft-nat=y
CONFIG_PACKAGE_kmod-nft-socket=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
CONFIG_PACKAGE_dnsmasq-full=y
# CONFIG_PACKAGE_dnsmasq is not set
CONFIG_PACKAGE_dnsmasq_full_dhcp=y
CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y
CONFIG_PACKAGE_dnsmasq_full_nftset=y

CONFIG_PACKAGE_luci-app-ssr-plus=y
CONFIG_PACKAGE_luci-app-ssr-plus_Nftables_Transparent_Proxy=y
# CONFIG_PACKAGE_luci-app-ssr-plus_Iptables_Transparent_Proxy is not set
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray is not set
CONFIG_PACKAGE_v2ray-core=y
# CONFIG_PACKAGE_v2ray-plugin is not set

CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Client=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Client is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Rust_Client is not set
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_NONE_Server=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Rust_Server is not set
CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client=y
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Server is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_V2ray_Plugin is not set
# CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Trojan is not set

CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_luci-proto-wireguard=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_zerotier=y
CONFIG_PACKAGE_luci-app-zerotier=y

CONFIG_PACKAGE_ddns-scripts=y
CONFIG_PACKAGE_ddns-scripts-services=y
CONFIG_PACKAGE_luci-app-ddns=y

CONFIG_PACKAGE_openlist=y
CONFIG_PACKAGE_luci-app-openlist=y

CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-app-wol=y
CONFIG_PACKAGE_etherwake=y

CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-lua-runtime=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y
CONFIG_PACKAGE_luci-i18n-ddns-zh-cn=y
CONFIG_PACKAGE_luci-i18n-openlist-zh-cn=y
CONFIG_PACKAGE_luci-i18n-ssr-plus-zh-cn=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y
CONFIG_PACKAGE_luci-i18n-wol-zh-cn=y
CONFIG_PACKAGE_luci-i18n-zerotier-zh-cn=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_tcpdump-mini=y
EOF

  local pkg
  for pkg in $DDNS_PROVIDER_PACKAGES $EXTRA_PACKAGES; do
    [[ -n "$pkg" ]] || continue
    printf 'CONFIG_PACKAGE_%s=y\n' "$pkg" >> "$config"
  done
}

require_config() {
  local symbol="$1"
  grep -qx "CONFIG_${symbol}=y" "$X86_ROOT/.config" ||
    die "required config is not selected: $symbol"
}

forbid_config() {
  local symbol="$1"
  if grep -qx "CONFIG_${symbol}=y" "$X86_ROOT/.config"; then
    die "forbidden config is selected: $symbol"
  fi
}

validate_x86_config() {
  require_config TARGET_x86_64_DEVICE_generic
  require_config PACKAGE_luci-app-ssr-plus
  require_config PACKAGE_luci-app-ssr-plus_Nftables_Transparent_Proxy
  require_config PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray
  require_config PACKAGE_v2ray-core
  require_config PACKAGE_dnsmasq-full
  require_config PACKAGE_dnsmasq_full_nftset
  require_config PACKAGE_kmod-nft-tproxy
  require_config PACKAGE_kmod-wireguard
  require_config PACKAGE_wireguard-tools
  require_config PACKAGE_luci-proto-wireguard
  require_config PACKAGE_zerotier
  require_config PACKAGE_luci-app-zerotier
  require_config PACKAGE_ddns-scripts
  require_config PACKAGE_ddns-scripts-services
  require_config PACKAGE_luci-app-ddns
  require_config PACKAGE_openlist
  require_config PACKAGE_luci-app-openlist
  require_config PACKAGE_vlmcsd
  require_config PACKAGE_luci-app-vlmcsd
  require_config PACKAGE_luci-app-wol
  require_config PACKAGE_etherwake
  require_config PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client

  forbid_config PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY
  forbid_config PACKAGE_luci-app-ssr-plus_INCLUDE_Xray
  forbid_config PACKAGE_luci-app-ssr-plus_Iptables_Transparent_Proxy
  forbid_config PACKAGE_v2ray-plugin
  forbid_config PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Libev_Server
  forbid_config PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_Rust_Server
  forbid_config PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Server

  local pkg
  for pkg in $DDNS_PROVIDER_PACKAGES $EXTRA_PACKAGES; do
    [[ -n "$pkg" ]] || continue
    require_config "PACKAGE_$pkg"
  done
}

collect_x86_artifacts() {
  local target_dir="$X86_ROOT/bin/targets/x86/64"
  local qcow2 img_gz manifest raw_img generated_qcow2
  qcow2="$(find "$target_dir" -maxdepth 1 -type f \
    -name '*-generic-squashfs-combined-efi.qcow2' | sort | tail -1)"
  img_gz="$(find "$target_dir" -maxdepth 1 -type f \
    -name '*-generic-squashfs-combined-efi.img.gz' | sort | tail -1)"
  manifest="$(find "$target_dir" -maxdepth 1 -type f \
    -name '*.manifest' | sort | tail -1)"

  [[ -n "$img_gz" && -f "$img_gz" ]] || die "x86 img.gz image not found"
  [[ -n "$manifest" && -f "$manifest" ]] || die "x86 manifest not found"

  if [[ -z "$qcow2" || ! -f "$qcow2" ]]; then
    raw_img="$X86_STATE/openwrt-x86-64-generic-squashfs-combined-efi.img"
    generated_qcow2="$X86_STATE/openwrt-x86-64-generic-squashfs-combined-efi.qcow2"
    log "qcow2 was not emitted by the target; converting $img_gz"
    gzip -dc "$img_gz" > "$raw_img"
    qemu-img convert -f raw -O qcow2 -c "$raw_img" "$generated_qcow2"
    qemu-img check "$generated_qcow2"
    rm -f "$raw_img"
    qcow2="$generated_qcow2"
  fi
  [[ -n "$qcow2" && -f "$qcow2" ]] || die "x86 qcow2 image not found"

  grep -q '^v2ray-core ' "$manifest" || die "manifest lacks v2ray-core"
  grep -q '^luci-app-ssr-plus ' "$manifest" ||
    die "manifest lacks luci-app-ssr-plus"
  if grep -q '^v2ray-plugin ' "$manifest"; then
    die "manifest unexpectedly contains v2ray-plugin"
  fi

  cp -fp "$qcow2" "$img_gz" "$manifest" "$X86_ARTIFACT"/
  (
    cd "$X86_ARTIFACT"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 |
      sort -z |
      xargs -0 sha256sum > SHA256SUMS
  )

  printf '%s\t%s\n' x86_64 "$X86_ARTIFACT" >> "$ARTIFACT_INDEX"
}

run_x86_task() (
  set -euo pipefail
  write_status "RUNNING x86_64"
  log "task x86_64: preparing source"
  prepare_x86_source

  cd "$X86_ROOT"
  write_x86_config "$X86_ROOT/.config"
  make defconfig
  write_x86_config "$X86_ROOT/.config"
  make defconfig
  validate_x86_config

  export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
  export GOSUMDB="${GOSUMDB:-sum.golang.google.cn}"
  export CFLAGS="${CFLAGS:-} -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types"
  export CXXFLAGS="${CXXFLAGS:-} -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types"

  log "task x86_64: building host tools"
  make tools/install -j"$JOBS" V=s

  log "task x86_64: building target toolchain"
  make toolchain/install -j"$JOBS" V=s

  log "task x86_64: downloading"
  make download -j"$DOWNLOAD_JOBS"

  # Package-specific compile targets can pull package/kernel/linux without
  # first completing target/linux. The full build enforces the dependency
  # graph (kernel -> modules -> packages -> image).
  log "task x86_64: full dependency-aware image build"
  make -j"$JOBS" TARGET_DEVICES=generic V=s
  collect_x86_artifacts
  printf '%s\t%s\n' x86_64 0 >> "$TASK_RESULT_FILE"
  log "task x86_64: completed"
)

verify_y_artifacts() {
  local id="$1"
  local artifact_dir="$Y1_TASK_ROOT/artifacts/$id"
  local expected="$2"
  local pattern
  for pattern in $expected; do
    compgen -G "$artifact_dir/$pattern" >/dev/null ||
      die "$id artifact missing: $pattern"
  done
  (
    cd "$artifact_dir"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 |
      sort -z |
      xargs -0 sha256sum > SHA256SUMS
  )
  printf '%s\t%s\n' "$id" "$artifact_dir" >> "$ARTIFACT_INDEX"
}

run_y1_task() (
  set -euo pipefail
  write_status "RUNNING y1"
  log "task y1: foreground run"
  bash "$Y1_SCRIPT" run
  verify_y_artifacts y1 \
    'openwrt-ramips-mt7620-lenovo_newifi-y1-initramfs-kernel.bin openwrt-ramips-mt7620-lenovo_newifi-y1-squashfs-sysupgrade.bin openwrt-ramips-mt7620-lenovo_newifi-y1.manifest'
  printf '%s\t%s\n' y1 0 >> "$TASK_RESULT_FILE"
  log "task y1: completed"
)

run_y1s_task() (
  set -euo pipefail
  write_status "RUNNING y1s"
  log "task y1s: foreground run"
  bash "$Y1S_SCRIPT" run
  verify_y_artifacts y1s \
    'openwrt-ramips-mt7620-lenovo_newifi-y1s-initramfs-kernel.bin openwrt-ramips-mt7620-lenovo_newifi-y1s-squashfs-sysupgrade.bin openwrt-ramips-mt7620-lenovo_newifi-y1s.manifest'
  printf '%s\t%s\n' y1s 0 >> "$TASK_RESULT_FILE"
  log "task y1s: completed"
)

run_all() {
  exec 9>"$GLOBAL_LOCK"
  log "waiting for global OpenWrt build lock"
  flock 9
  log "global OpenWrt build lock acquired"

  exec 8>"$Y1_TASK_LOCK"
  log "waiting for Y1/Y1s source lock before starting x86_64"
  flock 8
  log "Y1/Y1s source lock acquired"

  mkdir -p "$STATE_ROOT"
  : > "$TASK_RESULT_FILE"
  : > "$ARTIFACT_INDEX"
  date -Is > "$STATE_ROOT/started_at"
  snapshot_shared_source
  trap restore_shared_source EXIT
  trap 'handle_signal INT 130' INT
  trap 'handle_signal TERM 143' TERM

  local rc=0
  set +e
  run_x86_task
  rc=$?
  set -e

  # Y1/Y1s scripts acquire this lock themselves. Release it before invoking
  # their foreground commands to avoid a nested-lock deadlock.
  flock -u 8
  exec 8>&-

  if (( rc == 0 )); then
    set +e
    run_y1_task
    rc=$?
    set -e
  fi
  if (( rc == 0 )); then
    set +e
    run_y1s_task
    rc=$?
    set -e
  fi

  if (( rc == 0 )); then
    write_status COMPLETED
    log "merged build completed"
  else
    write_status "FAILED rc=$rc"
    log "merged build failed with rc=$rc"
    if [[ "$CONTINUE_ON_ERROR" == "1" ]]; then
      log "CONTINUE_ON_ERROR is enabled, but dependencies make further tasks unsafe"
    fi
  fi
  return "$rc"
}

start_detached() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "already running: pid=$(cat "$PID_FILE")"
    show_status
    return 0
  fi

  preflight
  mkdir -p "$STATE_ROOT"
  : > "$LOG_FILE"
  : > "$TASK_RESULT_FILE"
  : > "$ARTIFACT_INDEX"
  write_status QUEUED

  setsid nohup bash "$SELF" run >>"$LOG_FILE" 2>&1 </dev/null &
  printf '%s\n' "$!" > "$PID_FILE"
  echo "started detached merged build: pid=$!"
  show_status
}

main() {
  case "${1:-help}" in
    preflight)
      preflight
      ;;
    start)
      start_detached
      ;;
    run)
      preflight
      run_all
      ;;
    status)
      show_status
      ;;
    help|-h|--help)
      show_help
      ;;
    *)
      show_help
      return 2
      ;;
  esac
}

main "$@"
