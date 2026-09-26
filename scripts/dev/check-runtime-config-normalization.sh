#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
YQ_VERSION="${YQ_VERSION:-v4.52.4}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/runtime" "$tmp_dir/config" "$tmp_dir/logs"

install_test_yq() {
  local target="$tmp_dir/bin/yq"
  local system_yq

  if [ -n "${CLASH_TEST_YQ_BIN:-}" ] && [ -x "$CLASH_TEST_YQ_BIN" ]; then
    cp "$CLASH_TEST_YQ_BIN" "$target"
    chmod +x "$target"
    return 0
  fi

  if [ -x "$PROJECT_DIR/runtime/bin/yq" ]; then
    cp "$PROJECT_DIR/runtime/bin/yq" "$target"
    chmod +x "$target"
    return 0
  fi

  system_yq="$(command -v yq 2>/dev/null || true)"
  if [ -n "${system_yq:-}" ] && "$system_yq" --version 2>/dev/null | grep -q 'version v4'; then
    cp "$system_yq" "$target"
    chmod +x "$target"
    return 0
  fi

  local arch file url archive extract_dir
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) file="yq_linux_amd64.tar.gz" ;;
    aarch64|arm64) file="yq_linux_arm64.tar.gz" ;;
    armv7l|armv7*) file="yq_linux_arm.tar.gz" ;;
    *) echo "not ok - unsupported test architecture for yq: $arch" >&2; return 1 ;;
  esac

  url="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${file}"
  archive="$tmp_dir/$file"
  extract_dir="$tmp_dir/yq-extract"
  mkdir -p "$extract_dir"
  curl -fsSL "$url" -o "$archive"
  tar -xzf "$archive" -C "$extract_dir"
  find "$extract_dir" -type f -name 'yq*' -perm -111 -print -quit | xargs -r -I{} cp "{}" "$target"
  [ -x "$target" ] || chmod +x "$target" 2>/dev/null || true
  [ -x "$target" ] || { echo "not ok - failed to install temporary yq" >&2; return 1; }
}

install_test_yq

export PROJECT_DIR
export RUNTIME_DIR="$tmp_dir/runtime"
export BIN_DIR="$tmp_dir/bin"
export LOG_DIR="$tmp_dir/logs"
export CONFIG_DIR="$tmp_dir/config"
unset CLASH_IPV6

# shellcheck source=scripts/core/config.sh
source "$PROJECT_DIR/scripts/core/config.sh"

# Keep this regression test independent from the developer's project .env.
read_env_value() { return 1; }

# Keep port resolution deterministic for this test; the preservation path must
# not depend on whatever happens to be listening on the developer's machine.
is_port_in_use() { return 1; }
port_reserved_by_current_runtime() { return 1; }

preserved_port_config="$tmp_dir/preserved-dns-port-config.yaml"
cat > "$preserved_port_config" <<'YAML'
mixed-port: 7890
external-controller: 0.0.0.0:9090
dns:
  listen: 127.0.0.1:7874
proxies: []
proxy-groups: []
rules: []
YAML

unset MIXED_PORT EXTERNAL_CONTROLLER CLASH_DNS_PORT CLASH_PRESERVE_DNS_LISTEN
default_port_resolution="$(resolve_runtime_ports "$preserved_port_config")"
if printf '%s\n' "$default_port_resolution" | grep -qx 'CLASH_DNS_PORT_RESOLVED=1053'; then
  echo "ok - default DNS port remains configurable"
else
  echo "not ok - default DNS port resolution changed unexpectedly: $default_port_resolution" >&2
  exit 1
fi

preserved_port_resolution="$(CLASH_PRESERVE_DNS_LISTEN=true resolve_runtime_ports "$preserved_port_config")"
if printf '%s\n' "$preserved_port_resolution" | grep -qx 'CLASH_DNS_PORT_RESOLVED=7874'; then
  echo "ok - preserves subscription DNS port during resolution"
else
  echo "not ok - subscription DNS port was not preserved: $preserved_port_resolution" >&2
  exit 1
fi

resolve_runtime_ports() {
  printf 'MIXED_PORT_RESOLVED=7891\n'
  printf 'EXTERNAL_CONTROLLER_RESOLVED=0.0.0.0:9090\n'
  printf 'CLASH_DNS_PORT_RESOLVED=1053\n'
}

ensure_controller_secret() { printf 'test-secret\n'; }
runtime_dashboard_dir() { printf '%s/dashboard\n' "$RUNTIME_DIR"; }
tun_enabled() { printf 'false\n'; }
tun_stack() { printf 'mixed\n'; }
tun_auto_route() { printf 'false\n'; }
tun_auto_redirect() { printf 'false\n'; }
tun_strict_route() { printf 'false\n'; }
tun_dns_hijack() { printf 'any:53\n'; }

set_config_allow_lan false

actual="$("$BIN_DIR/yq" eval '.["allow-lan"]' "$CONFIG_DIR/template.yaml")"
if [ "$actual" != "false" ]; then
  echo "not ok - writes disabled LAN setting: got '$actual', expected 'false'" >&2
  exit 1
fi
echo "ok - writes disabled LAN setting"

actual="$(config_allow_lan)"
if [ "$actual" != "false" ]; then
  echo "not ok - reads disabled LAN setting: got '$actual', expected 'false'" >&2
  exit 1
fi
echo "ok - reads disabled LAN setting"

sample_config="$tmp_dir/runtime-config.yaml"
cat > "$sample_config" <<'YAML'
port: 7890
socks-port: 7891
redir-port: 7892
tproxy-port: 7893
mixed-port: 7890
external-controller: 0.0.0.0:9090
secret: old-secret
allow-lan: false
ipv6: true
dns:
  listen: 127.0.0.1:7874
  ipv6: true
proxies:
  - name: hy2-ipv6
    type: hysteria2
    server: "2001:db8::1"
    port: 443
    password: test-password
  - name: anytls
    type: anytls
    server: 192.0.2.1
    port: 443
    password: test-password
    sni: example.com
proxy-groups: []
rules: []
YAML

preserved_normalization_config="$tmp_dir/preserved-dns-normalization.yaml"
cp "$sample_config" "$preserved_normalization_config"

normalize_runtime_config "$sample_config"

assert_file_yq() {
  local name="$1"
  local file="$2"
  local expr="$3"
  local expected="$4"
  local actual

  actual="$("$BIN_DIR/yq" eval "$expr" "$file")"
  if [ "$actual" != "$expected" ]; then
    echo "not ok - $name: got '$actual', expected '$expected'" >&2
    "$BIN_DIR/yq" eval '.' "$file" >&2 || true
    return 1
  fi
  echo "ok - $name"
}

assert_yq() {
  assert_file_yq "$1" "$sample_config" "$2" "$3"
}

assert_yq "keeps resolved mixed-port" '.["mixed-port"]' "7891"
assert_yq "removes legacy port" 'has("port")' "false"
assert_yq "removes legacy socks-port" 'has("socks-port")' "false"
assert_yq "removes legacy redir-port" 'has("redir-port")' "false"
assert_yq "removes legacy tproxy-port" 'has("tproxy-port")' "false"
assert_yq "keeps controller normalization" '.["external-controller"]' "0.0.0.0:9090"
assert_yq "keeps LAN proxy disabled" '.["allow-lan"]' "false"

cp "$sample_config" "$RUNTIME_DIR/config.yaml"
actual="$(runtime_config_allow_lan)"
if [ "$actual" != "false" ]; then
  echo "not ok - reports disabled runtime LAN status: got '$actual', expected 'false'" >&2
  exit 1
fi
echo "ok - reports disabled runtime LAN status"

assert_yq "preserves subscription IPv6" '.ipv6' "true"
assert_yq "preserves subscription DNS IPv6" '.dns.ipv6' "true"
assert_yq "normalizes DNS listen by default" '.dns.listen' "0.0.0.0:1053"
assert_yq "preserves Hysteria2 proxy type" '.proxies[0].type' "hysteria2"
assert_yq "preserves IPv6-only proxy server" '.proxies[0].server' "2001:db8::1"
assert_yq "preserves AnyTLS proxy type" '.proxies[1].type' "anytls"
assert_yq "preserves AnyTLS SNI" '.proxies[1].sni' "example.com"

CLASH_PRESERVE_DNS_LISTEN=true normalize_runtime_config "$preserved_normalization_config"
assert_file_yq "preserves subscription DNS listen when enabled" "$preserved_normalization_config" '.dns.listen' "127.0.0.1:7874"
unset CLASH_PRESERVE_DNS_LISTEN

CLASH_IPV6=false normalize_runtime_config "$sample_config"
assert_yq "IPv6 off disables kernel IPv6" '.ipv6' "false"
assert_yq "IPv6 off disables DNS IPv6" '.dns.ipv6' "false"

unset CLASH_IPV6
normalize_runtime_config "$sample_config"
assert_yq "auto preserves disabled kernel IPv6" '.ipv6' "false"
assert_yq "auto preserves disabled DNS IPv6" '.dns.ipv6' "false"

CLASH_IPV6=true normalize_runtime_config "$sample_config"
assert_yq "IPv6 on enables kernel IPv6" '.ipv6' "true"
assert_yq "IPv6 on enables DNS IPv6" '.dns.ipv6' "true"
unset CLASH_IPV6

default_config="$tmp_dir/default-ipv6-config.yaml"
cat > "$default_config" <<'YAML'
proxies: []
proxy-groups: []
rules: []
YAML

normalize_runtime_config "$default_config"
assert_file_yq "auto keeps kernel IPv6 default enabled" "$default_config" '.ipv6' "true"
assert_file_yq "auto keeps legacy DNS IPv6 default disabled" "$default_config" '.dns.ipv6' "false"

default_subscription_ua="$(
  unset CLASH_SUBSCRIPTION_UA CLASH_SUB_UA
  subconverter_subscription_user_agent
)"
if [ "$default_subscription_ua" != "clash-verge/v2.4.0" ]; then
  echo "not ok - modern protocol subscription UA: got '$default_subscription_ua'" >&2
  exit 1
fi
echo "ok - modern protocol subscription UA"

share_links="$tmp_dir/modern-share-links.txt"
cat > "$share_links" <<'EOF'
vmess://legacy
hysteria2://password@example.com:443
hy2://password@example.com:443
anytls://password@example.com:443
EOF

converted_links="$(local_subscription_share_links_to_subconverter_url "$share_links")"
case "$converted_links" in
  *"hysteria2://"*"hy2://"*"anytls://"*)
    echo "ok - recognizes Hysteria2, hy2 and AnyTLS share links"
    ;;
  *)
    echo "not ok - modern share links were dropped: $converted_links" >&2
    exit 1
    ;;
esac
