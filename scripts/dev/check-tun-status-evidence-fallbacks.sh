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

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

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

status_of() {
  if "$@" >/dev/null 2>&1; then
    echo "pass"
  else
    echo "fail"
  fi
}

# Host state of a live report: auto-route + auto-redirect with
# route-exclude-address, log-level warning, and ip.sb unreachable directly.
has_ip_command() { return 0; }

test_link_output='7: Meta: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 9000 qdisc fq_codel state UNKNOWN mode DEFAULT group default qlen 500'
test_routes='0.0.0.0/5 via 198.18.0.2 dev Meta table 2022
8.0.0.0/7 via 198.18.0.2 dev Meta table 2022
default via 172.19.47.253 dev eth0 proto dhcp src 172.19.34.221 metric 100
local 198.18.0.1 dev Meta table local proto kernel scope host src 198.18.0.1'

ip() {
  case "$*" in
    "route show default") printf 'default via 172.19.47.253 dev eth0 proto dhcp metric 100\n' ;;
    "route show table all") printf '%s\n' "$test_routes" ;;
    "rule show") printf '9002:\tnot from all iif lo lookup 2022\n' ;;
    "-o link show up") printf '%s\n' "$test_link_output" ;;
    *) return 1 ;;
  esac
}

mkdir -p "$tmp_dir/logs"
LOG_DIR="$tmp_dir/logs"
printf '%s\n' 'level=warning msg="[TUN] default interface changed by monitor, => eth0"' > "$LOG_DIR/mihomo.out.log"

assert_equal \
  "accepts split Tun routes in table 2022 without a default route" \
  "0.0.0.0/5 via 198.18.0.2 dev Meta table 2022" \
  "$(tun_policy_route_line)"

assert_equal \
  "accepts an up Tun link when the adapter log line is absent" \
  "pass" \
  "$(status_of tun_has_policy_routing_evidence)"

test_link_output=""
assert_equal \
  "still requires adapter evidence" \
  "fail" \
  "$(status_of tun_has_policy_routing_evidence)"
test_link_output='7: Meta: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 9000 qdisc fq_codel state UNKNOWN mode DEFAULT group default qlen 500'

test_routes='default via 172.19.47.253 dev eth0 proto dhcp metric 100
local 198.18.0.1 dev Meta table local proto kernel scope host src 198.18.0.1'
assert_equal \
  "ignores Meta routes outside table 2022" \
  "fail" \
  "$(status_of tun_policy_route_line)"
test_routes='0.0.0.0/5 via 198.18.0.2 dev Meta table 2022
8.0.0.0/7 via 198.18.0.2 dev Meta table 2022'

# The interface-bound probe fails; an unbound probe would go through Tun and
# return the proxy exit, which must not be reported as the host IP.
mkdir -p "$tmp_dir/bin"
cat > "$tmp_dir/bin/curl" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  [ "$arg" = "--interface" ] && exit 28
done
echo 203.0.113.10
EOF
chmod +x "$tmp_dir/bin/curl"
PATH="$tmp_dir/bin:$PATH"

assert_equal \
  "does not fall back to an unbound host IP probe" \
  "fail" \
  "$(status_of tun_public_ip_without_proxy_env)"

tun_enabled() { printf 'true\n'; }
runtime_config_tun_enabled() { printf 'true\n'; }
runtime_config_tun_auto_route() { printf 'true\n'; }
status_is_running() { return 0; }
proxy_controller_reachable() { return 0; }

assert_equal \
  "reports host IP as unavailable instead of same-as-host" \
  "host-ip-unavailable" \
  "$(tun_traffic_effective_check || true)"

assert_equal \
  "treats the reported host as likely effective" \
  "policy-routing-likely-effective" \
  "$(tun_current_effective_result)"
