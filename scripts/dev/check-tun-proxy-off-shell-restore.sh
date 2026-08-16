#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source_clashctl_for_tests() {
  set -- ""
  # Source the real command functions; suppress the no-arg usage output.
  source "$PROJECT_DIR/scripts/core/clashctl.sh" >/dev/null
}

source_clashctl_for_tests

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

test_project="$tmp_dir/project"
RUNTIME_DIR="$test_project/runtime"
mkdir -p "$test_project/scripts/core" "$RUNTIME_DIR"
cp "$PROJECT_DIR/scripts/core/alias.sh" "$test_project/scripts/core/alias.sh"

cat > "$RUNTIME_DIR/config.yaml" <<'YAML'
mixed-port: 7890
YAML

set_shell_proxy_persist_enabled "true"

cmd_tun_on() { :; }
boot_proxy_keep_disable() { :; }
ui_blank() { :; }
ui_ok() { :; }
ui_warn() { :; }
ui_next() { :; }

cmd_tun_on_proxy_off

if shell_proxy_persist_enabled; then
  echo "not ok - tun on-proxy-off keeps shell proxy auto-restore enabled" >&2
  exit 1
fi

actual="$(
  env -i \
    HOME="$tmp_dir/home" \
    PATH="$PATH" \
    bash --noprofile --norc -c '
      unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
      source "'"$test_project"'/scripts/core/alias.sh"
      printf "%s\n" "${http_proxy:-}"
    '
)"

if [ -n "$actual" ]; then
  echo "not ok - a new shell restored proxy after tun on-proxy-off: $actual" >&2
  exit 1
fi

echo "ok - tun on-proxy-off disables shell proxy auto-restore"

set_shell_proxy_persist_enabled "true"
boot_proxy_keep_disable() { return 2; }

if cmd_tun_on_proxy_off; then
  echo "not ok - tun on-proxy-off ignored system proxy cleanup failure" >&2
  exit 1
else
  actual_rc=$?
fi

if [ "$actual_rc" -ne 2 ]; then
  echo "not ok - tun on-proxy-off returned $actual_rc, expected 2" >&2
  exit 1
fi

if shell_proxy_persist_enabled; then
  echo "not ok - system proxy cleanup failure left shell auto-restore enabled" >&2
  exit 1
fi

echo "ok - shell auto-restore stays off when system proxy cleanup fails"
