#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$PROJECT_DIR/scripts/core/common.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

openwrt_root="$tmp_dir/openwrt"
fake_bin="$tmp_dir/bin"
mkdir -p "$openwrt_root/etc" "$fake_bin"
: > "$openwrt_root/etc/openwrt_release"

link_command() {
  local command_name="$1"
  local command_path

  command_path="$(command -v "$command_name")"
  ln -s "$command_path" "$fake_bin/$command_name"
}

for command_name in bash curl tar gzip readlink unzip; do
  link_command "$command_name"
done

output_file="$tmp_dir/missing-dependencies.out"
set +e
(
  export CLASH_OPENWRT_ROOT="$openwrt_root"
  export CLASH_TEST_UNAME_M="aarch64"
  PATH="$fake_bin"
  ensure_openwrt_install_supported
) > "$output_file" 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "not ok - OpenWrt preflight should reject missing install and nohup commands" >&2
  exit 1
fi

if ! grep -Fq "OpenWrt 缺少依赖命令：install nohup" "$output_file"; then
  echo "not ok - OpenWrt preflight did not report install and nohup together" >&2
  cat "$output_file" >&2
  exit 1
fi

if ! grep -Fq "coreutils-install coreutils-nohup" "$output_file"; then
  echo "not ok - OpenWrt dependency hint omitted install/nohup packages" >&2
  cat "$output_file" >&2
  exit 1
fi

echo "ok - OpenWrt preflight reports install and nohup packages before downloads"

link_command install
link_command nohup

(
  export CLASH_OPENWRT_ROOT="$openwrt_root"
  export CLASH_TEST_UNAME_M="aarch64"
  PATH="$fake_bin"
  ensure_openwrt_install_supported
)

echo "ok - OpenWrt preflight accepts the complete dependency set"
