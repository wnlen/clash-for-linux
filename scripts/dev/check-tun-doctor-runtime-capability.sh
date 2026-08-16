#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source_clashctl_for_tests() {
  set -- ""
  # Source the real doctor functions; suppress the no-arg usage output.
  source "$PROJECT_DIR/scripts/core/clashctl.sh" >/dev/null
}

source_clashctl_for_tests

# Keep every unrelated doctor signal healthy so the assertion isolates the
# capability decision reported by tun_problem_lines.
tun_kernel_support_level() { printf 'full\n'; }
tun_container_mode() { printf 'host\n'; }
tun_container_risk_reason() { :; }
status_tun_last_action_result() { :; }
status_tun_last_action_reason() { :; }
status_tun_last_action_time() { :; }
tun_enabled() { printf 'true\n'; }
container_env_type() { printf 'host\n'; }
runtime_config_tun_enabled() { printf 'true\n'; }
runtime_config_tun_auto_route() { printf 'true\n'; }
default_route_dev() { printf 'Meta\n'; }
tun_device_exists() { return 0; }
tun_device_readable() { return 0; }
has_ip_command() { return 0; }
can_manage_tun_safely() { return 1; }
runtime_config_exists() { return 0; }
tun_current_effective_result() { printf 'ok\n'; }

test_backend="systemd"
test_process_has_cap="true"

runtime_backend() { printf '%s\n' "$test_backend"; }
tun_process_has_cap_net_admin() { [ "$test_process_has_cap" = "true" ]; }

assert_capability_problem() {
  local name="$1"
  local expected="$2"
  local output actual

  output="$(tun_problem_lines)"
  if printf '%s\n' "$output" | grep -Fq '当前环境不满足 Tun 安全开启条件'; then
    actual="present"
  else
    actual="absent"
  fi

  if [ "$actual" != "$expected" ]; then
    echo "not ok - $name: capability problem is $actual, expected $expected" >&2
    [ -n "${output:-}" ] && printf '%s\n' "$output" | sed 's/^/  /' >&2
    return 1
  fi

  echo "ok - $name"
}

# Reproduce Issue #307: a non-root diagnostic shell cannot manage Tun itself,
# while the running systemd Mihomo process has CAP_NET_ADMIN.
assert_capability_problem \
  "accepts CAP_NET_ADMIN from the running systemd process" \
  "absent"

test_backend="systemd-user"
assert_capability_problem \
  "accepts CAP_NET_ADMIN from the running user systemd process" \
  "absent"

test_backend="systemd"
test_process_has_cap="false"
assert_capability_problem \
  "keeps the warning when the systemd process lacks CAP_NET_ADMIN" \
  "present"

test_backend="script"
test_process_has_cap="true"
assert_capability_problem \
  "does not borrow process capability for the script backend" \
  "present"
