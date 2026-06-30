#!/usr/bin/env bash
set -euo pipefail
sed -i 's/\r$//' "$0" 2>/dev/null || true

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$PROJECT_DIR/scripts/core/common.sh"
source "$PROJECT_DIR/scripts/core/runtime.sh"
source "$PROJECT_DIR/scripts/core/config.sh"
source "$PROJECT_DIR/scripts/init/systemd.sh"
source "$PROJECT_DIR/scripts/init/systemd-user.sh"
source "$PROJECT_DIR/scripts/init/script.sh"

init_project_context "$PROJECT_DIR"
guard_unsafe_sudo_auto_install "${1:-}"
load_env_if_exists
migrate_env_legacy_compat_fields "$PROJECT_DIR/.env"
detect_install_scope "${1:-auto}"
ensure_project_not_wsl_windows_mount

ensure_openwrt_install_supported
ensure_required_commands

init_layout
ensure_dashboard_deploy_prerequisites

resolve_geo_assets

resolve_runtime_kernel
resolve_yq
resolve_subconverter

mark_install_environment || true
mark_install_plan || true
mark_install_port_plan || true

install_clashctl_entry
install_clashctl_completion
install_shell_alias_entry
install_runtime_entry
install_local_dashboard_assets
ensure_controller_secret >/dev/null
set_shell_proxy_persist_enabled "false"
prompt_install_tui

ensure_subscription_bootstrap_for_install "default"
prompt_subscription_if_needed

if [ -n "$(subscription_url 2>/dev/null || true)" ]; then
  if generate_config; then
    if [ -n "${INSTALL_PENDING_SUBSCRIPTION_URL:-}" ]; then
      write_env_value "CLASH_SUBSCRIPTION_URL" "$INSTALL_PENDING_SUBSCRIPTION_URL"
    fi
    echo "✨ 订阅已生效"
    post_install_verify
  else
    write_runtime_value "INSTALL_VERIFY_CONFIG_READY" "false"
    write_runtime_value "INSTALL_VERIFY_RUNTIME_READY" "false"
    write_runtime_value "INSTALL_VERIFY_CONTROLLER_READY" "false"

    echo
    echo "❗ 安装未完成：订阅编译失败"
    if [ -n "$(read_build_value "BUILD_LAST_ERROR_SUMMARY" 2>/dev/null || true)" ]; then
      echo "❌ 原因：$(read_build_value "BUILD_LAST_ERROR_SUMMARY" 2>/dev/null || true)"
    fi
    if [ -f "$RUNTIME_DIR/tmp/subscription-invalid-preview.txt" ]; then
      echo "🧾 调试预览：$RUNTIME_DIR/tmp/subscription-invalid-preview.txt"
    fi
    echo "👉 下一步：clashctl doctor"
    echo
    exit 1
  fi
fi

print_install_summary
