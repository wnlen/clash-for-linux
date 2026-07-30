#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/core/runtime.sh
source "$PROJECT_DIR/scripts/core/runtime.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_project="$tmp_dir/project"
RUNTIME_DIR="$fixture_project/runtime"
RESOURCE_DIR="$fixture_project/resources"
BIN_DIR="$RUNTIME_DIR/bin"
LOG_DIR="$RUNTIME_DIR/logs"

mkdir -p \
  "$RESOURCE_DIR/bin/mihomo" \
  "$RESOURCE_DIR/bin/yq" \
  "$RESOURCE_DIR/bin/subconverter" \
  "$RESOURCE_DIR/geo" \
  "$BIN_DIR" \
  "$LOG_DIR"

export CLASH_TEST_UNAME_M="amd64"
export KERNEL_TYPE="mihomo"
export CLASH_OFFLINE="true"
export CLASH_PREDOWNLOAD_GEO="true"
unset CLASH_BUNDLED_ASSET_DIR
unset CLASH_BUNDLED_ASSET_ENABLED

mihomo_version="${MIHOMO_VERSION:-$DEFAULT_MIHOMO_VERSION}"
yq_version="${YQ_VERSION:-$DEFAULT_YQ_VERSION}"
subconverter_version="${SUBCONVERTER_VERSION:-$DEFAULT_SUBCONVERTER_VERSION}"

mihomo_file="$(mihomo_asset_file amd64 "$mihomo_version")"
yq_file="$(yq_asset_file amd64)"
subconverter_file="$(subconverter_asset_file amd64)"

printf 'mock\n' > "$RESOURCE_DIR/bin/mihomo/$mihomo_file"
printf 'mock\n' > "$RESOURCE_DIR/bin/yq/$yq_file"
printf 'mock\n' > "$RESOURCE_DIR/bin/subconverter/$subconverter_file"

for item in "${GEO_ASSET_DOWNLOADS[@]}"; do
  geo_path="${item%% *}"
  printf 'mock\n' > "$RESOURCE_DIR/geo/$(basename "$geo_path")"
done

preflight_offline_assets >/dev/null
echo "ok - complete offline asset set passes preflight"

rm -f "$RESOURCE_DIR/bin/mihomo/$mihomo_file"
missing_output="$tmp_dir/missing-output"
if (preflight_offline_assets) >"$missing_output" 2>&1; then
  echo "not ok - missing Mihomo asset unexpectedly passed preflight" >&2
  exit 1
fi

if ! grep -Fq "Mihomo" "$missing_output"; then
  echo "not ok - missing asset output did not identify Mihomo" >&2
  cat "$missing_output" >&2
  exit 1
fi
echo "ok - missing offline asset fails with an actionable name"

blocked_output="$tmp_dir/blocked-output"
if (download_file "https://example.com/file" "$tmp_dir/downloaded" "fixture") >"$blocked_output" 2>&1; then
  echo "not ok - offline download unexpectedly succeeded" >&2
  exit 1
fi

if [ -e "$tmp_dir/downloaded" ]; then
  echo "not ok - offline download created an output file" >&2
  exit 1
fi

if ! grep -Fq "离线模式禁止下载" "$blocked_output"; then
  echo "not ok - offline download failure was not explicit" >&2
  cat "$blocked_output" >&2
  exit 1
fi
echo "ok - offline mode blocks remote fallback before curl"

parse_install_options user --offline
if [ "$INSTALL_REQUESTED_SCOPE" != "user" ] \
  || [ "$INSTALL_OFFLINE_REQUESTED" != "true" ]; then
  echo "not ok - install option parser lost scope or offline flag" >&2
  exit 1
fi
echo "ok - install options accept scope and --offline together"

dry_run_output="$tmp_dir/dry-run-output"
bash "$PROJECT_DIR/scripts/prefetch-assets.sh" \
  --arch arm64 \
  --kernel mihomo \
  --dry-run >"$dry_run_output"

if ! grep -Fq "mihomo-linux-arm64-" "$dry_run_output" \
  || ! grep -Fq "subconverter_aarch64.tar.gz" "$dry_run_output" \
  || ! grep -Fq "未生成资源包" "$dry_run_output"; then
  echo "not ok - prefetch dry run did not describe the arm64 bundle" >&2
  cat "$dry_run_output" >&2
  exit 1
fi
echo "ok - prefetch dry run resolves target architecture without downloading"
