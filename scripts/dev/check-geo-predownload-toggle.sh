#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/core/runtime.sh
source "$PROJECT_DIR/scripts/core/runtime.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

RUNTIME_DIR="$tmp_dir/runtime"
RESOURCE_DIR="$tmp_dir/resources"
mkdir -p "$RUNTIME_DIR" "$RESOURCE_DIR"

download_log="$tmp_dir/downloads"
copy_log="$tmp_dir/copies"
: > "$download_log"
: > "$copy_log"

copy_bundled_asset() {
  printf '%s\n' "$*" >> "$copy_log"
  return 1
}

download_file() {
  local url="$1"
  local out="$2"
  local asset_name="$3"

  printf '%s %s %s\n' "$asset_name" "$url" "$out" >> "$download_log"
  mkdir -p "$(dirname "$out")"
  printf 'mock\n' > "$out"
}

assert_download_count() {
  local name="$1"
  local expected="$2"
  local actual

  actual="$(wc -l < "$download_log" | tr -d ' ')"
  if [ "$actual" != "$expected" ]; then
    echo "not ok - $name: got $actual downloads, expected $expected" >&2
    sed 's/^/  /' "$download_log" >&2
    return 1
  fi

  echo "ok - $name"
}

unset CLASH_PREDOWNLOAD_GEO
resolve_geo_assets
assert_download_count "default predownloads GEO assets" 5

: > "$download_log"
CLASH_PREDOWNLOAD_GEO=false resolve_geo_assets
assert_download_count "explicit false skips install-time GEO predownload" 0

: > "$download_log"
CLASH_PREDOWNLOAD_GEO=true resolve_geo_assets
assert_download_count "existing GEO assets are reused" 0

rm -f "$RUNTIME_DIR/GeoSite.dat"
: > "$download_log"
CLASH_PREDOWNLOAD_GEO=true resolve_geo_assets
assert_download_count "only missing GEO assets are downloaded" 1

: > "$RUNTIME_DIR/GeoSite.dat"
: > "$download_log"
CLASH_PREDOWNLOAD_GEO=true resolve_geo_assets
assert_download_count "empty GEO assets are replaced" 1

: > "$download_log"
CLASH_OFFLINE=true CLASH_PREDOWNLOAD_GEO=true resolve_geo_assets
assert_download_count "offline install reuses existing GEO assets" 0
