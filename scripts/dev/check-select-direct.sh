#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source_clashctl_for_tests() {
  set -- ""
  source "$PROJECT_DIR/scripts/core/clashctl.sh" >/dev/null
}

source_clashctl_for_tests

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

prepare() { :; }
status_is_running() { return 0; }
proxy_controller_reachable() { return 0; }
print_select_feedback() { printf 'feedback:%s\n' "$1"; }
die_usage() {
  printf 'usage:%s\nnext:%s\n' "$1" "${2:-}"
  exit 2
}
die_state() {
  printf 'state:%s\nnext:%s\n' "$1" "${2:-}"
  exit 3
}

run_help_case() {
  local output rc

  set +e
  output="$(cmd_select --help 2>&1)"
  rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    echo "not ok - select help should succeed" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  if ! printf '%s\n' "$output" | grep -Fq "clash select <策略组> <节点>"; then
    echo "not ok - select help missing direct usage" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  echo "ok - select help prints direct usage"
}

run_direct_case() {
  local output

  proxy_group_select() {
    printf '%s -> %s\n' "$1" "$2" > "$tmp_dir/selected"
  }

  output="$(cmd_select "🚀 节点选择" "日本 01")"

  if [ "$(cat "$tmp_dir/selected")" != "🚀 节点选择 -> 日本 01" ]; then
    echo "not ok - direct select did not pass group and node through" >&2
    cat "$tmp_dir/selected" >&2
    return 1
  fi

  if ! printf '%s\n' "$output" | grep -Fq "feedback:🚀 节点选择"; then
    echo "not ok - direct select did not print feedback" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  echo "ok - direct select delegates to proxy_group_select"
}

run_bad_args_case() {
  local output rc

  set +e
  output="$(cmd_select only-group 2>&1)"
  rc=$?
  set -e

  if [ "$rc" -ne 2 ]; then
    echo "not ok - bad direct select args should fail usage" >&2
    printf 'rc=%s\n%s\n' "$rc" "$output" >&2
    return 1
  fi

  echo "ok - direct select validates arguments"
}

run_help_case
run_direct_case
run_bad_args_case
