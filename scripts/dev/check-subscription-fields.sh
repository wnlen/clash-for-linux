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

  local arch file url
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) file="yq_linux_amd64" ;;
    aarch64|arm64) file="yq_linux_arm64" ;;
    armv7l|armv7*) file="yq_linux_arm" ;;
    *) echo "not ok - unsupported test architecture for yq: $arch" >&2; return 1 ;;
  esac

  url="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${file}"
  curl -fsSL "$url" -o "$target"
  chmod +x "$target"
}

install_test_yq

export PROJECT_DIR
export RUNTIME_DIR="$tmp_dir/runtime"
export BIN_DIR="$tmp_dir/bin"
export LOG_DIR="$tmp_dir/logs"
export CONFIG_DIR="$tmp_dir/config"

# shellcheck source=scripts/core/common.sh
source "$PROJECT_DIR/scripts/core/common.sh"
# shellcheck source=scripts/core/config.sh
source "$PROJECT_DIR/scripts/core/config.sh"

subscriptions="$RUNTIME_DIR/subscriptions.yaml"
cat > "$subscriptions" <<'EOF'
active: 210GB mojie.co
sources:
  default:
    type: clash
    url: https://example.invalid/default
    enabled: true
  210GB mojie.co:
    type: clash
    url: https://example.invalid/mojie
    enabled: true
  a.b c:
    type: clash
    url: https://example.invalid/abc
    enabled: false
EOF

assert_value() {
  local description="$1"
  local actual="$2"
  local expected="$3"

  if [ "$actual" != "$expected" ]; then
    echo "not ok - $description: got '$actual', expected '$expected'" >&2
    exit 1
  fi
}

assert_enabled() {
  local description="$1"
  local name="$2"
  local expected="$3"

  if [ "$expected" = "enabled" ]; then
    subscription_enabled "$name" || {
      echo "not ok - $description: expected enabled, got disabled" >&2
      exit 1
    }
  else
    if subscription_enabled "$name"; then
      echo "not ok - $description: expected disabled, got enabled" >&2
      exit 1
    fi
  fi
}

assert_enabled "plain subscription names keep resolving" "default" "enabled"
assert_enabled "name with spaces and dots is treated as enabled" "210GB mojie.co" "enabled"
assert_enabled "disabled flag is still respected for special names" "a.b c" "disabled"

assert_value \
  "url lookup by name with spaces and dots" \
  "$(subscription_url_by_name "210GB mojie.co")" \
  "https://example.invalid/mojie"

assert_value \
  "format lookup by name with spaces and dots" \
  "$(subscription_format_by_name "a.b c")" \
  "clash"

assert_value \
  "active subscription url resolves for special names" \
  "$(subscription_url)" \
  "https://example.invalid/mojie"

assert_value \
  "active subscription format resolves for special names" \
  "$(subscription_format)" \
  "clash"

verbose_output="$(print_subscription_health_verbose 2>/dev/null || true)"
for want in "210GB mojie.co" "a.b c"; do
  if ! grep -qF "$want" <<<"$verbose_output"; then
    echo "not ok - health verbose listing drops subscription: $want" >&2
    exit 1
  fi
done

if ! grep -qF "enabled       : true" <<<"$verbose_output"; then
  echo "not ok - health verbose listing shows empty enabled for special names" >&2
  exit 1
fi

echo "ok - subscription field lookups survive names with spaces and dots"
