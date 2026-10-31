#!/usr/bin/env bash

# Shared launcher and build implementation for Y1/Y1s.
# It is sourced by build-y1.sh and build-y1s.sh.

set -Eeuo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR="$(cd "$COMMON_DIR/.." && pwd)"
ROOT="$(cd "$TASK_DIR/../.." && pwd)"
STATE_DIR="$TASK_DIR/state/$DEVICE"
ARTIFACT_DIR="$TASK_DIR/artifacts/$DEVICE"
PID_FILE="$STATE_DIR/build.pid"
STATUS_FILE="$STATE_DIR/status"
LOG_FILE="$STATE_DIR/build.log"
LOCK_FILE="$ROOT/.codex-autobuild/y1-y1s.lock"

mkdir -p "$STATE_DIR" "$ARTIFACT_DIR"

AUTOBUILD_SOCKS_PROXY="${AUTOBUILD_SOCKS_PROXY:-socks5://192.168.100.1:1080}"
export AUTOBUILD_SOCKS_PROXY
export ALL_PROXY="$AUTOBUILD_SOCKS_PROXY"
export all_proxy="$AUTOBUILD_SOCKS_PROXY"
export HTTP_PROXY="$AUTOBUILD_SOCKS_PROXY"
export HTTPS_PROXY="$AUTOBUILD_SOCKS_PROXY"
export http_proxy="$AUTOBUILD_SOCKS_PROXY"
export https_proxy="$AUTOBUILD_SOCKS_PROXY"
export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,::1}"
export no_proxy="$NO_PROXY"
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=http.proxy
export GIT_CONFIG_VALUE_0="$AUTOBUILD_SOCKS_PROXY"

verify_file_hash() {
  local file="$1"
  local expected="$2"
  [[ -f "$file" ]] &&
    printf '%s  %s\n' "$expected" "$file" | sha256sum -c - >/dev/null 2>&1
}

verify_host_commands() {
  local command_name
  for command_name in bash git make curl flock sha256sum gzip tar python3 stat; do
    command -v "$command_name" >/dev/null 2>&1 ||
      { echo "Missing build command: $command_name" >&2; return 1; }
  done
}

download_with_retry() {
  local url="$1"
  local destination="$2"
  local expected="$3"
  local label="$4"
  local attempt part stamp

  if verify_file_hash "$destination" "$expected"; then
    echo "$label: existing cache is valid"
    return 0
  fi

  part="$destination.part"
  for attempt in 1 2 3 4 5; do
    echo "$label: download attempt $attempt/5 through $AUTOBUILD_SOCKS_PROXY"
    if curl --proxy "$AUTOBUILD_SOCKS_PROXY" \
      -fL --retry 5 --retry-all-errors --retry-delay 3 \
      --connect-timeout 15 --speed-limit 1024 --speed-time 120 \
      --continue-at - -o "$part" "$url" &&
      verify_file_hash "$part" "$expected"; then
      mv -f "$part" "$destination"
      return 0
    fi

    stamp="$(date +%Y%m%d-%H%M%S)"
    if [[ -f "$part" ]]; then
      mv "$part" "$part.failed-$stamp-$attempt"
    fi
    if [[ -f "$destination" ]]; then
      mv "$destination" "$destination.failed-$stamp-$attempt"
    fi
    sleep 5
  done

  echo "$label: download failed after 5 attempts" >&2
  return 1
}

set_key() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp "$STATE_DIR/config.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    {
      if (index($0, key "=") == 1 ||
          $0 == "# " key " is not set") {
        if (!found) {
          if (value == "n")
            print "# " key " is not set"
          else
            print key "=" value
          found = 1
        }
        next
      }
      print
    }
    END {
      if (!found) {
        if (value == "n")
          print "# " key " is not set"
        else
          print key "=" value
      }
    }
  ' "$ROOT/.config" > "$tmp"
  mv "$tmp" "$ROOT/.config"
}

apply_requested_config() {
  set_key CONFIG_TARGET_SQUASHFS_BLOCK_SIZE 1024
  set_key CONFIG_TARGET_DEFAULT_LAN_IP_FROM_PREINIT y
  set_key CONFIG_TARGET_PREINIT_IP "\"$LAN_IP\""
  set_key CONFIG_TARGET_PREINIT_NETMASK '"255.255.255.0"'
  set_key CONFIG_TARGET_PREINIT_BROADCAST "\"$LAN_BROADCAST\""

  set_key CONFIG_PACKAGE_luci n
  set_key CONFIG_PACKAGE_luci-light y
  set_key CONFIG_PACKAGE_luci-app-package-manager y
  set_key CONFIG_PACKAGE_luci-app-uhttpd n

  set_key CONFIG_PACKAGE_dnsmasq n
  set_key CONFIG_PACKAGE_dnsmasq-full y
  set_key CONFIG_PACKAGE_dnsmasq_full_dhcp y
  set_key CONFIG_PACKAGE_dnsmasq_full_dhcpv6 y
  set_key CONFIG_PACKAGE_dnsmasq_full_ipset y

  set_key CONFIG_PACKAGE_procd-ujail y
  set_key CONFIG_PACKAGE_procd-seccomp y
  set_key CONFIG_PACKAGE_wget-ssl y
  set_key CONFIG_PACKAGE_xz y
  set_key CONFIG_PACKAGE_xz-utils y
  set_key CONFIG_PACKAGE_jq y

  set_key CONFIG_PACKAGE_luci-app-ssr-plus y
  set_key CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray y
  set_key CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_NONE_V2RAY n
  set_key CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Xray n
  set_key CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_SagerNet_Core n
  set_key CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Trojan n
  set_key CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_Shadowsocks_V2ray_Plugin n
  set_key CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Client y
  set_key CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_ShadowsocksR_Libev_Server n
  set_key CONFIG_PACKAGE_v2ray-core y
  set_key CONFIG_PACKAGE_v2ray-plugin n

  set_key CONFIG_PACKAGE_p910nd y
  set_key CONFIG_PACKAGE_kmod-usb-printer y
  set_key CONFIG_PACKAGE_kmod-usb-core y
  set_key CONFIG_PACKAGE_kmod-usb2 y
  set_key CONFIG_PACKAGE_kmod-usb-ohci y
  set_key CONFIG_PACKAGE_luci-app-p910nd y
  set_key CONFIG_PACKAGE_luci-app-usb-printer y

  set_key CONFIG_PACKAGE_luci-app-turboacc y
  set_key CONFIG_PACKAGE_TURBOACC_INCLUDE_FLOW_OFFLOADING y
  set_key CONFIG_PACKAGE_TURBOACC_INCLUDE_BBR_CCA n
  set_key CONFIG_PACKAGE_kmod-tcp-bbr n
  set_key CONFIG_PACKAGE_miniupnpd-iptables y
  set_key CONFIG_PACKAGE_luci-app-upnp y
  set_key CONFIG_PACKAGE_vlmcsd y
  set_key CONFIG_PACKAGE_luci-app-vlmcsd y
  set_key CONFIG_PACKAGE_etherwake y
  set_key CONFIG_PACKAGE_luci-app-wol y
  set_key CONFIG_PACKAGE_zerotier y
  set_key CONFIG_PACKAGE_luci-app-zerotier y

  set_key CONFIG_PACKAGE_odhcp6c y
  set_key CONFIG_PACKAGE_odhcpd-ipv6only y
  set_key CONFIG_PACKAGE_kmod-ipt-nat6 y
  set_key CONFIG_PACKAGE_kmod-ipt-tproxy y
  set_key CONFIG_PACKAGE_kmod-ipt-ipset y
  set_key CONFIG_PACKAGE_kmod-ipt-offload y

  set_key CONFIG_PACKAGE_curl n
  set_key CONFIG_PACKAGE_libcurl4 n
  set_key CONFIG_PACKAGE_coremark n
  set_key CONFIG_PACKAGE_coreutils-timeout n
  set_key CONFIG_PACKAGE_ddns-scripts-services n
  set_key CONFIG_PACKAGE_libncurses n
  set_key CONFIG_PACKAGE_terminfo n
}

disable_chinese() {
  local tmp
  set_key CONFIG_LUCI_LANG_zh_Hans n
  tmp="$(mktemp "$STATE_DIR/config.XXXXXX")"
  awk '
    /^CONFIG_PACKAGE_luci-i18n-.*-zh-cn=y$/ {
      sub(/=y$/, "")
      print "# " $0 " is not set"
      next
    }
    { print }
  ' "$ROOT/.config" > "$tmp"
  mv "$tmp" "$ROOT/.config"
}

show_help() {
  cat <<EOF
Usage: $SELF <start|run|status>

  start   Launch in a detached setsid/nohup process
  run     Run in the foreground (normally used internally)
  status  Show PID, status, log and artifact paths

Nothing is built until "start" or "run" is invoked.
EOF
}

show_status() {
  echo "device: $DEVICE"
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "process: RUNNING pid=$(cat "$PID_FILE")"
  else
    echo "process: NOT_RUNNING"
  fi
  [[ -f "$STATUS_FILE" ]] && echo "status: $(cat "$STATUS_FILE")" || true
  echo "log: $LOG_FILE"
  echo "artifacts: $ARTIFACT_DIR"
}

restore_source_state() {
  local rc=$?
  set +e
  if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
    cp -fp "$BACKUP_DIR/dotconfig" "$ROOT/.config"
    cp -fp "$BACKUP_DIR/v2ray-core.Makefile" "$ROOT/feeds/helloworld/v2ray-core/Makefile"
    cp -fp "$BACKUP_DIR/luci-app-ssr-plus.Makefile" "$ROOT/feeds/helloworld/luci-app-ssr-plus/Makefile"
  fi
  if [[ "$rc" -eq 0 ]]; then
    echo "COMPLETED" > "$STATUS_FILE"
  else
    echo "FAILED rc=$rc" > "$STATUS_FILE"
  fi
  date -Is > "$STATE_DIR/finished_at"
  echo "$rc" > "$STATE_DIR/rc"
  exit "$rc"
}

prepare_v2ray_cache() {
  local zip="$ROOT/dl/v2ray-linux-mips32le.zip"
  local expected="6fae6cb0293be4b64c92b738195f5af5fd2d158c63d69c170a7a6e360cca2faf"
  download_with_retry \
    "https://github.com/v2fly/v2ray-core/releases/download/v4.45.2/v2ray-linux-mips32le.zip" \
    "$zip" \
    "$expected" \
    "V2Ray 4.45.2 mips32le"
}

verify_task_dependencies() {
  local feed expected
  local -A expected_feeds=(
    [packages]="360859c8a6dcb7dc294dfc68389a8eeec8c8392a"
    [luci]="0631d439f5d57fab7f077a70e10e3b81809ae5e3"
    [routing]="56d7a818b71b83b0051b85d38efa3b3b558adf75"
    [telephony]="a04b7acfd30a6f8f4d78e62955376c4febcb0976"
    [helloworld]="9ec3e2d32753629aa9e40465611ba6e206970af5"
  )

  for feed in packages luci routing telephony helloworld; do
    expected="${expected_feeds[$feed]}"
    [[ -d "$ROOT/feeds/$feed/.git" ]] ||
      { echo "Feed is missing: $feed" >&2; return 1; }
    local actual
    actual="$(git -C "$ROOT/feeds/$feed" rev-parse HEAD)"
    [[ "$actual" == "$expected" ]] ||
      { echo "Feed $feed mismatch: expected $expected, got $actual" >&2; return 1; }
  done

  for path in \
    "$ROOT/package/feeds/helloworld/luci-app-ssr-plus" \
    "$ROOT/package/feeds/helloworld/v2ray-core" \
    "$ROOT/package/feeds/luci/luci-app-zerotier" \
    "$ROOT/package/feeds/luci/luci-app-vlmcsd" \
    "$ROOT/package/feeds/packages/vlmcsd"; do
    [[ -e "$path" ]] || { echo "Required package link is missing: $path" >&2; return 1; }
  done
}

collect_artifacts() {
  local target_dir="$ROOT/bin/targets/ramips/mt7620"
  local image="$target_dir/openwrt-ramips-mt7620-${DEVICE_TOKEN}-squashfs-sysupgrade.bin"
  local max_size=$((16064 * 1024))

  [[ -f "$image" ]] || {
    echo "Missing expected image: $image" >&2
    return 1
  }

  cp -fp "$target_dir/openwrt-ramips-mt7620-${DEVICE_TOKEN}"-*.bin "$ARTIFACT_DIR"/
  cp -fp "$target_dir/openwrt-ramips-mt7620-${DEVICE_TOKEN}.manifest" "$ARTIFACT_DIR"/
  cp -fp "$target_dir/openwrt-ramips-mt7620-${DEVICE_TOKEN}-squashfs-sysupgrade.bin.sha256sum" "$ARTIFACT_DIR"/ 2>/dev/null || true
  (
    cd "$ARTIFACT_DIR"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 |
      sort -z |
      xargs -0 sha256sum > SHA256SUMS
  )

  local size
  size="$(stat -c %s "$image")"
  echo "sysupgrade_size=$size max=$max_size"
  (( size <= max_size )) || {
    echo "Image exceeds the Y1/Y1s IMAGE_SIZE=$max_size limit" >&2
    return 1
  }
}

run_worker() {
  exec 9>"$LOCK_FILE"
  echo "WAITING_FOR_BUILD_LOCK"
  flock 9

  echo "network proxy: $AUTOBUILD_SOCKS_PROXY"
  verify_host_commands
  verify_task_dependencies

  mkdir -p "$STATE_DIR"
  BACKUP_DIR="$STATE_DIR/backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  cp -fp "$ROOT/.config" "$BACKUP_DIR/dotconfig"
  cp -fp "$ROOT/feeds/helloworld/v2ray-core/Makefile" "$BACKUP_DIR/v2ray-core.Makefile"
  cp -fp "$ROOT/feeds/helloworld/luci-app-ssr-plus/Makefile" "$BACKUP_DIR/luci-app-ssr-plus.Makefile"

  trap restore_source_state EXIT SIGINT SIGTERM
  echo "RUNNING $DEVICE" > "$STATUS_FILE"
  date -Is > "$STATE_DIR/started_at"

  cd "$ROOT"
  cp -fp "$TASK_DIR/assets/v2ray-core-mipsel.Makefile" \
    feeds/helloworld/v2ray-core/Makefile
  mkdir -p feeds/helloworld/v2ray-core/files
  cp -fp "$TASK_DIR/assets/v2ray-wrapper" \
    feeds/helloworld/v2ray-core/files/v2ray-wrapper
  cp -fp "$TASK_DIR/assets/luci-app-ssr-plus.Makefile" \
    feeds/helloworld/luci-app-ssr-plus/Makefile

  prepare_v2ray_cache
  cp -fp "$BASE_CONFIG" .config
  apply_requested_config
  make defconfig
  apply_requested_config
  disable_chinese

  grep -q '^CONFIG_PACKAGE_v2ray-core=y$' .config
  grep -q '^CONFIG_PACKAGE_luci-app-ssr-plus_INCLUDE_V2ray=y$' .config
  grep -q '^CONFIG_PACKAGE_luci-app-zerotier=y$' .config
  grep -q '^CONFIG_PACKAGE_luci-app-vlmcsd=y$' .config
  grep -q "^CONFIG_TARGET_PREINIT_IP=\"$LAN_IP\"$" .config
  grep -q "^CONFIG_TARGET_PREINIT_BROADCAST=\"$LAN_BROADCAST\"$" .config
  if grep -q '^CONFIG_PACKAGE_luci-i18n-.*-zh-cn=y$' .config; then
    echo "Chinese translations unexpectedly enabled" >&2
    return 1
  fi

  export CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types"
  export CXXFLAGS="$CFLAGS"
  export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
  export GOSUMDB="${GOSUMDB:-sum.golang.google.cn}"

  echo "Building or validating OpenWrt host tools"
  make tools/install -j"${AUTOBUILD_JOBS:-4}" V=s
  echo "Building or validating target toolchain"
  make toolchain/install -j"${AUTOBUILD_JOBS:-4}" V=s
  echo "Pre-downloading selected package sources"
  make download -j"${AUTOBUILD_DOWNLOAD_JOBS:-8}" V=s
  echo "Cleaning target package state after host tools are ready"
  make package/base-files/clean
  echo "Building target image"
  make -j"${AUTOBUILD_JOBS:-4}" V=s TARGET_DEVICES="$DEVICE_TOKEN"
  collect_artifacts
}

autobuild_main() {
  SELF="$COMMON_DIR/$(basename "$0")"
  case "${1:-help}" in
    start)
      mkdir -p "$STATE_DIR"
      if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Already running for $DEVICE: pid=$(cat "$PID_FILE")"
        show_status
        return 0
      fi
      : > "$LOG_FILE"
      echo "QUEUED" > "$STATUS_FILE"
      setsid nohup env AUTOBUILD_WORKER=1 bash "$SELF" run \
        >> "$LOG_FILE" 2>&1 < /dev/null &
      echo "$!" > "$PID_FILE"
      echo "Started detached build for $DEVICE: pid=$(cat "$PID_FILE")"
      show_status
      ;;
    run)
      run_worker
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
