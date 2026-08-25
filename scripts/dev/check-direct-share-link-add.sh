#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source_clashctl_for_tests() {
  set -- ""
  # Source the real command functions; suppress the no-arg usage printed by the dispatcher.
  source "$PROJECT_DIR/scripts/core/clashctl.sh" >/dev/null
}

assert_equal() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$actual" != "$expected" ]; then
    echo "not ok - $name: got '$actual', expected '$expected'" >&2
    exit 1
  fi

  echo "ok - $name"
}

source_clashctl_for_tests

schemes=(vmess vless trojan tuic hysteria2 hy2 anytls)
urls=(
  'vmess://test-payload'
  'vless://00000000-0000-0000-0000-000000000000@example.com:443?security=tls&alpn=h2&flow=xtls-rprx-vision#jp'
  'trojan://test-password@example.com:443#trojan'
  'tuic://00000000-0000-0000-0000-000000000000:test-password@example.com:443#tuic'
  'hysteria2://test-password@example.com:443#hy2'
  'hy2://test-password@example.com:443#hy2-short'
  'anytls://test-password@example.com:443#anytls'
)

for index in "${!urls[@]}"; do
  scheme="${schemes[$index]}"
  url="${urls[$index]}"

  assert_equal "$scheme scheme detection" "$scheme" "$(subscription_url_scheme "$url")"

  if ! subscription_url_is_supported "$url"; then
    echo "not ok - $scheme direct share link should be accepted" >&2
    exit 1
  fi
  echo "ok - $scheme direct share link is accepted"

  assert_equal "$scheme format detection" "convert" "$(detect_subscription_format "$url")"
  assert_equal "$scheme display redaction" "$scheme://<redacted>" "$(subscription_url_for_display "$url")"
done

assert_equal \
  "https subscriptions remain direct Clash inputs" \
  "clash" \
  "$(detect_subscription_format 'https://example.com/subscription')"
assert_equal \
  "file subscriptions remain direct Clash inputs" \
  "clash" \
  "$(detect_subscription_format 'file:///tmp/subscription.yaml')"

if subscription_url_is_supported 'vlesss://invalid-scheme'; then
  echo "not ok - unknown share-link-like schemes should remain rejected" >&2
  exit 1
fi
echo "ok - unknown share-link-like schemes remain rejected"

feedback="$(print_add_feedback jp "${urls[1]}")"
if printf '%s\n' "$feedback" | grep -Fq '00000000-0000-0000-0000-000000000000'; then
  echo "not ok - add feedback should not expose share-link credentials" >&2
  exit 1
fi
if ! printf '%s\n' "$feedback" | grep -Fq 'vless://<redacted>'; then
  echo "not ok - add feedback should identify a redacted VLESS link" >&2
  exit 1
fi
echo "ok - add feedback redacts share-link credentials"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
calls_file="$tmp_dir/calls"
sample_url="${urls[1]}"

prepare() { :; }
ensure_add_use_prerequisites() { :; }
ui_progress_line() { :; }
ui_progress_done() { :; }
set_subscription() {
  printf 'set|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$calls_file"
}
set_active_subscription() { printf 'active|%s\n' "$1" >> "$calls_file"; }
apply_runtime_change_after_config_mutation() { printf 'apply\n' >> "$calls_file"; }
print_add_feedback() { printf 'feedback|%s|%s\n' "$1" "$2" >> "$calls_file"; }
cmd_ls() { printf 'list\n' >> "$calls_file"; }

cmd_add "$sample_url" jp

expected_calls="$(printf '%s\n' \
  "set|$sample_url|convert|jp|false" \
  "active|jp" \
  "apply" \
  "feedback|jp|$sample_url" \
  "list")"
assert_equal "clash add preserves and classifies a direct share link" "$expected_calls" "$(cat "$calls_file")"

(
  # Exercise the production converter with only the local subprocess boundary stubbed.
  source "$PROJECT_DIR/scripts/core/config.sh"

  captured_url_file="$tmp_dir/captured-converter-url"
  converter_log_file="$tmp_dir/subconverter.log"
  converter_output_file="$tmp_dir/converted.yaml"

  start_subconverter() { return 0; }
  subconverter_url() { echo "http://127.0.0.1:25500"; }
  subconverter_log_file() { echo "$converter_log_file"; }
  subconverter_running() { return 0; }
  subscription_yaml_validate() { return 0; }
  subscription_yaml_has_no_nodes() { return 1; }
  subscription_cache_store() { :; }
  curl() {
    local output_file="" argument

    while [ "$#" -gt 0 ]; do
      argument="$1"
      case "$argument" in
        --data-urlencode)
          shift
          case "${1:-}" in
            url=*) printf '%s\n' "${1#url=}" > "$captured_url_file" ;;
          esac
          ;;
        -o)
          shift
          output_file="${1:-}"
          ;;
      esac
      shift || true
    done

    printf 'proxies: []\nproxy-groups: []\nrules: []\n' > "$output_file"
    printf '200\nhttp://127.0.0.1:25500/sub?url=credential-bearing-link'
  }

  if ! convert_subscription_via_subconverter \
    "$sample_url" \
    "$converter_output_file" \
    "manual-add" \
    "direct-share-link"; then
    echo "not ok - converter should accept a direct share link" >&2
    exit 1
  fi

  assert_equal \
    "converter receives the complete direct share link" \
    "$sample_url" \
    "$(cat "$captured_url_file")"

  if grep -Fq '00000000-0000-0000-0000-000000000000' "$converter_log_file"; then
    echo "not ok - converter diagnostics should not expose share-link credentials" >&2
    exit 1
  fi
  if ! grep -Fq 'param: url=vless://<redacted>' "$converter_log_file"; then
    echo "not ok - converter diagnostics should identify a redacted VLESS link" >&2
    exit 1
  fi
  echo "ok - converter diagnostics redact share-link credentials"
)

(
  # Re-source the production functions for the failure-path check.
  source "$PROJECT_DIR/scripts/core/config.sh"

  fallback_calls="$tmp_dir/fallback-calls"
  subscription_url_by_name() { printf '%s\n' "$sample_url"; }
  subscription_format_by_name() { echo "convert"; }
  clear_subscription_cache() { :; }
  convert_subscription_via_subconverter() {
    SUBCONVERTER_LAST_ZERO_NODES="true"
    return 1
  }
  download_subscription_yaml() {
    echo "unexpected-download" >> "$fallback_calls"
    return 1
  }
  mark_subscription_health_failure() { printf '%s\n' "$2" > "$tmp_dir/failure-reason"; }
  warn() { :; }

  if fetch_subscription_source jp "$tmp_dir/unused-runtime.yaml" "manual-add"; then
    echo "not ok - a zero-node direct share link should report conversion failure" >&2
    exit 1
  fi

  if [ -e "$fallback_calls" ]; then
    echo "not ok - a direct share link should not enter the Clash YAML download fallback" >&2
    exit 1
  fi

  expected_reason="订阅转换失败：No nodes were found；分享链接无法作为 Clash YAML fallback"
  assert_equal \
    "zero-node share links fail without an invalid download fallback" \
    "$expected_reason" \
    "$(cat "$tmp_dir/failure-reason")"
)
