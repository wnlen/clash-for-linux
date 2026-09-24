#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/core/common.sh
source "$PROJECT_DIR/scripts/core/common.sh"
# shellcheck source=scripts/core/config.sh
source "$PROJECT_DIR/scripts/core/config.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

RUNTIME_DIR="$tmp_dir/runtime"
mkdir -p "$RUNTIME_DIR"

success_output="$tmp_dir/success.out"
failure_output="$tmp_dir/failure.out"
cancel_output="$tmp_dir/cancel.out"

download_subscription_fetch_quiet() {
  local _url="$1"
  local out="$2"

  sleep 5
  printf 'proxies: []\nproxy-groups: []\nrules: []\n' > "$out"
}

download_subscription_file "https://example.invalid/sub" "$tmp_dir/success.yaml" \
  >"$success_output" 2>&1

if grep -q '94\.0%' "$success_output"; then
  echo "not ok - subscription download must not show fake 94% progress" >&2
  exit 1
fi

if ! grep -q '100\.0%' "$success_output"; then
  echo "not ok - successful subscription download should keep the 100% completion line" >&2
  exit 1
fi

echo "ok - successful subscription download has no fake progress"

download_subscription_fetch_quiet() {
  printf 'curl: (28) Operation timed out\n' >&2
  return 28
}

set +e
CLASH_INSTALL_ALLOW_SUBSCRIPTION_SKIP=true \
  download_subscription_file "https://example.invalid/sub" "$tmp_dir/failure.yaml" \
  >"$failure_output" 2>&1
failure_rc="$?"
set -e

if [ "$failure_rc" -ne 28 ]; then
  echo "not ok - timeout should preserve curl exit code 28, got $failure_rc" >&2
  exit 1
fi

expected_failure='⚠ 订阅下载失败：连接超时；已跳过，请稍后执行 clash sub update'
if ! grep -Fxq "$expected_failure" "$failure_output"; then
  echo "not ok - install-time timeout should show one concise reason" >&2
  sed 's/^/  /' "$failure_output" >&2
  exit 1
fi

if [ "$(grep -Ec '^(⚠|❌).*订阅下载' "$failure_output" || true)" -ne 1 ]; then
  echo "not ok - timeout should show exactly one subscription failure line" >&2
  sed 's/^/  /' "$failure_output" >&2
  exit 1
fi

if grep -q 'curl:' "$failure_output"; then
  echo "not ok - raw curl errors should stay out of normal output" >&2
  exit 1
fi

echo "ok - failed subscription download shows one concise reason"

download_subscription_fetch_quiet() {
  local _url="$1"
  local out="$2"

  sleep 30
  printf 'unexpected completion\n' > "$out"
}

subscription_download_wait_status() {
  kill -INT "$BASHPID"
}

set +e
CLASH_INSTALL_ALLOW_SUBSCRIPTION_SKIP=true \
  download_subscription_file "https://example.invalid/sub" "$tmp_dir/cancel.yaml" \
  >"$cancel_output" 2>&1
cancel_rc="$?"
set -e

if [ "$cancel_rc" -ne 130 ]; then
  echo "not ok - Ctrl+C should return 130, got $cancel_rc" >&2
  exit 1
fi

expected_cancel='⚠ 已取消订阅下载；安装继续，请稍后执行 clash sub update'
if ! grep -Fxq "$expected_cancel" "$cancel_output"; then
  echo "not ok - Ctrl+C should show one concise skip message" >&2
  sed 's/^/  /' "$cancel_output" >&2
  exit 1
fi

if [ -e "$tmp_dir/cancel.yaml" ]; then
  echo "not ok - cancelled subscription download left an output file" >&2
  exit 1
fi

echo "ok - Ctrl+C cancels only the subscription download"

generate_marker="$tmp_dir/generate.marker"
generate_output="$tmp_dir/generate.out"
harness_config_dir="$tmp_dir/config"

(
  set +e

  compile_error=""
  ensure_active_subscription_usable() { return 0; }
  clear_compile_error() { compile_error=""; }
  active_subscription_name() { echo "default"; }
  config_tmp_dir() { echo "$harness_config_dir"; }
  subscription_exists() { return 0; }
  subscription_enabled() { return 0; }
  fetch_subscription_source() {
    SUBSCRIPTION_DOWNLOAD_LAST_STATUS="failed"
    SUBSCRIPTION_DOWNLOAD_LAST_ERROR_SUMMARY="订阅下载失败：连接超时"
    SUBSCRIPTION_DOWNLOAD_LAST_ERROR_DETAIL="curl exit code: 28"
    return 1
  }
  read_compile_error() {
    [ -n "$compile_error" ] || return 1
    printf '%s\n' "$compile_error"
  }
  write_compile_error() { compile_error="$1"; }
  append_compile_error() { compile_error="${compile_error}${compile_error:+\n}$1"; }
  record_build_error_detail() { :; }
  record_build_failure() { :; }
  mark_runtime_build_not_applied() { :; }

  generate_config
  generate_rc="$?"

  if subscription_download_failed_or_cancelled; then
    skippable="true"
  else
    skippable="false"
  fi

  printf 'rc=%s status=%s skippable=%s\n' \
    "$generate_rc" \
    "${SUBSCRIPTION_DOWNLOAD_LAST_STATUS:-}" \
    "$skippable" > "$generate_marker"
) >"$generate_output" 2>&1

if [ "$(cat "$generate_marker" 2>/dev/null || true)" != "rc=1 status=failed skippable=true" ]; then
  echo "not ok - install control flow should survive a subscription download failure" >&2
  sed 's/^/  /' "$generate_output" >&2
  exit 1
fi

if [ -s "$generate_output" ]; then
  echo "not ok - build layer repeated the downloader failure message" >&2
  sed 's/^/  /' "$generate_output" >&2
  exit 1
fi

echo "ok - install control flow can skip a failed subscription"
