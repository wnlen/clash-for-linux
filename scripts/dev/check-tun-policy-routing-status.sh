#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source_clashctl_for_tests() {
  set -- ""
  # Source the real functions; suppress the no-arg usage printed by the command dispatcher.
  source "$PROJECT_DIR/scripts/core/clashctl.sh" >/dev/null
}

source_clashctl_for_tests

assert_equal() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$actual" != "$expected" ]; then
    echo "not ok - $name: got '$actual', expected '$expected'" >&2
    return 1
  fi

  echo "ok - $name"
}

# Reproduce Issues #303 and #309: policy routing sends both direct-looking
# probes through Tun, so comparing their public IPs alone reports
# traffic-same-as-host. The fallback must follow auto-route, including when
# auto-redirect is disabled.
tun_enabled() { printf 'true\n'; }
runtime_config_tun_enabled() { printf 'true\n'; }
status_is_running() { return 0; }
proxy_controller_reachable() { return 0; }
tun_public_ip_without_proxy_env() { printf '203.0.113.10\n'; }
tun_public_ip_with_current_route() { printf '203.0.113.10\n'; }
test_auto_route="true"
runtime_config_tun_auto_route() { printf '%s\n' "$test_auto_route"; }
runtime_config_tun_auto_redirect() { printf 'false\n'; }
tun_has_policy_routing_evidence() { return 0; }
tun_log_tun_source_line() { printf '[TCP] 28.0.0.1:1234 --> example.com:443\n'; }

assert_equal \
  "accepts auto-route policy routing when auto-redirect is disabled" \
  "ok" \
  "$(tun_current_effective_result)"
assert_equal \
  "status uses local policy routing evidence without a public IP probe" \
  "effective" \
  "$(
    tun_current_effective_result() { printf 'unexpected-public-ip-probe\n'; }
    status_tun_effective_status
  )"

# The same classifier must drive both status commands. Without observed traffic,
# keep the result explicit instead of presenting a false negative.
tun_log_tun_source_line() { return 1; }
assert_equal \
  "reports policy routing without traffic as likely effective" \
  "policy-routing-likely-effective" \
  "$(tun_current_effective_result)"
assert_equal \
  "maps likely policy routing to a distinct status" \
  "likely-effective" \
  "$(status_tun_effective_status)"

# Do not let stale policy-routing evidence override a runtime configuration that
# explicitly disables auto-route.
test_auto_route="false"
assert_equal \
  "requires auto-route before accepting policy routing evidence" \
  "traffic-same-as-host" \
  "$(tun_current_effective_result)"

# Reproduce the restart race: verification must happen only after waiting for
# the controller following service_restart.
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
events_file="$tmp_dir/events"
: > "$events_file"

record_event() {
  printf '%s\n' "$1" >> "$events_file"
}

guard_sudo_on_user_install() { return 0; }
prepare() { :; }
tun_container_mode() { printf 'host\n'; }
tun_container_risk_reason() { :; }
can_manage_tun_safely() { return 0; }
tun_kernel_support_level() { printf 'full\n'; }
sync_tun_target_state() { return 0; }
service_restart() { record_event restart; }
wait_runtime_controller_ready() { record_event wait; return 0; }
tun_current_effective_result() { record_event verify; printf 'ok\n'; }
mark_tun_last_action() { :; }
mark_tun_last_verification() { :; }
print_tun_on_feedback() { :; }

cmd_tun_on
assert_equal \
  "waits for controller before Tun verification" \
  "restart,wait,verify" \
  "$(paste -sd, "$events_file")"
