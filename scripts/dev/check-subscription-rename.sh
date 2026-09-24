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
active: default
sources:
  default:
    type: clash
    url: https://example.invalid/default
    enabled: true
  backup:
    type: clash
    url: https://example.invalid/backup
    enabled: true
EOF

write_subscription_health_value default STATUS success
write_subscription_health_value default FAIL_COUNT 2

rename_subscription default myvps >/dev/null

assert_yq_value() {
  local description="$1"
  local expression="$2"
  local expected="$3"
  local actual

  actual="$("$BIN_DIR/yq" eval "$expression" "$subscriptions")"
  if [ "$actual" != "$expected" ]; then
    echo "not ok - $description: got '$actual', expected '$expected'" >&2
    exit 1
  fi
}

assert_value() {
  local description="$1"
  local actual="$2"
  local expected="$3"

  if [ "$actual" != "$expected" ]; then
    echo "not ok - $description: got '$actual', expected '$expected'" >&2
    exit 1
  fi
}

assert_yq_value "active subscription follows the renamed source" '.active' "myvps"
assert_yq_value "old source is removed" '.sources | has("default")' "false"
assert_yq_value "renamed source keeps its URL" '.sources.myvps.url' "https://example.invalid/default"
assert_value "health status follows the renamed source" "$(read_subscription_health_value myvps STATUS)" "success"
assert_value "health failure count follows the renamed source" "$(read_subscription_health_value myvps FAIL_COUNT)" "2"

assert_value \
  "old subscription health status is cleared" \
  "$(read_subscription_health_value default STATUS 2>/dev/null || true)" \
  ""

echo "ok - active subscription rename migrates source and health state"

cat > "$subscriptions" <<'EOF'
active: default
sources:
  default:
    type: clash
    url: https://example.invalid/default
    enabled: true
  backup:
    type: clash
    url: https://example.invalid/backup
    enabled: true
EOF

rename_subscription backup archive >/dev/null

assert_yq_value "unrelated active subscription is unchanged" '.active' "default"
assert_yq_value "renamed non-active source removes its old key" '.sources | has("backup")' "false"
assert_yq_value "renamed non-active source keeps its URL" '.sources.archive.url' "https://example.invalid/backup"

echo "ok - non-active subscription rename preserves the active source"
