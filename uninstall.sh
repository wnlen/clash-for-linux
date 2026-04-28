#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PURGE_RUNTIME="false"
DEV_RESET="false"

for arg in "$@"; do
  case "$arg" in
    --purge-runtime)
      PURGE_RUNTIME="true"
      ;;
    --dev-reset)
      DEV_RESET="true"
      ;;
    *)
      echo "未知参数：$arg" >&2
      echo "用法：bash uninstall.sh [--dev-reset] [--purge-runtime]" >&2
      exit 2
      ;;
  esac
done

# shellcheck source=scripts/core/common.sh
source "$PROJECT_DIR/scripts/core/common.sh"
# shellcheck source=scripts/core/runtime.sh
source "$PROJECT_DIR/scripts/core/runtime.sh"
# shellcheck source=scripts/core/config.sh
source "$PROJECT_DIR/scripts/core/config.sh"
# shellcheck source=scripts/init/systemd.sh
source "$PROJECT_DIR/scripts/init/systemd.sh"
# shellcheck source=scripts/init/systemd-user.sh
source "$PROJECT_DIR/scripts/init/systemd-user.sh"
# shellcheck source=scripts/init/script.sh
source "$PROJECT_DIR/scripts/init/script.sh"

init_project_context "$PROJECT_DIR"
load_env_if_exists
detect_install_scope auto

service_stop || true
remove_runtime_entry || true
remove_clashctl_entry || true
remove_clashctl_completion || true
remove_shell_alias_entry || true
clear_shell_proxy_persist_state || true

if [ "$PURGE_RUNTIME" = "true" ]; then
  rm -rf "$RUNTIME_DIR"
  clear_controller_secret || true
  echo "🗑️ 已删除运行目录：$RUNTIME_DIR"
  echo "🧩 保留内容：项目目录仍在（已清理 controller secret）"
elif [ "$DEV_RESET" = "true" ]; then
  cache_backup_dir="$(mktemp -d)"
  cache_restore_needed="false"
  subscriptions_backup_file="$cache_backup_dir/subscriptions.yaml"
  subscriptions_restore_needed="false"

  if [ -d "$RUNTIME_DIR/cache" ]; then
    cp -a "$RUNTIME_DIR/cache" "$cache_backup_dir/" 2>/dev/null || true
    cache_restore_needed="true"
  fi

  if [ -f "$RUNTIME_DIR/subscriptions.yaml" ]; then
    cp -f "$RUNTIME_DIR/subscriptions.yaml" "$subscriptions_backup_file" 2>/dev/null || true
    subscriptions_restore_needed="true"
  fi

  clean_runtime_state

  if [ "$cache_restore_needed" = "true" ] && [ -d "$cache_backup_dir/cache" ]; then
    mkdir -p "$RUNTIME_DIR"
    rm -rf "$RUNTIME_DIR/cache" 2>/dev/null || true
    mv "$cache_backup_dir/cache" "$RUNTIME_DIR/cache"
  fi

  if [ "$subscriptions_restore_needed" = "true" ] && [ -f "$subscriptions_backup_file" ]; then
    mkdir -p "$RUNTIME_DIR"
    cp -f "$subscriptions_backup_file" "$RUNTIME_DIR/subscriptions.yaml"
  fi

  rm -rf "$cache_backup_dir" 2>/dev/null || true
  clear_controller_secret || true

  echo "🧪 已清理安装状态：$RUNTIME_DIR"
  echo "🧩 保留内容：subscriptions.yaml、下载缓存与项目目录仍在（已清理 controller secret）"
else
  echo "📦 已卸载安装入口，保留运行目录：$RUNTIME_DIR"
  echo "🧩 保留内容：runtime 数据仍在"
fi

echo "✨ 卸载完成"
