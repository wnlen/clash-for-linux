#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../.." && pwd)"

source "$PROJECT_DIR/scripts/core/common.sh"
source "$PROJECT_DIR/scripts/core/runtime.sh"
source "$PROJECT_DIR/scripts/core/config.sh"
source "$PROJECT_DIR/scripts/core/completion.sh"
source "$PROJECT_DIR/scripts/core/proxy.sh"
source "$PROJECT_DIR/scripts/core/update.sh"
source "$PROJECT_DIR/scripts/core/tui.sh"
source "$PROJECT_DIR/scripts/init/systemd.sh"
source "$PROJECT_DIR/scripts/init/systemd-user.sh"
source "$PROJECT_DIR/scripts/init/script.sh"

usage() {
  cat <<EOF
🐱 Clash 控制台

Usage:
  clashon                        🚀 开启代理
  clashoff                       ⛔ 关闭代理
  clashctl <command>

🚀 Main Path:
  add                            ➕ 添加订阅
  add local                      ➕ 从 runtime/subscriptions 导入本地订阅
  use                            💱 切换订阅
  select                         💫 切换节点

🧩 Config:
  config                         🧩 配置编译管理
  config kernel mihomo|clash     🧩 切换指定内核
  mixin                          🧩 Mixin 配置管理
  relay                          🔗 多跳节点管理
  lan                            🏠 局域网代理管理
  

📦 Subscription:
  config show                    📡 查看当前订阅
  config regen                   🔄 更新当前订阅
  ls                             📜 查看订阅列表
  sub                            📡 订阅高级管理（启用 / 禁用 / 重命名 / 删除）

🕹️  Control:
  tui                            🖥️  TUI 交互式控制台（需要 gum）
  tui install-gum                🧩 安装可选 TUI 依赖 gum
  clashui                        🕹️  查看 Web 控制台
  secret                         🔑 查看或设置 Web 密钥
  lan on|off|status              🏠 开启 / 关闭局域网代理

🧪 Transparent proxy:
  tun                            🧪 Tun 模式管理
  tun doctor                     🩺 诊断环境与运行状态
  tun log/logs                   📜 查看日志

🚀 Lifecycle:
  boot on|off|status             🚦 管理开机代理接管
  boot runtime on|off|status     🚦 仅管理内核开机自启
  boot proxy on|off|status       📜 仅管理开机代理保持
  upgrade                        🚀 升级当前或指定内核
  update                         🔄 更新项目代码
  completion bash|zsh            💡 导出 Shell 补全脚本
  dev reset                      🧪 恢复到安装前状态（保留项目目录和已下载文件）

🩺 Diagnose:
  doctor                         🩺 诊断环境与运行状态
  status                         🔍️ 查看状态总览
  log/logs                       📜 查看日志
  completion                     💡 导出 Bash / Zsh 补全脚本

📌 Advanced Examples:
  clashctl sub list
  clashctl sub enable hk
  clashctl sub disable hk
  clashctl sub rename hk hk-bak
  clashctl sub remove hk

  clashctl relay add 多跳-示例 节点A 节点B --domain example.com
  clashctl relay list

💡 Notes:
  当前编译链固定为 active-only
  只处理当前 active 主订阅
  Tun 模式属于高级能力，开启前建议先执行：clashctl tun doctor

EOF
}

prepare() {
  init_project_context "$PROJECT_DIR"
  load_env_if_exists
  detect_install_scope auto
}

ensure_add_use_prerequisites() {
  if [ ! -x "$(yq_bin)" ]; then
    die_state "依赖未就绪：缺少 yq（$(yq_bin)）" \
              "请先执行 bash install.sh，或运行 clashctl doctor 查看缺失项"
  fi

  if [ ! -d "$RUNTIME_DIR" ]; then
    die_state "运行环境未初始化：缺少 runtime 目录" \
              "请先执行 bash install.sh"
  fi

  if [ ! -d "$CONFIG_DIR" ]; then
    die_state "运行环境未初始化：缺少 config 目录" \
              "请先执行 bash install.sh"
  fi
}

ensure_runtime_ports_ready() {
  local mixed_port controller_port dns_port
  local new_mixed_port="" new_controller_port="" new_dns_port=""
  local changed="false"
  local repair_detail=""

  # 运行中不做端口改写，避免把当前已经跑起来的 runtime 搅乱
  if status_is_running 2>/dev/null; then
    return 0
  fi

  # 当前没有 runtime/config.yaml 时，不在这里修；后面 generate_config 会生成
  [ -s "$RUNTIME_DIR/config.yaml" ] || return 0

  mixed_port="$(runtime_config_mixed_port 2>/dev/null || true)"
  controller_port="$(runtime_config_controller_port 2>/dev/null || true)"
  dns_port="$(runtime_config_dns_port 2>/dev/null || true)"

  if [ -n "${mixed_port:-}" ] && [ "$mixed_port" != "null" ] && is_port_in_use "$mixed_port"; then
    new_mixed_port="$(resolve_free_port 7890 7999)"
    write_env_value "MIXED_PORT" "$new_mixed_port"
    write_runtime_value "INSTALL_PLAN_MIXED_PORT" "$new_mixed_port"
    write_runtime_value "INSTALL_PLAN_MIXED_PORT_AUTO_CHANGED" "true"
    changed="true"
    repair_detail="${repair_detail} mixed-port:${mixed_port}->${new_mixed_port};"
    info "检测到 mixed-port 冲突：${mixed_port} -> ${new_mixed_port}"
  fi

  if [ -n "${controller_port:-}" ] && [ "$controller_port" != "null" ] && is_port_in_use "$controller_port"; then
    new_controller_port="$(resolve_free_port 9000 9199)"
    write_env_value "EXTERNAL_CONTROLLER" "127.0.0.1:${new_controller_port}"
    write_runtime_value "INSTALL_PLAN_CONTROLLER" "127.0.0.1:${new_controller_port}"
    write_runtime_value "INSTALL_PLAN_CONTROLLER_AUTO_CHANGED" "true"
    changed="true"
    repair_detail="${repair_detail} external-controller:${controller_port}->${new_controller_port};"
    info "检测到 external-controller 冲突：${controller_port} -> ${new_controller_port}"
  fi

  if [ -n "${dns_port:-}" ] && [ "$dns_port" != "null" ] && is_port_in_use "$dns_port"; then
    new_dns_port="$(resolve_free_port 1053 1999)"
    write_env_value "CLASH_DNS_PORT" "$new_dns_port"
    write_runtime_value "INSTALL_PLAN_DNS_PORT" "$new_dns_port"
    write_runtime_value "INSTALL_PLAN_DNS_PORT_AUTO_CHANGED" "true"
    changed="true"
    repair_detail="${repair_detail} dns:${dns_port}->${new_dns_port};"
    info "检测到 DNS 端口冲突：${dns_port} -> ${new_dns_port}"
  fi

  if [ "$changed" = "true" ]; then
    mark_runtime_port_repair_result "true" "$repair_detail"
    info "检测到端口占用，正在自动重建运行配置"
    regenerate_config
    success "端口冲突已自动修复"
  else
    mark_runtime_port_repair_result "false" "no-change"
  fi
}

ensure_on_path_ready() {
  load_system_state

  if [ "$SUBSCRIPTION_STATE" = "missing" ]; then
    die_state "当前没有可用订阅" "clashctl add <订阅链接>"
  fi

  if [ ! -s "$RUNTIME_DIR/config.yaml" ]; then
    info "检测到运行配置缺失，正在自动生成"
    regenerate_config || true
    load_system_state
  fi

  if [ ! -s "$RUNTIME_DIR/config.yaml" ] && [ ! -s "$RUNTIME_DIR/config.last.yaml" ]; then
    die_state "当前没有可启动的运行配置" "clashctl doctor"
  fi

  ensure_runtime_ports_ready
}

print_on_feedback() {
  ui_blank
  echo "🐱 已开启代理环境"
  ui_blank
}

cmd_on() {
  local relay_switch
  local relay_switch_file relay_err_file relay_rc
  local system_proxy_rc system_proxy_degraded="false"

  trap 'rc=$?; ui_error "开启代理失败：cmd_on 在第 ${LINENO} 行执行失败：${BASH_COMMAND}（返回码：${rc}）"; ui_next "clashctl logs service"; exit "$rc"' ERR

  prepare

  # fast path 1：代理已经完整开启
  if status_is_running 2>/dev/null \
    && proxy_controller_reachable 2>/dev/null \
    && [ "$(system_proxy_status 2>/dev/null || echo off)" = "on" ] \
    && system_proxy_matches_runtime 2>/dev/null; then
    print_on_feedback
    trap - ERR
    return 0
  fi

  # fast path 2：runtime 已运行，只是系统代理被关了
  if status_is_running 2>/dev/null \
    && proxy_controller_reachable 2>/dev/null; then
    system_proxy_enable || true
    print_on_feedback
    trap - ERR
    return 0
  fi

  ensure_on_path_ready

  if status_is_running 2>/dev/null && ! proxy_controller_reachable 2>/dev/null; then
    ui_warn "检测到内核已运行但控制器不可访问，正在重启以加载当前配置"
    service_restart || die_state "控制器启动失败：内核重启未完成" "clashctl logs mihomo"
  else
    service_start || die_state "控制器启动失败：内核启动未完成" "clashctl logs mihomo"
  fi

  if ! wait_runtime_controller_ready 8; then
    ui_warn "控制器未在预期时间内可访问，正在重启内核重试"
    service_restart || die_state "控制器启动失败：内核重启未完成" "clashctl logs mihomo"
    if ! wait_runtime_controller_ready 8; then
      status_is_running 2>/dev/null || die_state "控制器启动失败：内核未运行" "clashctl logs mihomo"
      ui_warn "控制器暂不可访问，继续开启本地代理；请稍后执行 clashctl doctor"
    fi
  fi

  if proxy_controller_reachable 2>/dev/null; then
    relay_switch=""
    relay_switch_file="$RUNTIME_DIR/.relay-switch.$$"
    relay_err_file="$LOG_DIR/relay-switch.err"
    mkdir -p "$LOG_DIR"
    : > "$relay_err_file"
    if ensure_default_proxy_group_relay_selected >"$relay_switch_file" 2>"$relay_err_file"; then
      if [ -s "$relay_switch_file" ]; then
        IFS= read -r relay_switch < "$relay_switch_file" || relay_switch=""
      fi
    else
      relay_rc=$?
      relay_switch=""
    fi
    rm -f "$relay_switch_file" 2>/dev/null || true
  fi

  if system_proxy_enable; then
    system_proxy_degraded="false"
  else
    system_proxy_rc=$?
    system_proxy_degraded="true"
    write_runtime_value "RUNTIME_BOOT_PROXY_KEEP" "false" 2>/dev/null || true

    if [ "$system_proxy_rc" -eq 2 ]; then
      ui_warn "当前环境不支持系统代理持久接管，仅当前 Shell 生效"
      ui_next "开机代理保持不可用；如需持久接管，请使用可写的 $(system_proxy_env_file)"
    else
      ui_warn "系统代理持久接管写入失败，仅当前 Shell 生效"
      ui_next "clashctl doctor"
    fi
  fi

  load_system_state
  print_on_feedback

  if [ "${CLASH_ALIAS_CALL:-0}" != "1" ]; then
    if [ "$system_proxy_degraded" = "true" ]; then
      ui_warn "当前通过 clashctl 子进程执行，不能修改当前 Shell 代理变量"
    else
      ui_warn "当前通过 clashctl 子进程执行，已开启系统代理，但不会修改当前终端的 Shell 变量"
    fi
    ui_next "当前终端如需立即生效：重新打开终端后使用 clashon，或手动 source shell 入口"
    ui_blank
  fi

  if [ "$RUNTIME_STATE" = "degraded" ]; then
    ui_warn "代理内核已启动，但控制器暂不可访问"
    ui_next "clashctl doctor"
    ui_blank
  fi

  trap - ERR
  return 0
}

cmd_off() {
  local system_proxy_rc stop_rc
  local system_proxy_state_before system_proxy_cleanup_blocked="false"

  prepare

  system_proxy_state_before="$(system_proxy_status 2>/dev/null || echo off)"

  if system_proxy_disable; then
    :
  else
    system_proxy_rc=$?
    write_runtime_value "RUNTIME_BOOT_PROXY_KEEP" "false" 2>/dev/null || true

    if [ "$system_proxy_state_before" = "on" ]; then
      system_proxy_cleanup_blocked="true"
      if [ "$system_proxy_rc" -eq 2 ]; then
        ui_warn "当前环境不支持清理系统代理持久块，已继续关闭运行时"
      else
        ui_warn "系统代理持久块清理失败，已继续关闭运行时"
        ui_next "clashctl doctor"
      fi
    fi
  fi

  if status_is_running 2>/dev/null; then
    stop_rc=0
    service_stop || stop_rc=$?
    if [ "$stop_rc" -ne 0 ]; then
      die_state "关闭运行时失败：运行后端 stop 返回 ${stop_rc}" "clashctl logs"
    fi

    if ! wait_runtime_stopped 8; then
      die_state "关闭运行时失败：代理内核仍在运行" "clashctl logs"
    fi
  fi

  if [ "$system_proxy_cleanup_blocked" = "true" ]; then
    die_state "系统代理持久块未清理：$(system_proxy_env_file)" "请使用有权限的用户执行 clashctl off，或手动清理该文件中的 clash-for-linux 代理块"
  fi

  ui_blank
  echo "🧹 代理已关闭"
  ui_blank
}

wait_runtime_stopped() {
  local timeout="${1:-8}"
  local elapsed=0

  while status_is_running 2>/dev/null; do
    [ "$elapsed" -lt "$timeout" ] || return 1
    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 0
}

ui_internal_url() {
  local controller host port
  controller="${1:-}"
  [ -n "${controller:-}" ] || controller="$(status_read_controller_raw 2>/dev/null || true)"

  [ -n "${controller:-}" ] && [ "$controller" != "null" ] || return 1
  host="${controller%:*}"
  port="${controller##*:}"

  if [ "${host:-}" = "0.0.0.0" ]; then
    host="127.0.0.1"
  fi

  host="$(url_host_bracket_if_needed "$host")"
  echo "http://${host}:${port}/ui"
}

ui_public_url() {
  local ip port
  ip="$(ui_public_ip 2>/dev/null || true)"
  port="${1:-}"
  [ -n "${port:-}" ] || port="$(ui_controller_port 2>/dev/null || true)"

  [ -n "${ip:-}" ] || return 1
  [ -n "${port:-}" ] || return 1

  ip="$(url_host_bracket_if_needed "$ip")"
  echo "http://${ip}:${port}/ui"
}

ui_lan_url() {
  local ip port
  ip="$(ui_lan_ip 2>/dev/null || true)"
  port="${1:-}"
  [ -n "${port:-}" ] || port="$(ui_controller_port 2>/dev/null || true)"

  [ -n "${ip:-}" ] || return 1
  [ -n "${port:-}" ] || return 1

  ip="$(url_host_bracket_if_needed "$ip")"
  echo "http://${ip}:${port}/ui"
}

cmd_ui() {
  local controller_addr="" controller_raw=""
  local internal_url="" lan_url="" public_url=""
  local current_secret="" controller_port="" controller_status=""

  prepare
  runtime_config_exists || die "🧩 运行时配置不存在，请先生成配置"

  controller_raw="$(status_read_controller_raw 2>/dev/null || true)"
  controller_addr="$(display_controller_local_addr "$controller_raw" 2>/dev/null || echo "$controller_raw")"
  [ -n "${controller_addr:-}" ] && [ "$controller_addr" != "null" ] || die_state "未解析到控制器地址" "clashctl doctor"

  controller_port="${controller_raw##*:}"
  internal_url="$(ui_internal_url "$controller_raw" 2>/dev/null || true)"
  if controller_externally_reachable 2>/dev/null; then
    lan_url="$(ui_lan_url "$controller_port" 2>/dev/null || true)"
    public_url="$(ui_public_url "$controller_port" 2>/dev/null || true)"
  fi
  current_secret="$(controller_secret 2>/dev/null || true)"

  if [ -z "${current_secret:-}" ] || [ "$current_secret" = "null" ]; then
    current_secret="未设置"
  fi

  if status_is_running; then
    if proxy_controller_reachable 2>/dev/null; then
      controller_status="可访问"
    else
      controller_status="不可访问"
    fi
  else
    controller_status="未运行"
  fi

  cmd_ui_box \
    "$controller_status" \
    "$internal_url" \
    "$lan_url" \
    "$public_url" \
    "$current_secret" \
    "$controller_port"

  cmd_ui_help_summary

  if [ "${CLASH_UI_BOX_ONLY:-0}" = "1" ]; then
    return 0
  fi

  case "$controller_status" in
    可访问)
      return 0
      ;;
    不可访问)
      ui_warn "控制器当前不可访问"
      ui_next "clashctl doctor"
      ui_blank
      return 1
      ;;
    未运行)
      ui_warn "当前代理未启动"
      ui_next "clashon"
      ui_blank
      return 1
      ;;
    *)
      ui_warn "控制器状态未知"
      ui_next "clashctl doctor"
      ui_blank
      return 1
      ;;
  esac
}

status_build_active_source() {
  read_build_value "BUILD_ACTIVE_SOURCE" 2>/dev/null || true
}

status_build_active_sources() {
  local value

  value="$(read_build_value "BUILD_ACTIVE_SOURCES" 2>/dev/null || true)"
  if [ -n "${value:-}" ]; then
    echo "$value"
    return 0
  fi

  # 兼容历史 build.env
  read_build_value "BUILD_INCLUDED_SOURCES" 2>/dev/null || true
}

status_build_failed_active_sources() {
  local value
  value="$(read_build_value "BUILD_FAILED_ACTIVE_SOURCES" 2>/dev/null || true)"
  if [ -n "${value:-}" ]; then
    echo "$value"
    return 0
  fi
  # 兼容历史 build.env
  read_build_value "BUILD_FAILED_SOURCES" 2>/dev/null || true
}

status_build_last_status() {
  read_build_value "BUILD_LAST_STATUS" 2>/dev/null || true
}

status_build_last_time() {
  read_build_value "BUILD_LAST_TIME" 2>/dev/null || true
}

status_runtime_last_active_switch_from() {
  read_runtime_event_value "RUNTIME_LAST_ACTIVE_SWITCH_FROM" 2>/dev/null || true
}

status_runtime_last_active_switch_to() {
  read_runtime_event_value "RUNTIME_LAST_ACTIVE_SWITCH_TO" 2>/dev/null || true
}

status_runtime_last_active_switch_time() {
  read_runtime_event_value "RUNTIME_LAST_ACTIVE_SWITCH_TIME" 2>/dev/null || true
}

status_runtime_last_build_block_reason() {
  read_runtime_event_value "RUNTIME_LAST_BUILD_BLOCK_REASON" 2>/dev/null || true
}

status_runtime_last_build_block_time() {
  read_runtime_event_value "RUNTIME_LAST_BUILD_BLOCK_TIME" 2>/dev/null || true
}

status_runtime_config_source() {
  read_runtime_event_value "RUNTIME_LAST_CONFIG_SOURCE" 2>/dev/null || true
}

status_runtime_config_source_time() {
  read_runtime_event_value "RUNTIME_LAST_CONFIG_SOURCE_TIME" 2>/dev/null || true
}

status_runtime_build_applied() {
  read_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED" 2>/dev/null || true
}

status_runtime_build_applied_time() {
  read_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED_TIME" 2>/dev/null || true
}

status_runtime_build_applied_reason() {
  read_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED_REASON" 2>/dev/null || true
}

status_tun_enabled() {
  tun_enabled 2>/dev/null || echo false
}

status_tun_stack() {
  tun_stack 2>/dev/null || echo system
}

status_tun_container_mode() {
  tun_container_mode 2>/dev/null || echo unknown
}

status_tun_container_mode_text() {
  tun_container_mode_text 2>/dev/null || echo 未知
}

status_tun_kernel_support_level() {
  tun_kernel_support_level 2>/dev/null || echo unknown
}

status_tun_kernel_support_text() {
  tun_kernel_support_text 2>/dev/null || echo 未知
}

status_tun_last_verify_result() {
  read_tun_last_verify_result 2>/dev/null || true
}

status_tun_last_verify_reason() {
  read_tun_last_verify_reason 2>/dev/null || true
}

status_tun_last_verify_time() {
  read_tun_last_verify_time 2>/dev/null || true
}

status_tun_last_action() {
  read_tun_last_action 2>/dev/null || true
}

status_tun_last_action_result() {
  read_tun_last_action_result 2>/dev/null || true
}

status_tun_last_action_reason() {
  read_tun_last_action_reason 2>/dev/null || true
}

status_tun_last_action_time() {
  read_tun_last_action_time 2>/dev/null || true
}

status_tun_effective_status() {
  local enabled result

  enabled="$(status_tun_enabled)"

  if [ "$enabled" != "true" ]; then
    echo "off"
    return 0
  fi

  result="$(tun_effective_check 2>/dev/null || true)"
  case "${result:-unknown}" in
    ok)
      echo "effective"
      ;;
    *)
      echo "ineffective"
      ;;
  esac
}

status_tun_effective_text() {
  local s
  s="$(status_tun_effective_status)"

  case "$s" in
    effective) echo "🐱 已生效" ;;
    *) echo "❗ 未生效" ;;
  esac
}

system_state_build_status() {
  local last_status
  local block_reason

  last_status="$(status_build_last_status 2>/dev/null || true)"
  block_reason="$(status_runtime_last_build_block_reason 2>/dev/null || true)"

  if [ -n "${block_reason:-}" ]; then
    echo "blocked"
    return 0
  fi

  case "${last_status:-}" in
    success) echo "success" ;;
    failed) echo "failed" ;;
    *) echo "unknown" ;;
  esac
}

status_build_effective_status() {
  system_state_build_status 2>/dev/null || true
}

runtime_mixed_port_bind_failure_line() {
  local log_file="$LOG_DIR/mihomo.out.log"
  local mixed_port line

  runtime_config_exists 2>/dev/null || return 1
  status_is_running 2>/dev/null && return 1
  [ -f "$log_file" ] || return 1

  mixed_port="$(status_read_mixed_port 2>/dev/null || true)"
  if [ -n "${mixed_port:-}" ] && [ "$mixed_port" != "null" ]; then
    line="$(grep -Ei "Start Mixed.*server error: listen tcp .*:${mixed_port}:.*(operation not permitted|permission denied|address already in use)" "$log_file" 2>/dev/null | tail -n 1 || true)"
  fi

  if [ -z "${line:-}" ]; then
    line="$(grep -Ei 'Start Mixed.*server error: listen tcp .*:.*(operation not permitted|permission denied|address already in use)' "$log_file" 2>/dev/null | tail -n 1 || true)"
  fi

  [ -n "${line:-}" ] || return 1
  printf '%s\n' "$line"
}

runtime_mixed_port_bind_failure_kind() {
  local line lower

  line="$(runtime_mixed_port_bind_failure_line 2>/dev/null || true)"
  [ -n "${line:-}" ] || return 1

  lower="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *"address already in use"*)
      echo "address_in_use"
      ;;
    *"operation not permitted"*|*"permission denied"*)
      echo "bind_denied"
      ;;
    *)
      echo "bind_failed"
      ;;
  esac
}

runtime_mixed_port_bind_failure_text() {
  case "$(runtime_mixed_port_bind_failure_kind 2>/dev/null || true)" in
    address_in_use) echo "mixed-port 端口被占用" ;;
    bind_denied) echo "mixed-port 绑定被拒绝" ;;
    bind_failed) echo "mixed-port 绑定失败" ;;
    *) return 1 ;;
  esac
}

runtime_mixed_port_bind_failure_port() {
  local port line

  port="$(status_read_mixed_port 2>/dev/null || true)"
  if [ -n "${port:-}" ] && [ "$port" != "null" ]; then
    echo "$port"
    return 0
  fi

  line="$(runtime_mixed_port_bind_failure_line 2>/dev/null || true)"
  [ -n "${line:-}" ] || return 1

  printf '%s\n' "$line" | grep -Eo ':[0-9]+:' | tail -n 1 | tr -d ':'
}

runtime_mihomo_log_port_listened() {
  local keyword="$1"
  local port="$2"
  local log_file="$LOG_DIR/mihomo.out.log"
  local line

  [ -n "${keyword:-}" ] || return 1
  [ -n "${port:-}" ] || return 1
  [ -f "$log_file" ] || return 1

  line="$(grep -Ei "(${keyword}).*(listen|listening|start|started).*[:.]${port}([^0-9]|$)|[:.]${port}([^0-9]|$).*(listen|listening|start|started).*(${keyword})" "$log_file" 2>/dev/null | tail -n 1 || true)"
  [ -n "${line:-}" ]
}

runtime_mixed_port_controller_listening() {
  local port

  proxy_controller_reachable 2>/dev/null && return 0

  port="$(runtime_config_controller_port 2>/dev/null || true)"
  [ -n "${port:-}" ] || return 1

  runtime_mihomo_log_port_listened "RESTful API|controller" "$port"
}

runtime_mixed_port_dns_listening() {
  local port

  port="$(runtime_config_dns_port 2>/dev/null || true)"
  [ -n "${port:-}" ] || return 1

  runtime_mihomo_log_port_listened "DNS|dns" "$port" && return 0
  status_is_running 2>/dev/null && is_port_in_use "$port"
}

mixed_port_bind_environment_text() {
  local scope backend container

  scope="$(install_env_scope 2>/dev/null || true)"
  [ -n "${scope:-}" ] || scope="${INSTALL_SCOPE:-unknown}"

  backend="$(runtime_backend 2>/dev/null || true)"
  [ -n "${backend:-}" ] || backend="$(install_plan_backend 2>/dev/null || true)"
  [ -n "${backend:-}" ] || backend="unknown"

  container="$(container_env_type 2>/dev/null || true)"
  [ -n "${container:-}" ] || container="$(install_env_container 2>/dev/null || true)"
  [ -n "${container:-}" ] || container="unknown"

  echo "安装范围 ${scope}，后端 ${backend}，容器环境 ${container}"
}

mixed_port_bind_observation_line() {
  local port dns_port

  port="$(runtime_mixed_port_bind_failure_port 2>/dev/null || status_read_mixed_port 2>/dev/null || true)"
  dns_port="$(runtime_config_dns_port 2>/dev/null || true)"

  if runtime_mixed_port_controller_listening 2>/dev/null; then
    echo "配置已加载，控制器已启动，仅代理端口 ${port:-unknown} 绑定失败；不是订阅/配置主链失败"
  fi

  if [ -n "${dns_port:-}" ] && runtime_mixed_port_dns_listening 2>/dev/null; then
    echo "DNS 端口 ${dns_port} 已监听，可先聚焦 mixed-port"
  fi
}

mixed_port_bind_recommendation_emit() {
  local style="$1"
  local number="$2"
  local text="$3"

  case "$style" in
    numbered)
      echo "${number}. ${text}"
      ;;
    icon)
      echo "💡 ${text}"
      ;;
    *)
      echo "$text"
      ;;
  esac
}

mixed_port_bind_recommendation_lines() {
  local style="${1:-icon}"
  local kind port env_text n line

  kind="$(runtime_mixed_port_bind_failure_kind 2>/dev/null || true)"
  [ -n "${kind:-}" ] || return 1

  port="$(runtime_mixed_port_bind_failure_port 2>/dev/null || status_read_mixed_port 2>/dev/null || true)"
  env_text="$(mixed_port_bind_environment_text 2>/dev/null || echo "当前环境")"
  n=1

  while IFS= read -r line; do
    [ -n "${line:-}" ] || continue
    mixed_port_bind_recommendation_emit "$style" "$n" "$line"
    n=$((n + 1))
  done <<EOF
$(mixed_port_bind_observation_line 2>/dev/null || true)
EOF

  case "$kind" in
    bind_denied)
      mixed_port_bind_recommendation_emit "$style" "$n" "当前 ${env_text} 对端口 ${port:-unknown} 的可绑定性受限；优先修改 .env 中 MIXED_PORT 后执行 clashctl config regen"
      n=$((n + 1))
      ;;
    address_in_use)
      mixed_port_bind_recommendation_emit "$style" "$n" "mixed-port ${port:-unknown} 存在端口冲突；先检查占用进程，或修改 .env 中 MIXED_PORT 后执行 clashctl config regen"
      n=$((n + 1))
      ;;
    *)
      mixed_port_bind_recommendation_emit "$style" "$n" "mixed-port ${port:-unknown} 绑定失败；先查看内核日志确认端口错误"
      n=$((n + 1))
      ;;
  esac

  mixed_port_bind_recommendation_emit "$style" "$n" "保留日志线索：clashctl logs mihomo"
}

mixed_port_bind_next_action() {
  local kind port

  kind="$(runtime_mixed_port_bind_failure_kind 2>/dev/null || true)"
  port="$(runtime_mixed_port_bind_failure_port 2>/dev/null || status_read_mixed_port 2>/dev/null || true)"

  case "$kind" in
    bind_denied)
      echo "修改 .env 中 MIXED_PORT 后执行 clashctl config regen"
      ;;
    address_in_use)
      echo "检查 ${port:-mixed-port} 占用，或修改 .env 中 MIXED_PORT 后执行 clashctl config regen"
      ;;
    bind_failed)
      echo "clashctl logs mihomo"
      ;;
    *)
      return 1
      ;;
  esac
}

system_state_runtime_status() {
  if status_is_running; then
    if proxy_controller_reachable 2>/dev/null; then
      echo "running"
    else
      echo "degraded"
    fi
  else
    echo "stopped"
  fi
}

system_state_subscription_status() {
  local active

  active="$(active_subscription_name 2>/dev/null || true)"

  if [ -z "${active:-}" ]; then
    echo "missing"
    return 0
  fi

  if ! subscription_exists "$active"; then
    echo "invalid"
    return 0
  fi

  if ! subscription_enabled "$active"; then
    echo "disabled"
    return 0
  fi

  case "$(subscription_health_status "$active" 2>/dev/null || echo unknown)" in
    success) echo "healthy" ;;
    failed) echo "degraded" ;;
    *) echo "unknown" ;;
  esac
}

system_state_risk_level() {
  local risk

  if runtime_mixed_port_bind_failure_kind >/dev/null 2>&1; then
    echo "high"
    return 0
  fi

  if status_is_running 2>/dev/null && ! proxy_controller_reachable 2>/dev/null; then
    echo "high"
    return 0
  fi

  if ! runtime_config_exists 2>/dev/null; then
    echo "high"
    return 0
  fi

  risk="$(calculate_runtime_risk_level 2>/dev/null || true)"

  case "${risk:-unknown}" in
    low|medium|high|critical)
      echo "$risk"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

system_state_summary() {
  local runtime_status build_status subscription_status risk_level
  local config_source fallback_used build_applied
  local tun_enabled tun_effective tun_container_mode tun_kernel_support
  local bind_failure_kind overall

  runtime_status="$(system_state_runtime_status)"
  build_status="$(system_state_build_status)"
  subscription_status="$(system_state_subscription_status)"
  risk_level="$(system_state_risk_level)"
  config_source="$(status_runtime_config_source)"
  fallback_used="$(runtime_last_fallback_used 2>/dev/null || true)"
  build_applied="$(status_runtime_build_applied)"
  bind_failure_kind="$(runtime_mixed_port_bind_failure_kind 2>/dev/null || true)"

  tun_enabled="$(status_tun_enabled)"
  tun_effective="$(status_tun_effective_status)"
  tun_container_mode="$(status_tun_container_mode)"
  tun_kernel_support="$(status_tun_kernel_support_level)"

  if [ "$runtime_status" = "running" ] \
    && [ "$build_status" = "success" ] \
    && [ "$subscription_status" = "healthy" ]; then
    overall="ready"
  elif [ "$runtime_status" = "stopped" ] && [ -n "${bind_failure_kind:-}" ]; then
    overall="broken"
  elif [ "$runtime_status" = "stopped" ]; then
    overall="stopped"
  elif [ "$build_status" = "failed" ] || [ "$build_status" = "blocked" ] || [ "$subscription_status" = "invalid" ] || [ "$subscription_status" = "missing" ]; then
    overall="broken"
  else
    overall="degraded"
  fi

  cat <<EOF
SYSTEM_STATE=$overall
RUNTIME_STATE=$runtime_status
BUILD_STATE=$build_status
SUBSCRIPTION_STATE=$subscription_status
RISK_LEVEL=$risk_level
BIND_FAILURE_STATE=${bind_failure_kind:-none}
CONFIG_SOURCE=${config_source:-unknown}
FALLBACK_USED=${fallback_used:-false}
BUILD_APPLIED=${build_applied:-unknown}
TUN_ENABLED=${tun_enabled:-false}
TUN_EFFECTIVE=${tun_effective:-unknown}
TUN_CONTAINER_MODE=${tun_container_mode:-unknown}
TUN_KERNEL_SUPPORT=${tun_kernel_support:-unknown}
EOF
}
load_system_state() {
  eval "$(system_state_summary)"
}

system_state_connectivity_text() {
  load_system_state

  case "$SYSTEM_STATE" in
    ready)
      echo "可用（本地代理已就绪）"
      ;;
    degraded)
      if [ "$RUNTIME_STATE" = "running" ]; then
        echo "异常（内核已运行，但部分能力异常）"
      else
        echo "异常（系统处于降级状态）"
      fi
      ;;
    stopped)
      echo "未连接（代理未启动）"
      ;;
    broken)
      if [ "${BIND_FAILURE_STATE:-none}" != "none" ]; then
        echo "不可用（mixed-port 绑定失败）"
      else
        echo "不可用（配置或订阅异常）"
      fi
      ;;
    *)
      echo "未知"
      ;;
  esac
}

system_state_risk_text() {
  load_system_state

  case "$RISK_LEVEL" in
    low) echo "🐱 低" ;;
    medium) echo "🟡 中" ;;
    high) echo "🟠 高" ;;
    critical) echo "❗ 严重" ;;
    *) echo "⚪ 未知" ;;
  esac
}

system_state_default_action() {
  load_system_state

  case "$SYSTEM_STATE" in
    stopped)
      if [ "${BIND_FAILURE_STATE:-none}" != "none" ]; then
        mixed_port_bind_next_action 2>/dev/null || echo "clashctl logs mihomo"
        return 0
      fi

      if [ "$SUBSCRIPTION_STATE" = "missing" ]; then
        echo "clashctl add <订阅链接>"
      else
        echo "clashon"
      fi
      ;;
    broken)
      if [ "${BIND_FAILURE_STATE:-none}" != "none" ]; then
        mixed_port_bind_next_action 2>/dev/null || echo "clashctl logs mihomo"
        return 0
      fi

      if [ "$SUBSCRIPTION_STATE" = "missing" ]; then
        echo "clashctl add <订阅链接>"
      else
        echo "clashctl doctor"
      fi
      ;;
    degraded)
      if [ "$RUNTIME_STATE" = "degraded" ]; then
        echo "clashctl doctor"
      else
        echo "clashctl status --verbose"
      fi
      ;;
    ready)
      echo "clashctl select"
      ;;
    *)
      echo "clashctl status --verbose"
      ;;
  esac
}

system_state_problem_lines() {
  local mixed_port

  load_system_state
  mixed_port="$(runtime_mixed_port_bind_failure_port 2>/dev/null || status_read_mixed_port 2>/dev/null || true)"

  case "$SYSTEM_STATE" in
    ready)
      return 0
      ;;
    stopped)
      if [ "${BIND_FAILURE_STATE:-none}" != "none" ]; then
        echo "• $(runtime_mixed_port_bind_failure_text)${mixed_port:+：${mixed_port}}"
      elif [ "$SUBSCRIPTION_STATE" = "missing" ]; then
        echo "• 当前没有可用订阅"
      else
        echo "• 代理内核未启动"
      fi
      ;;
    degraded)
      [ "$RUNTIME_STATE" = "degraded" ] && echo "• 代理内核已启动，但控制器不可访问"
      [ "$SUBSCRIPTION_STATE" = "degraded" ] && echo "• 当前主订阅健康异常"
      ;;
    broken)
      [ "${BIND_FAILURE_STATE:-none}" != "none" ] && echo "• $(runtime_mixed_port_bind_failure_text)${mixed_port:+：${mixed_port}}"
      [ "$BUILD_STATE" = "failed" ] && echo "• 最近一次编译失败"
      [ "$SUBSCRIPTION_STATE" = "missing" ] && echo "• 当前没有主订阅"
      [ "$SUBSCRIPTION_STATE" = "invalid" ] && echo "• 当前主订阅无效"
      [ "$SUBSCRIPTION_STATE" = "disabled" ] && echo "• 当前主订阅已禁用"
      [ "$BUILD_STATE" = "blocked" ] && echo "• 最近一次编译被阻断"
      ;;
  esac
}

system_state_recommendation_lines() {
  load_system_state

  if [ "${BIND_FAILURE_STATE:-none}" != "none" ]; then
    mixed_port_bind_recommendation_lines numbered
    return 0
  fi

  case "$SYSTEM_STATE" in
    ready)
      echo "1. clashctl select"
      echo "2. clashctl ls"
      ;;
    stopped)
      if [ "$SUBSCRIPTION_STATE" = "missing" ]; then
        echo "1. clashctl add <订阅链接>"
      else
        echo "1. clashon"
        echo "2. clashctl status"
      fi
      ;;
    degraded)
      echo "1. clashctl doctor"
      echo "2. clashctl status --verbose"
      ;;
    broken)
      if [ "$SUBSCRIPTION_STATE" = "missing" ]; then
        echo "1. clashctl add <订阅链接>"
      else
        echo "1. clashctl doctor"
        echo "2. clashctl ls"
      fi
      ;;
    *)
      echo "1. clashctl status --verbose"
      ;;
  esac
}

ui_box_width=47

box_text_width() {
  local text="${1:-}"

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, unicodedata
s = sys.argv[1]
w = 0
for ch in s:
    if unicodedata.combining(ch):
        continue
    if unicodedata.category(ch)[0] == "C":
        continue
    w += 2 if unicodedata.east_asian_width(ch) in ("F", "W") else 1
print(w)' "$text" 2>/dev/null && return 0
  fi

  if command -v python >/dev/null 2>&1; then
    python -c 'import sys, unicodedata
s = sys.argv[1]
w = 0
for ch in s:
    if unicodedata.combining(ch):
        continue
    if unicodedata.category(ch)[0] == "C":
        continue
    w += 2 if unicodedata.east_asian_width(ch) in ("F", "W") else 1
print(w)' "$text" 2>/dev/null && return 0
  fi

  if command -v od >/dev/null 2>&1 && command -v tr >/dev/null 2>&1; then
    local width=0 byte skip=0

    while IFS= read -r byte; do
      [ -n "${byte:-}" ] || continue

      if [ "$skip" -gt 0 ]; then
        skip=$((skip - 1))
        continue
      fi

      if [ "$byte" -lt 32 ] || [ "$byte" -eq 127 ]; then
        continue
      elif [ "$byte" -lt 128 ]; then
        width=$((width + 1))
      elif [ "$byte" -ge 240 ]; then
        width=$((width + 2))
        skip=3
      elif [ "$byte" -ge 224 ]; then
        width=$((width + 2))
        skip=2
      elif [ "$byte" -ge 192 ]; then
        width=$((width + 1))
        skip=1
      fi
    done < <(printf '%s' "$text" | od -An -t u1 | tr -s ' ' '\n')

    echo "$width"
    return 0
  fi

  echo "${#text}"
}

compute_box_width() {
  local max_len=0
  local line line_width

  for line in "$@"; do
    line_width="$(box_text_width "$line")"
    case "${line_width:-}" in
      ''|*[!0-9]*) line_width="${#line}" ;;
    esac
    [ "$line_width" -gt "$max_len" ] && max_len="$line_width"
  done

  ui_box_width=$((max_len + 14))
}

box_border_top() {
  local i
  printf "╔"
  for ((i = 0; i < ui_box_width - 2; i++)); do
    printf "═"
  done
  printf "╗\n"
}

box_border_mid() {
  local i
  printf "╠"
  for ((i = 0; i < ui_box_width - 2; i++)); do
    printf "═"
  done
  printf "╣\n"
}

box_border_bottom() {
  local i
  printf "╚"
  for ((i = 0; i < ui_box_width - 2; i++)); do
    printf "═"
  done
  printf "╝\n"
}

box_center_line() {
  local text="$1"
  local inner_width=$((ui_box_width - 2))
  local text_len
  text_len="$(box_text_width "$text")"
  local left_pad=$(( (inner_width - text_len) / 2 ))
  local right_pad=$(( inner_width - left_pad - text_len ))

  printf "║%*s%s%*s║\n" "$left_pad" "" "$text" "$right_pad" ""
}

box_empty() {
  printf "║%*s║\n" $((ui_box_width-2)) ""
}

box_section_line() {
  local text="$1"
  local inner_width=$((ui_box_width - 2))
  local content="      $text"
  local content_len
  content_len="$(box_text_width "$content")"
  local right_pad=$((inner_width - content_len))

  [ "$right_pad" -lt 0 ] && right_pad=0
  printf "║%s%*s║\n" "$content" "$right_pad" ""
}

box_title_line() {
  box_center_line "$1"
}

status_is_running() {
  local backend pid

  backend="$(runtime_backend)"

  case "$backend" in
    systemd)
      systemctl is-active --quiet "$(service_unit_name)"
      ;;
    systemd-user)
      systemctl --user is-active --quiet "$(service_unit_name)"
      ;;
    script)
      if [ -f "$RUNTIME_DIR/mihomo.pid" ]; then
        pid="$(cat "$RUNTIME_DIR/mihomo.pid" 2>/dev/null || true)"
        [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null
      else
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

apply_runtime_change_after_config_mutation() {
  if status_is_running; then
    info "检测到代理正在运行，正在自动重启以应用新配置"
    service_restart
    success "新配置已自动重启生效"
  else
    info "新配置已写入，当前代理未运行，下次启动自动生效"
  fi
}

print_config_regen_feedback() {
  echo
  echo "🧩 配置已重新生成"
  echo
}

print_config_apply_feedback() {
  local build_status build_applied config_source next_action

  build_status="$(status_build_effective_status 2>/dev/null || true)"
  build_applied="$(status_runtime_build_applied 2>/dev/null || true)"
  config_source="$(status_runtime_config_source 2>/dev/null || true)"
  next_action="$(system_state_default_action 2>/dev/null || echo 'clashctl status')"

  echo
  echo "🧩 配置变更已处理"

  case "${build_status:-unknown}" in
    success)
      echo "🐱 构建结果：success"
      ;;
    failed)
      echo "❗ 构建结果：failed"
      ;;
    blocked)
      echo "🚨 构建结果：blocked"
      ;;
    *)
      echo "⚪ 构建结果：unknown"
      ;;
  esac

  case "${build_applied:-unknown}" in
    true)
      echo "🐱 是否应用：true"
      ;;
    false)
      echo "🚨 是否应用：false"
      ;;
    *)
      echo "⚪ 是否应用：unknown"
      ;;
  esac

  echo "🧩 配置来源：${config_source:-unknown}"
  echo "👉 下一步：$next_action"
  echo
}

main_feedback_runtime_state() {
  if status_is_running; then
    ui_kv "🐱" "运行状态" "已运行"
  else
    ui_kv "❗" "运行状态" "未运行"
  fi
}

main_feedback_build_mode() {
  ui_kv "🧩" "编译模式" "active-only"
}

main_feedback_active_subscription() {
  local active
  active="$(active_subscription_name 2>/dev/null || true)"
  if [ -n "${active:-}" ]; then
    ui_kv "📡" "当前订阅" "$active"
  fi
}

main_feedback_subscription_selected_state() {
  local name="$1"
  local active

  [ -n "${name:-}" ] || return 0

  active="$(active_subscription_name 2>/dev/null || true)"

  if [ "$name" = "$active" ]; then
    echo "✅ 参与状态：当前主订阅"
  else
    echo "📦 参与状态：已保存，但当前未启用"
  fi
}

print_add_feedback() {
  local name="$1"
  local url="${2:-}"

  echo "✔ 已添加订阅并设为当前主订阅：$name"
  [ -n "${url:-}" ] && echo "📡 URL：$url"
  echo "📋 最新订阅列表（clashctl ls）："
}

print_use_context() {
  local active recommended

  active="$(active_subscription_name 2>/dev/null || true)"
  recommended="$(recommended_subscription_name 2>/dev/null || true)"

  ui_title "🔁 切换当前订阅"

  if [ -n "${active:-}" ]; then
    ui_kv "🚩" "当前主订阅" "$active"
  else
    ui_kv "🚩" "当前主订阅" "未设置"
  fi

  if [ -n "${recommended:-}" ] && [ "${recommended:-}" != "${active:-}" ]; then
    ui_kv "💡" "推荐订阅" "$recommended"
  else
    ui_kv "💡" "推荐订阅" "保持当前"
  fi

  ui_blank
}

print_use_feedback() {
  local name="$1" health fail_count enabled_text

  ui_title "🔁 订阅切换完成"

  if [ -n "${name:-}" ]; then
    if subscription_enabled "$name"; then
      enabled_text="enabled"
    else
      enabled_text="disabled"
    fi

    health="$(subscription_health_status "$name" 2>/dev/null || echo "unknown")"
    fail_count="$(subscription_fail_count "$name" 2>/dev/null || echo "0")"

    ui_kv "🚩" "当前主订阅" "$name"
    ui_kv "❤️" "订阅状态" "$enabled_text / $health / fail=$fail_count"
  fi

  main_feedback_build_mode
  main_feedback_runtime_state
  ui_next "clashctl select  选择节点"
  ui_blank
}

print_select_context() {
  local current_proxy

  if ! status_is_running; then
    ui_kv "❗" "代理状态" "未运行"
    ui_next "clashon"
    ui_blank
    return 1
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    ui_kv "❗" "当前节点" "控制器不可访问"
    ui_next "clashctl doctor"
    ui_blank
    return 1
  fi

  if [ "$(proxy_group_count 2>/dev/null || echo 0)" -le 0 ]; then
    ui_kv "❗" "当前节点" "暂无可切换策略组"
    ui_next "clashctl status --verbose"
    ui_blank
    return 1
  fi

  current_proxy="$(status_current_proxy_brief 2>/dev/null || true)"
  if [ -n "${current_proxy:-}" ]; then
    ui_kv "🚀" "当前节点" "$current_proxy"
  else
    ui_kv "🚀" "当前节点" "未知"
  fi

  ui_next "请选择要切换的策略组和节点"
  ui_blank
  return 0
}

print_select_feedback() {
  local group="$1"
  local current

  current="$(proxy_group_current_display "$group" 2>/dev/null || true)"

  ui_title "🚀 节点切换完成"

  if [ -n "${group:-}" ]; then
    ui_kv "📦" "已切换策略组" "$group"
  fi

  if [ -n "${current:-}" ]; then
    ui_kv "🚀" "当前节点" "$current"
  fi

  main_feedback_runtime_state
  ui_next "clashctl status"
  ui_blank
}

print_sub_enable_feedback() {
  local name="$1"
  local health fail_count

  health="$(subscription_health_status "$name" 2>/dev/null || echo "unknown")"
  fail_count="$(subscription_fail_count "$name" 2>/dev/null || echo "0")"

  ui_title "📡 订阅已启用"
  ui_kv "📡" "订阅名称" "$name"
  ui_kv "❤️" "当前健康" "$health / fail=$fail_count"
  main_feedback_build_mode
  main_feedback_runtime_state
  ui_next "clashctl health ${name}"
  ui_blank
}

print_sub_disable_feedback() {
  local name="$1"
  local active

  active="$(active_subscription_name 2>/dev/null || true)"

  ui_title "📡 订阅已禁用"
  ui_kv "📡" "订阅名称" "$name"

  if [ "$name" = "$active" ]; then
    ui_kv "🚨" "当前主订阅" "已被禁用"
    ui_next "clashctl use"
  else
    ui_kv "🧩" "当前主订阅" "${active:-未设置}"
    ui_next "clashctl status"
  fi

  main_feedback_build_mode
  main_feedback_runtime_state
  ui_blank
}

print_sub_rename_feedback() {
  local old_name="$1"
  local new_name="$2"

  ui_title "📡 订阅已重命名"
  ui_kv "📡" "原名称" "$old_name"
  ui_kv "📡" "新名称" "$new_name"
  main_feedback_build_mode
  main_feedback_runtime_state
  ui_next "clashctl ls"
  ui_blank
}

print_sub_remove_feedback() {
  local name="$1"
  local active

  active="$(active_subscription_name 2>/dev/null || true)"

  ui_title "📡 订阅已删除"
  ui_kv "📡" "已删除" "$name"
  ui_kv "🚩" "当前主订阅" "${active:-未设置}"
  main_feedback_build_mode
  main_feedback_runtime_state
  ui_next "clashctl ls"
  ui_blank
}

print_config_kernel_feedback() {
  local kernel="$1"

  ui_title "🚀 运行内核已切换"
  ui_kv "🚀" "当前内核" "$kernel"
  main_feedback_runtime_state
  ui_next "clashctl status"
  ui_blank
}

tun_container_runtime_hint_lines() {
  local env_type os_variant cap_check printed="false"

  env_type="$(container_env_type 2>/dev/null || echo unknown)"
  os_variant="$(install_env_os_variant 2>/dev/null || true)"
  cap_check="$(has_cap_net_admin; echo $?)"

  if [ "$env_type" = "docker" ]; then
    if ! tun_device_exists 2>/dev/null || [ "$cap_check" != "0" ]; then
      echo "👉 当前问题来自容器启动参数；仅在容器内执行 sudo 或切换到 root，无法补齐缺失的 device / capability"
      printed="true"
    fi
  fi

  if ! tun_device_exists 2>/dev/null; then
    if [ "$env_type" = "docker" ]; then
      echo "👉 请重新创建 Docker 容器并挂载 Tun 设备：--device /dev/net/tun"
    else
      echo "👉 请在容器启动时映射 Tun 设备；Docker 示例：--device /dev/net/tun"
    fi
    printed="true"
  fi

  case "$cap_check" in
    0)
      ;;
    2)
      if [ "$env_type" = "docker" ]; then
        echo "👉 当前容器内缺少 capsh，无法确认 CAP_NET_ADMIN；请重点检查启动参数是否包含：--cap-add NET_ADMIN"
      else
        echo "👉 无法确认 CAP_NET_ADMIN（缺少 capsh）；请检查容器启动参数是否授予了该 capability"
      fi
      printed="true"
      ;;
    *)
      if [ "$env_type" = "docker" ]; then
        echo "👉 请重新创建 Docker 容器并增加能力：--cap-add NET_ADMIN"
      else
        echo "👉 请在容器启动时授予网络管理能力；Docker 示例：--cap-add NET_ADMIN"
      fi
      printed="true"
      ;;
  esac

  if ! has_ip_command 2>/dev/null; then
    case "$os_variant" in
      openwrt)
        echo "👉 当前环境缺少 ip 命令；OpenWrt 可安装：opkg update && opkg install ip-full"
        ;;
      *)
        echo "👉 当前环境缺少 ip 命令；Debian/Ubuntu 可安装：apt update && apt install -y iproute2"
        echo "👉 其他发行版请安装提供 ip 命令的 iproute / iproute2 软件包"
        ;;
    esac
    printed="true"
  fi

  [ "$printed" = "true" ]
}

print_tun_container_gate_feedback() {
  local mode="$1"
  local reason="${2:-}"

  echo
  ui_title "🧪 Tun 裁决"

  ui_kv "🚀" "当前内核" "$(runtime_kernel_type 2>/dev/null || echo unknown)"
  ui_kv "🧩" "Tun 支持等级" "$(tun_kernel_support_text 2>/dev/null || echo 未知)"

  case "$mode" in
    host)
      ui_kv "💻" "环境模式" "主机环境"
      ui_kv "🐱" "容器裁决" "允许正常开启"
      ;;
    container-safe)
      ui_kv "💻" "环境模式" "容器环境"
      ui_kv "🚨" "容器裁决" "允许开启，但属于保守通过"
      [ -n "${reason:-}" ] && ui_kv "🚨" "注意事项" "$reason"
      ;;
    container-risky)
      ui_kv "💻" "环境模式" "容器环境"
      ui_kv "❗" "容器裁决" "高风险，已阻断开启"
      [ -n "${reason:-}" ] && ui_kv "❗" "阻断原因" "$reason"
      tun_container_runtime_hint_lines | sed 's/^/  /' || true
      ui_next "查看完整诊断：clashctl tun doctor"
      ui_blank
      ;;
    *)
      ui_kv "⚪" "容器裁决" "未知"
      [ -n "${reason:-}" ] && ui_kv "🚨" "原因" "$reason"
      ;;
  esac

  if ! tun_kernel_is_recommended 2>/dev/null; then
    ui_warn "$(tun_kernel_support_reason 2>/dev/null || echo '当前内核不适合作为 Tun 主支持内核')"
    ui_next "如需最稳妥 Tun 体验，先执行：clashctl config kernel mihomo"
  fi

  if [ "$mode" != "container-risky" ]; then
    ui_next "clashctl tun doctor"
    ui_blank
  fi
}

print_tun_on_feedback() {
  local verify_result kernel stack auto_route auto_redirect
  local status_icon status_text detail

  verify_result="$1"
  kernel="$(runtime_kernel_type 2>/dev/null || echo unknown)"
  stack="$(runtime_config_tun_stack 2>/dev/null || tun_stack 2>/dev/null || echo unknown)"
  auto_route="$(runtime_config_tun_auto_route 2>/dev/null || echo false)"
  auto_redirect="$(runtime_config_tun_auto_redirect 2>/dev/null || echo false)"

  case "$verify_result" in
    ok)
      status_icon="🐱"
      status_text="已生效"
      detail="已通过 Tun 即时验证"
      ;;
    policy-routing-likely-effective)
      status_icon="🐱"
      status_text="已生效"
      if tun_log_tun_source_line >/dev/null 2>&1; then
        detail="已检测到 Tun 适配器、policy routing 与 Tun 源地址流量"
      else
        detail="已检测到 Tun 适配器与 policy routing，建议用 tun doctor 查看完整证据"
      fi
      ;;
    disabled-in-state|disabled-in-runtime-config|tun-disabled|runtime-not-running|controller-unreachable)
      status_icon="❗"
      status_text="未生效"
      detail="即时验证未通过：$verify_result"
      ;;
    *)
      status_icon="🟡"
      status_text="已开启，仍在确认"
      detail="Tun 已开启，但即时验证仍需结合完整证据确认：$verify_result"
      ;;
  esac

  ui_title "🧪 Tun 模式已开启"
  ui_kv "🚀" "当前内核" "${kernel:-unknown}"
  ui_kv "🔧 " "Tun stack" "${stack:-unknown}"
  ui_kv "📜" "auto-route" "${auto_route:-false}"
  ui_kv "📜" "auto-redirect" "${auto_redirect:-false}"
  ui_kv "$status_icon" "当前状态" "$status_text"
  echo "💡 $detail"

  ui_next "查看完整证据：clashctl tun doctor"
  ui_blank
}

print_tun_off_feedback() {
  local verify_result route_dev

  verify_result="$1"
  route_dev="$(default_route_dev 2>/dev/null || true)"

  ui_title "🧪 Tun 模式已关闭"
  ui_kv "🧪" "目标状态" "关闭"

  case "$verify_result" in
    ok)
      ui_kv "🐱" "验证结果" "Tun 已关闭并完成回滚检查"
      [ -n "${route_dev:-}" ] && ui_kv "🌐" "当前默认路由设备" "$route_dev"
      ;;
    *)
      ui_kv "🚨" "验证结果" "Tun 关闭后仍存在残留或运行异常"
      ui_kv "🚨" "原因" "$verify_result"
      ;;
  esac

  ui_next "clashctl tun doctor"
  ui_blank
}

tun_on_verify_result() {
  local result auto_redirect

  result="${1:-unknown}"
  case "$result" in
    ok)
      echo "ok"
      return 0
      ;;
    disabled-in-state|disabled-in-runtime-config|tun-disabled|runtime-not-running|controller-unreachable)
      echo "$result"
      return 0
      ;;
  esac

  auto_redirect="$(runtime_config_tun_auto_redirect 2>/dev/null || echo false)"
  if [ "${auto_redirect:-false}" = "true" ] && tun_has_policy_routing_evidence 2>/dev/null; then
    echo "policy-routing-likely-effective"
    return 0
  fi

  echo "$result"
}

status_subscription_health_summary() {
  local active health fail_count auto_disabled

  active="$(active_subscription_name 2>/dev/null || true)"
  [ -n "${active:-}" ] || return 0

  health="$(subscription_health_status "$active" 2>/dev/null || echo "unknown")"
  fail_count="$(subscription_fail_count "$active" 2>/dev/null || echo "0")"

  if subscription_auto_disabled "$active"; then
    auto_disabled="yes"
  else
    auto_disabled="no"
  fi

  echo "❤️ 健康状态：$health"
  echo "🚨 失败次数：$fail_count"
  echo "🚨 阈值命中：$auto_disabled"

  if [ -n "$(subscription_last_success "$active" 2>/dev/null || true)" ]; then
    echo "🕒 最近成功：$(subscription_last_success "$active" 2>/dev/null || true)"
  fi

  if [ -n "$(subscription_last_failure "$active" 2>/dev/null || true)" ]; then
    echo "🕒 最近失败：$(subscription_last_failure "$active" 2>/dev/null || true)"
  fi
}

status_proxy_summary_lines() {
  print_proxy_groups_status 2>/dev/null | head -n 5 || true
}

status_user_risk_text() {
  system_state_risk_text
}

status_risk_reason_lines() {
  local build_status active controller_ok
  local last_risk_name last_risk_reason last_risk_fail_count last_risk_threshold
  local build_block_reason build_block_time
  local fallback_used fallback_time fallback_reason
  local tun_enabled tun_effective tun_container_mode tun_kernel_support tun_verify_reason
  local tun_action_result tun_action_reason tun_action_time
  local bind_failure_text mixed_port

  build_status="$(status_build_last_status 2>/dev/null || true)"
  active="$(active_subscription_name 2>/dev/null || true)"
  controller_ok="false"
  proxy_controller_reachable 2>/dev/null && controller_ok="true"
  bind_failure_text="$(runtime_mixed_port_bind_failure_text 2>/dev/null || true)"
  mixed_port="$(runtime_mixed_port_bind_failure_port 2>/dev/null || status_read_mixed_port 2>/dev/null || true)"

  build_block_reason="$(status_runtime_last_build_block_reason 2>/dev/null || true)"
  build_block_time="$(status_runtime_last_build_block_time 2>/dev/null || true)"
  fallback_used="$(runtime_last_fallback_used 2>/dev/null || true)"
  fallback_time="$(runtime_last_fallback_time 2>/dev/null || true)"
  fallback_reason="$(runtime_last_fallback_reason 2>/dev/null || true)"
  tun_enabled="$(status_tun_enabled 2>/dev/null || echo false)"
  tun_effective="$(status_tun_effective_status 2>/dev/null || echo unknown)"
  tun_container_mode="$(status_tun_container_mode 2>/dev/null || echo unknown)"
  tun_kernel_support="$(status_tun_kernel_support_level 2>/dev/null || echo unknown)"
  tun_verify_reason="$(status_tun_last_verify_reason 2>/dev/null || true)"
  tun_action_result="$(status_tun_last_action_result 2>/dev/null || true)"
  tun_action_reason="$(status_tun_last_action_reason 2>/dev/null || true)"
  tun_action_time="$(status_tun_last_action_time 2>/dev/null || true)"

  if ! status_is_running; then
    if [ -n "${bind_failure_text:-}" ]; then
      echo "• ${bind_failure_text}${mixed_port:+：${mixed_port}}"
      mixed_port_bind_observation_line | sed 's/^/• /'
    else
      echo "• 代理内核未启动"
    fi
  fi

  if [ "$controller_ok" = "false" ] && status_is_running; then
    echo "• 控制器不可访问"
  fi

  if [ "${build_status:-}" = "failed" ]; then
    echo "• 最近一次编译失败"
  fi

  if [ -n "${build_block_reason:-}" ]; then
    if [ -n "${build_block_time:-}" ]; then
      echo "• 最近一次编译被阻断：${build_block_reason} @ ${build_block_time}"
    else
      echo "• 最近一次编译被阻断：${build_block_reason}"
    fi
  fi

  if [ "${fallback_used:-false}" = "true" ]; then
    if [ -n "${fallback_time:-}" ]; then
      echo "• 最近一次启动触发配置回退：${fallback_time}"
    else
      echo "• 最近一次启动触发配置回退"
    fi
    [ -n "${fallback_reason:-}" ] && echo "• 回退原因：${fallback_reason}"
  fi

  if [ -n "${active:-}" ] && ! active_subscription_enabled 2>/dev/null; then
    echo "• 当前主订阅已禁用或不可用"
  fi

  last_risk_name="$(read_runtime_event_value "RUNTIME_LAST_SUBSCRIPTION_RISK_NAME" 2>/dev/null || true)"
  last_risk_reason="$(read_runtime_event_value "RUNTIME_LAST_SUBSCRIPTION_RISK_REASON" 2>/dev/null || true)"
  last_risk_fail_count="$(read_runtime_event_value "RUNTIME_LAST_SUBSCRIPTION_RISK_FAIL_COUNT" 2>/dev/null || true)"
  last_risk_threshold="$(read_runtime_event_value "RUNTIME_LAST_SUBSCRIPTION_RISK_THRESHOLD" 2>/dev/null || true)"

  if [ -n "${last_risk_name:-}" ] && [ "${last_risk_reason:-}" = "fail-threshold-reached" ]; then
    echo "• 订阅 ${last_risk_name} 连续失败 ${last_risk_fail_count:-?} 次（阈值 ${last_risk_threshold:-?}）"
  fi

  if [ "${tun_action_result:-}" = "failed" ]; then
    if [ -n "${tun_action_time:-}" ]; then
      echo "• 最近一次 Tun 配置同步失败：${tun_action_reason:-unknown} @ ${tun_action_time}"
    else
      echo "• 最近一次 Tun 配置同步失败：${tun_action_reason:-unknown}"
    fi
  fi

  if [ "$tun_enabled" = "true" ] && [ "$tun_effective" != "effective" ]; then
    echo "• Tun 未生效"
  fi

  if [ "$tun_container_mode" = "container-risky" ]; then
    echo "• 当前 Tun 运行环境属于高风险容器场景"
  fi

  if [ "$tun_enabled" = "true" ] && [ "$tun_kernel_support" = "limited" ]; then
    echo "• 当前 Tun 运行在 clash 内核上，仅按降级支持处理"
  fi
}

status_recommendation_lines() {
  system_state_recommendation_lines
}

status_current_proxy_brief() {
  local default_group default_current fallback_group fallback_current
  local bind_failure_text

  if ! status_is_running; then
    bind_failure_text="$(runtime_mixed_port_bind_failure_text 2>/dev/null || true)"
    if [ -n "${bind_failure_text:-}" ]; then
      echo "$bind_failure_text"
      return 0
    fi

    echo "未启动"
    return 0
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    echo "控制器不可访问"
    return 0
  fi

  default_group="$(default_proxy_group_name 2>/dev/null || true)"
  default_current="$(default_proxy_group_current 2>/dev/null || true)"

  if [ -n "${default_group:-}" ]; then
    [ -n "${default_current:-}" ] || default_current="<unknown>"
    echo "${default_group} -> ${default_current}"
    return 0
  fi

  fallback_group="$(proxy_group_list 2>/dev/null | sed -n '1p')"
  if [ -n "${fallback_group:-}" ]; then
    fallback_current="$(proxy_group_current_display "$fallback_group" 2>/dev/null || true)"
    [ -n "${fallback_current:-}" ] || fallback_current="<unknown>"
    echo "${fallback_group} -> ${fallback_current}"
    return 0
  fi

  echo "暂无可切换策略组"
}

system_proxy_supported_state() {
  if system_proxy_supported; then
    echo "true"
  else
    echo "false"
  fi
}

persistent_system_proxy_text() {
  local status

  status="$(system_proxy_status 2>/dev/null || echo off)"
  if [ "$status" = "on" ]; then
    if system_proxy_matches_runtime 2>/dev/null; then
      echo "on"
    else
      echo "mismatch"
    fi
    return 0
  fi

  if ! system_proxy_supported; then
    echo "unsupported"
    return 0
  fi

  echo "off"
}

status_local_proxy_http_url() {
  local port

  port="$(status_read_mixed_port 2>/dev/null || true)"
  [ -n "${port:-}" ] && [ "$port" != "null" ] || return 1

  echo "http://127.0.0.1:${port}"
}

current_process_proxy_env_text() {
  local expected value

  expected="$(status_local_proxy_http_url 2>/dev/null || true)"
  [ -n "${expected:-}" ] || {
    echo "unknown"
    return 0
  }

  value="${http_proxy:-${HTTP_PROXY:-${https_proxy:-${HTTPS_PROXY:-}}}}"
  [ -n "${value:-}" ] || value="${all_proxy:-${ALL_PROXY:-}}"

  if [ -z "${value:-}" ]; then
    echo "off"
  elif [ "$value" = "$expected" ]; then
    echo "on"
  else
    echo "mismatch"
  fi
}

connectivity_issue_code() {
  local active group_count
  local bind_failure_kind

  if ! status_is_running; then
    bind_failure_kind="$(runtime_mixed_port_bind_failure_kind 2>/dev/null || true)"
    case "${bind_failure_kind:-}" in
      bind_denied)
        echo "mixed_port_bind_denied"
        return 0
        ;;
      address_in_use)
        echo "mixed_port_address_in_use"
        return 0
        ;;
      bind_failed)
        echo "mixed_port_bind_failed"
        return 0
        ;;
    esac

    echo "runtime_stopped"
    return 0
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    echo "controller_unreachable"
    return 0
  fi

  case "$(system_state_build_status 2>/dev/null || echo unknown)" in
    failed|blocked)
      echo "config_invalid"
      return 0
      ;;
  esac

  case "$(system_state_subscription_status 2>/dev/null || echo unknown)" in
    missing|invalid|disabled|degraded)
      echo "subscription_unhealthy"
      return 0
      ;;
  esac

  group_count="$(proxy_group_count 2>/dev/null || echo 0)"
  case "${group_count:-0}" in
    ''|*[!0-9]*) group_count=0 ;;
  esac

  if [ "$group_count" -le 0 ]; then
    echo "proxy_control_broken"
    return 0
  fi

  case "$(persistent_system_proxy_text)" in
    on) echo "local_proxy_ready_system_proxy_on" ;;
    unsupported) echo "local_proxy_ready_system_proxy_unsupported" ;;
    mismatch) echo "local_proxy_ready_system_proxy_mismatch" ;;
    off) echo "local_proxy_ready_system_proxy_off" ;;
    *) echo "local_proxy_ready_system_proxy_off" ;;
  esac
}

connectivity_issue_text() {
  local issue port

  issue="$(connectivity_issue_code)"
  port="$(runtime_mixed_port_bind_failure_port 2>/dev/null || status_read_mixed_port 2>/dev/null || true)"

  case "$issue" in
    ok|local_proxy_ready_system_proxy_on) echo "可用（本地代理已就绪，系统代理已接管）" ;;
    mixed_port_bind_denied) echo "不可用（mixed-port ${port:-unknown} 绑定被拒绝）" ;;
    mixed_port_address_in_use) echo "不可用（mixed-port ${port:-unknown} 端口被占用）" ;;
    mixed_port_bind_failed) echo "不可用（mixed-port ${port:-unknown} 绑定失败）" ;;
    runtime_stopped) echo "不可用（代理内核未启动）" ;;
    controller_unreachable) echo "异常（内核已运行，但控制器不可访问）" ;;
    config_invalid) echo "异常（当前运行配置不可用）" ;;
    subscription_unhealthy) echo "异常（当前主订阅不可用）" ;;
    proxy_control_broken) echo "异常（当前无可用策略组或节点控制面异常）" ;;
    system_proxy_unsupported|local_proxy_ready_system_proxy_unsupported) echo "本地代理可用，系统流量未自动接管（系统代理持久写入不可用）" ;;
    system_proxy_off|local_proxy_ready_system_proxy_off) echo "本地代理可用，系统流量未自动接管（系统代理未开启）" ;;
    system_proxy_mismatch|local_proxy_ready_system_proxy_mismatch) echo "本地代理可用，但系统代理端口与当前运行端口不一致" ;;
    *) echo "未知" ;;
  esac
}

connectivity_next_action() {
  case "$(connectivity_issue_code)" in
    ok|local_proxy_ready_system_proxy_on)
      echo "clashctl select"
      ;;
    runtime_stopped)
      echo "clashon"
      ;;
    mixed_port_bind_denied|mixed_port_address_in_use|mixed_port_bind_failed)
      mixed_port_bind_next_action 2>/dev/null || echo "clashctl logs mihomo"
      ;;
    controller_unreachable)
      echo "clashctl doctor"
      ;;
    config_invalid)
      echo "clashctl doctor"
      ;;
    subscription_unhealthy)
      echo "clashctl ls"
      ;;
    proxy_control_broken)
      echo "clashctl status --verbose"
      ;;
    system_proxy_unsupported|local_proxy_ready_system_proxy_unsupported)
      echo "浏览器/应用手动设置代理，或在当前 Shell 使用 clashon"
      ;;
    system_proxy_off|local_proxy_ready_system_proxy_off)
      echo "浏览器/应用手动设置代理，或在当前 Shell 使用 clashon"
      ;;
    system_proxy_mismatch|local_proxy_ready_system_proxy_mismatch)
      echo "clashoff && clashon"
      ;;
    *)
      echo "clashctl doctor"
      ;;
  esac
}

connectivity_evidence_lines() {
  local runtime_running controller_ok build_status subscription_status
  local group_count expected_proxy actual_proxy active config_source
  local system_proxy_state system_proxy_supported_text process_proxy_env mixed_port local_proxy_listening
  local bind_failure_kind bind_failure_line

  if status_is_running; then
    runtime_running="true"
  else
    runtime_running="false"
  fi

  if proxy_controller_reachable 2>/dev/null; then
    controller_ok="true"
  else
    controller_ok="false"
  fi

  build_status="$(system_state_build_status 2>/dev/null || echo unknown)"
  subscription_status="$(system_state_subscription_status 2>/dev/null || echo unknown)"
  group_count="$(proxy_group_count 2>/dev/null || echo 0)"
  active="$(active_subscription_name 2>/dev/null || true)"
  config_source="$(status_runtime_config_source 2>/dev/null || true)"
  expected_proxy="$(status_local_proxy_http_url 2>/dev/null || true)"
  mixed_port="$(status_read_mixed_port 2>/dev/null || true)"
  local_proxy_listening="false"
  if [ -n "${mixed_port:-}" ] && [ "$mixed_port" != "null" ] && is_port_in_use "$mixed_port"; then
    local_proxy_listening="true"
  fi
  actual_proxy="$(system_proxy_http_value 2>/dev/null || true)"
  system_proxy_state="$(persistent_system_proxy_text)"
  system_proxy_supported_text="$(system_proxy_supported_state)"
  process_proxy_env="$(current_process_proxy_env_text)"
  bind_failure_kind="$(runtime_mixed_port_bind_failure_kind 2>/dev/null || true)"
  bind_failure_line="$(runtime_mixed_port_bind_failure_line 2>/dev/null || true)"
  case "${group_count:-0}" in
    ''|*[!0-9]*) group_count=0 ;;
  esac

  echo "• runtime_running = ${runtime_running:-false}"
  echo "• controller_reachable = ${controller_ok:-false}"
  [ -n "${bind_failure_kind:-}" ] && echo "• mixed_port_bind_failure = ${bind_failure_kind}"
  [ -n "${bind_failure_line:-}" ] && echo "• mixed_port_bind_log = ${bind_failure_line}"
  echo "• build_status = ${build_status:-unknown}"
  echo "• subscription_status = ${subscription_status:-unknown}"
  echo "• active_subscription = ${active:-unset}"
  echo "• config_source = ${config_source:-unknown}"
  echo "• proxy_group_count = ${group_count:-0}"

  echo "• local_proxy_listening = ${local_proxy_listening:-false}"
  [ -n "${expected_proxy:-}" ] && echo "• local_proxy_http = $expected_proxy"
  echo "• system_proxy_persistent_supported = ${system_proxy_supported_text:-false}"
  echo "• system_proxy_persistent_status = ${system_proxy_state:-off}"
  echo "• current_process_proxy_env = ${process_proxy_env:-unknown}"
  echo "• runtime_backend = $(runtime_backend 2>/dev/null || echo unknown)"
  echo "• boot_runtime_autostart = $(status_service_autostart_text)"
  echo "• boot_proxy_keep = $(status_boot_proxy_keep_text)"
  [ -n "${actual_proxy:-}" ] && echo "• system_proxy_http = ${actual_proxy}"
  echo "• tun_enabled = $(status_tun_enabled 2>/dev/null || echo false)"
  echo "• tun_effective = $(status_tun_effective_status 2>/dev/null || echo unknown)"
  echo "• tun_container_mode = $(status_tun_container_mode 2>/dev/null || echo unknown)"
  echo "• tun_kernel_support = $(status_tun_kernel_support_level 2>/dev/null || echo unknown)"
}

status_runtime_backend_text() {
  local backend

  backend="$(runtime_backend 2>/dev/null || true)"
  [ -n "${backend:-}" ] || backend="$(install_plan_backend 2>/dev/null || true)"

  case "${backend:-unknown}" in
    systemd) echo "systemd" ;;
    systemd-user) echo "systemd-user" ;;
    script) echo "script" ;;
    *) echo "unknown" ;;
  esac
}

status_runtime_backend_reason_text() {
  local backend container_type

  backend="$(runtime_backend 2>/dev/null || echo unknown)"
  container_type="$(install_env_container 2>/dev/null || echo unknown)"

  case "$backend" in
    systemd)
      echo "root + systemd 可用"
      ;;
    systemd-user)
      echo "普通用户 + user systemd 可用"
      ;;
    script)
      if [ "$container_type" != "host" ] && [ -n "${container_type:-}" ]; then
        echo "容器环境默认回退 script"
      else
        echo "systemd 不可用，自动回退 script"
      fi
      ;;
    *)
      echo "未知"
      ;;
  esac
}

status_service_autostart_text() {
  service_autostart_status 2>/dev/null || echo "unknown"
}

status_boot_proxy_keep_text() {
  boot_proxy_keep_status 2>/dev/null || echo "unknown"
}

status_boot_auto_proxy_text() {
  local runtime_autostart proxy_keep

  runtime_autostart="$(status_service_autostart_text)"
  proxy_keep="$(status_boot_proxy_keep_text)"

  if [ "$runtime_autostart" = "on" ] && [ "$proxy_keep" = "on" ]; then
    echo "on"
  else
    echo "off"
  fi
}

status_boot_boundary_text() {
  local backend proxy_keep text

  backend="$(runtime_backend 2>/dev/null || echo unknown)"
  proxy_keep="$(status_boot_proxy_keep_text)"

  case "$backend" in
    systemd)
      text="systemd 支持内核开机自启；开机代理保持由 /etc/environment 的代理块决定"
      ;;
    systemd-user)
      text="systemd-user 支持用户登录后自启；开机代理保持仍由 /etc/environment 的代理块决定"
      ;;
    script)
      text="script 后端不支持内核开机自启；只能查看或清理系统代理持久块"
      ;;
    *)
      text="未知后端，无法确认开机自启边界"
      ;;
  esac

  if [ "$proxy_keep" = "unsupported" ]; then
    text="${text}；当前环境不可写系统代理持久文件"
  fi

  echo "$text"
}

status_container_mode_text() {
  local container_mode env_container

  container_mode="$(install_plan_container_mode 2>/dev/null || true)"
  env_container="$(install_env_container 2>/dev/null || true)"

  if [ "${container_mode:-}" = "true" ]; then
    echo "容器兼容模式"
    return 0
  fi

  case "${env_container:-host}" in
    host) echo "主机模式" ;;
    "") echo "未知" ;;
    *) echo "容器环境（未启用兼容模式）" ;;
  esac
}

status_install_verify_brief() {
  local runtime_ready controller_ready
  local live_runtime="false"
  local live_controller="false"

  runtime_ready="$(install_verify_runtime_ready 2>/dev/null || true)"
  controller_ready="$(install_verify_controller_ready 2>/dev/null || true)"

  if status_is_running 2>/dev/null; then
    live_runtime="true"
  fi

  if proxy_controller_reachable 2>/dev/null; then
    live_controller="true"
  fi

  if [ "$live_runtime" = "true" ] && [ "$live_controller" = "true" ]; then
    echo "安装验证通过"
    return 0
  fi

  if [ "$runtime_ready" = "true" ] && [ "$controller_ready" = "true" ]; then
    echo "安装验证通过"
    return 0
  fi

  if [ "$live_runtime" = "true" ] && [ "$live_controller" != "true" ]; then
    echo "运行已就绪，控制器未就绪"
    return 0
  fi

  if [ "$runtime_ready" = "true" ] && [ "$controller_ready" != "true" ]; then
    echo "运行已就绪，控制器未就绪"
    return 0
  fi

  if [ "$live_runtime" != "true" ] && [ "$live_controller" = "true" ]; then
    echo "控制器异常记录"
    return 0
  fi

  if [ "$runtime_ready" != "true" ] && [ "$controller_ready" = "true" ]; then
    echo "控制器异常记录"
    return 0
  fi

  echo "安装验证未完成"
}

status_port_adjustment_brief() {
  local changed=0

  [ "$(install_plan_mixed_port_auto_changed 2>/dev/null || echo false)" = "true" ] && changed=1
  [ "$(install_plan_controller_auto_changed 2>/dev/null || echo false)" = "true" ] && changed=1
  [ "$(install_plan_dns_port_auto_changed 2>/dev/null || echo false)" = "true" ] && changed=1

  if [ "$changed" -eq 1 ]; then
    echo "安装期发生过端口自动避让"
  else
    echo "安装期端口保持默认"
  fi
}

print_status_summary_compact() {
  local profile mixed_port controller controller_lan controller_public
  local allow_lan lan_proxy
  local running_text user_connectivity user_risk current_proxy_brief system_proxy_text
  local current_active dashboard_text dashboard_source_text dashboard_policy_text secret_text
  local tun_text bind_failure_text next_action

  profile="$(show_active_profile 2>/dev/null || true)"
  [ -n "${profile:-}" ] || profile="default"

  mixed_port="$(status_read_mixed_port 2>/dev/null || true)"
  allow_lan="$(runtime_config_allow_lan 2>/dev/null || config_allow_lan 2>/dev/null || echo true)"
  controller="$(status_read_controller 2>/dev/null || true)"
  controller_lan="$(status_read_controller_lan 2>/dev/null || true)"
  controller_public="$(status_read_controller_public 2>/dev/null || true)"
  current_active="$(active_subscription_name 2>/dev/null || true)"
  tun_text="$(status_tun_effective_text)"
  bind_failure_text="$(runtime_mixed_port_bind_failure_text 2>/dev/null || true)"

  if status_is_running; then
    running_text="🐱 已开启"
  elif [ -n "${bind_failure_text:-}" ]; then
    running_text="❗ ${bind_failure_text}"
  else
    running_text="❗ 未开启"
  fi

  user_connectivity="$(connectivity_issue_text)"
  user_risk="$(status_user_risk_text)"
  current_proxy_brief="$(status_current_proxy_brief)"
  next_action="$(connectivity_next_action 2>/dev/null || system_state_default_action 2>/dev/null || echo 'clashctl status --verbose')"
  system_proxy_text="$(persistent_system_proxy_text 2>/dev/null || echo unknown)"
  if [ -f "$(runtime_dashboard_dir)/index.html" ]; then
    dashboard_text="已部署"
  else
    dashboard_text="未部署"
  fi
  dashboard_source_text="$(read_runtime_value "DASHBOARD_ASSET_SOURCE" 2>/dev/null || echo none)"
  case "${dashboard_source_text:-none}" in
    dir|zip|none) ;;
    *) dashboard_source_text="none" ;;
  esac
  if [ "$dashboard_source_text" = "none" ]; then
    dashboard_policy_text="默认策略：Dashboard 资产无效将阻断 install/update"
  else
    dashboard_policy_text="默认策略：Dashboard 资产需保持可部署"
  fi
  if [ -n "$(read_env_value "CLASH_CONTROLLER_SECRET" 2>/dev/null || true)" ]; then
    secret_text="已设置"
  else
    secret_text="未设置"
  fi

  echo
  echo "🐱 Clash 状态总览"
  echo

  echo "【当前结果】"
  echo "🐱 代理状态：$running_text"
  echo "🌐 当前可用性：$user_connectivity"
  echo "📡 当前订阅：${current_active:-未设置}"
  echo "🚀 当前节点：$current_proxy_brief"
  echo "🚨 当前风险：$user_risk"
  if [ "$next_action" = "clashctl select" ]; then
    echo "👉 clashctl select  切换节点"
  else
    echo "👉 下一步：$next_action"
  fi
  echo

  echo "【核心入口】"
  echo "🔧 Profile：$profile"
  echo "🔧 运行后端：$(status_runtime_backend_text)"
  echo "🚦 内核开机自启：$(status_service_autostart_text)"
  echo "📜 开机代理保持：$(status_boot_proxy_keep_text)"
  echo "🐱 开机代理接管：$(status_boot_auto_proxy_text)"
  echo "🧪 环境模式：$(status_container_mode_text)"
  echo "🧪 Tun 状态：${tun_text:-未知}"
  echo "📜 系统代理持久接管：${system_proxy_text}"
  echo "🧩 Dashboard：${dashboard_text}（来源：${dashboard_source_text}）"
  echo "🧩 Dashboard 策略：${dashboard_policy_text}"
  echo "🔐 控制器密钥：${secret_text}"

  if [ -n "${mixed_port:-}" ] && [ "$mixed_port" != "null" ]; then
    echo "🌐 本地代理：http://127.0.0.1:${mixed_port}"
    if [ "$allow_lan" = "true" ]; then
      lan_proxy="$(ui_lan_ip 2>/dev/null || true)"
      [ -n "${lan_proxy:-}" ] && echo "🏠 局域网代理：http://${lan_proxy}:${mixed_port}"
    else
      echo "🏠 局域网代理：已关闭"
    fi
  else
    echo "🌐 本地代理：未知"
  fi

  if [ -n "${controller:-}" ] && [ "$controller" != "null" ]; then
    echo "🐱 控制台：http://${controller}/ui"
    [ -n "${controller_lan:-}" ] && echo "🏠 局域网：http://${controller_lan}/ui"
    if [ -n "${controller_public:-}" ]; then
      echo "🌍 公网：http://${controller_public}/ui"
    else
      echo "🌍 公网：需公网 IP / 端口映射后可访问"
    fi
  else
    echo "🐱 控制台：未知"
  fi

  echo
  echo "🧩 安装验证：$(status_install_verify_brief)"
  echo "💡 更多细节：clashctl status --verbose"
  echo
}

print_status_summary_verbose() {
  local running_text profile mixed_port controller controller_lan controller_public
  local allow_lan lan_proxy
  local current_active build_active_sources build_failed_active_sources build_status build_time
  local build_block_reason build_block_time
  local last_switch_from last_switch_to last_switch_time
  local controller_ok current_proxy_lines
  local user_connectivity user_risk current_proxy_brief
  local fallback_used fallback_time fallback_reason
  local config_source config_source_time build_applied build_applied_time build_applied_reason
  local install_backend_text install_container_text install_verify_text port_adjustment_text
  local tun_enabled tun_effective tun_stack tun_container_text tun_kernel_text tun_verify_result tun_verify_reason tun_verify_time
  local system_proxy_text dashboard_text dashboard_source_text dashboard_policy_text secret_text
  local bind_failure_text next_action

  profile="$(show_active_profile 2>/dev/null || true)"
  [ -n "${profile:-}" ] || profile="default"

  mixed_port="$(status_read_mixed_port 2>/dev/null || true)"
  allow_lan="$(runtime_config_allow_lan 2>/dev/null || config_allow_lan 2>/dev/null || echo true)"
  controller="$(status_read_controller 2>/dev/null || true)"
  controller_lan="$(status_read_controller_lan 2>/dev/null || true)"
  controller_public="$(status_read_controller_public 2>/dev/null || true)"


  current_active="$(active_subscription_name 2>/dev/null || true)"
  build_active_sources="$(status_build_active_sources)"
  build_failed_active_sources="$(status_build_failed_active_sources)"
  build_status="$(status_build_last_status)"
  build_time="$(status_build_last_time)"

  build_block_reason="$(status_runtime_last_build_block_reason)"
  build_block_time="$(status_runtime_last_build_block_time)"
  last_switch_from="$(status_runtime_last_active_switch_from)"
  last_switch_to="$(status_runtime_last_active_switch_to)"
  last_switch_time="$(status_runtime_last_active_switch_time)"

  fallback_used="$(runtime_last_fallback_used 2>/dev/null || true)"
  fallback_time="$(runtime_last_fallback_time 2>/dev/null || true)"
  fallback_reason="$(runtime_last_fallback_reason 2>/dev/null || true)"
  config_source="$(status_runtime_config_source 2>/dev/null || true)"
  config_source_time="$(status_runtime_config_source_time 2>/dev/null || true)"
  build_applied="$(status_runtime_build_applied 2>/dev/null || true)"
  build_applied_time="$(status_runtime_build_applied_time 2>/dev/null || true)"
  build_applied_reason="$(status_runtime_build_applied_reason 2>/dev/null || true)"
  bind_failure_text="$(runtime_mixed_port_bind_failure_text 2>/dev/null || true)"

  if status_is_running; then
    running_text="🐱 已开启"
  elif [ -n "${bind_failure_text:-}" ]; then
    running_text="❗ ${bind_failure_text}"
  else
    running_text="❗ 未开启"
  fi

  controller_ok="false"
  current_proxy_lines=""
  if status_is_running && proxy_controller_reachable 2>/dev/null; then
    controller_ok="true"
    current_proxy_lines="$(status_proxy_summary_lines)"
  fi

  user_connectivity="$(connectivity_issue_text)"
  user_risk="$(status_user_risk_text)"
  current_proxy_brief="$(status_current_proxy_brief)"
  next_action="$(connectivity_next_action 2>/dev/null || system_state_default_action 2>/dev/null || echo 'clashctl status --verbose')"
  install_backend_text="$(status_runtime_backend_text)"
  install_container_text="$(status_container_mode_text)"
  install_verify_text="$(status_install_verify_brief)"
  port_adjustment_text="$(status_port_adjustment_brief)"

  tun_enabled="$(status_tun_enabled 2>/dev/null || echo false)"
  tun_effective="$(status_tun_effective_text 2>/dev/null || echo 未知)"
  tun_stack="$(status_tun_stack 2>/dev/null || echo system)"
  tun_container_text="$(status_tun_container_mode_text 2>/dev/null || echo 未知)"
  tun_kernel_text="$(status_tun_kernel_support_text 2>/dev/null || echo 未知)"
  tun_verify_result="$(status_tun_last_verify_result 2>/dev/null || true)"
  tun_verify_reason="$(status_tun_last_verify_reason 2>/dev/null || true)"
  tun_verify_time="$(status_tun_last_verify_time 2>/dev/null || true)"
  system_proxy_text="$(persistent_system_proxy_text 2>/dev/null || echo unknown)"
  if [ -f "$(runtime_dashboard_dir)/index.html" ]; then
    dashboard_text="已部署"
  else
    dashboard_text="未部署"
  fi
  dashboard_source_text="$(read_runtime_value "DASHBOARD_ASSET_SOURCE" 2>/dev/null || echo none)"
  case "${dashboard_source_text:-none}" in
    dir|zip|none) ;;
    *) dashboard_source_text="none" ;;
  esac
  if [ "$dashboard_source_text" = "none" ]; then
    dashboard_policy_text="默认策略：Dashboard 资产无效将阻断 install/update"
  else
    dashboard_policy_text="默认策略：Dashboard 资产需保持可部署"
  fi
  if [ -n "$(read_env_value "CLASH_CONTROLLER_SECRET" 2>/dev/null || true)" ]; then
    secret_text="已设置"
  else
    secret_text="未设置"
  fi

  echo
  echo "🐱 Clash 状态总览"
  echo

  echo "【当前结果】"
  echo "🐱 代理状态：$running_text"
  echo "🌐 当前可用性：$user_connectivity"
  echo "📡 当前订阅：${current_active:-未设置}"
  echo "🚀 当前节点：$current_proxy_brief"
  echo "🚨 当前风险：$user_risk"
  if [ "$next_action" = "clashctl select" ]; then
    echo "👉 clashctl select  切换节点"
  else
    echo "👉 下一步：$next_action"
  fi
  echo

  echo "【核心入口】"
  echo "🔧 Profile：$profile"
  if [ -n "${mixed_port:-}" ] && [ "$mixed_port" != "null" ]; then
    echo "🌐 本地代理：http://127.0.0.1:${mixed_port}"
    if [ "$allow_lan" = "true" ]; then
      lan_proxy="$(ui_lan_ip 2>/dev/null || true)"
      [ -n "${lan_proxy:-}" ] && echo "🏠 局域网代理：http://${lan_proxy}:${mixed_port}"
    else
      echo "🏠 局域网代理：已关闭"
    fi
  else
    echo "🌐 本地代理：未知"
  fi

  if [ -n "${controller:-}" ] && [ "$controller" != "null" ]; then
    echo "🐱 控制台：http://${controller}/ui"
    [ -n "${controller_lan:-}" ] && echo "🏠 局域网：http://${controller_lan}/ui"
    if [ -n "${controller_public:-}" ]; then
      echo "🌍 公网：http://${controller_public}/ui"
    else
      echo "🌍 公网：需公网 IP / 端口映射后可访问"
    fi
  else
    echo "🐱 控制台：未知"
  fi
  echo

  echo "【安装上下文】"
  echo "🔧 运行后端：${install_backend_text:-unknown}"
  echo "💡 后端原因：$(status_runtime_backend_reason_text 2>/dev/null || echo unknown)"
  echo "🚦 内核开机自启：$(status_service_autostart_text)"
  echo "📜 开机代理保持：$(status_boot_proxy_keep_text)"
  echo "🐱 开机代理接管：$(status_boot_auto_proxy_text)"
  echo "💡 开机边界：$(status_boot_boundary_text)"
  echo "🧪 环境模式：${install_container_text:-unknown}"
  echo "🧩 安装验证：${install_verify_text:-unknown}"
  echo "📜 端口裁决：${port_adjustment_text:-unknown}"
  echo "📜 系统代理持久接管：${system_proxy_text}"
  echo "🧩 Dashboard：${dashboard_text}（来源：${dashboard_source_text}）"
  echo "🧩 Dashboard 策略：${dashboard_policy_text}"
  echo "🔐 控制器密钥：${secret_text}"
  echo

  if [ -n "$(install_plan_controller 2>/dev/null || true)" ]; then
    echo "🐱 安装期控制器：$(display_controller_local_addr "$(install_plan_controller 2>/dev/null || true)" 2>/dev/null || install_plan_controller 2>/dev/null || true)"
  fi

  if [ -n "$(install_plan_mixed_port 2>/dev/null || true)" ]; then
    echo "🌐 安装期代理端口：$(install_plan_mixed_port 2>/dev/null || true)"
  fi

  echo

  echo "【Tun 状态】"
  if [ "$tun_enabled" = "true" ]; then
    echo "🐱 Tun 开关：已开启"
  else
    echo "❗ Tun 开关：未开启"
  fi

  echo "🧪 Tun 生效：${tun_effective:-未知}"
  echo "🔧  Tun stack：${tun_stack:-unknown}"
  echo "🐱 容器裁决：${tun_container_text:-未知}"
  echo "🚀 内核支持：${tun_kernel_text:-未知}"
  echo

  echo "【编译结果】"
  echo "🧩 编译模式：active-only"
  [ -n "$(status_build_active_source 2>/dev/null || true)" ] && echo "📦 编译主订阅：$(status_build_active_source 2>/dev/null || true)"

  if [ -n "${build_status:-}" ]; then
    echo "🧩 最近编译：${build_status} @ ${build_time:-unknown}"
  else
    echo "🧩 最近编译：未知"
  fi

  [ -n "${build_active_sources:-}" ] && echo "🐱 实际参与编译：$build_active_sources"
  [ -n "${build_failed_active_sources:-}" ] && echo "❌ 编译失败源：$build_failed_active_sources"
  echo

  echo "【当前订阅健康】"
  if status_subscription_health_summary | grep -q .; then
    status_subscription_health_summary | sed 's/^/  /'
  else
    echo "  暂无健康数据"
  fi
  echo

  echo "【系统事件】"
  echo "🧩 当前配置来源：${config_source:-unknown}${config_source_time:+ @ ${config_source_time}}"

  case "${build_applied:-}" in
    true)
      echo "🐱 最近构建应用：true @ ${build_applied_time:-unknown}"
      ;;
    false)
      echo "🚨 最近构建应用：false @ ${build_applied_time:-unknown}"
      [ -n "${build_applied_reason:-}" ] && echo "未应用原因：${build_applied_reason}"
      ;;
    *)
      echo "⚪ 最近构建应用：unknown"
      ;;
  esac

  if [ -n "${build_block_reason:-}" ]; then
    echo "🚨 最近阻断：${build_block_reason} @ ${build_block_time:-unknown}"
  else
    echo "🚨 最近阻断：无"
  fi

  if [ -n "${last_switch_to:-}" ]; then
    echo "🤖 订阅切换建议记录：${last_switch_from:-unknown} -> ${last_switch_to} @ ${last_switch_time:-unknown}"
  else
    echo "🤖 订阅切换建议记录：无"
  fi

  if [ "${fallback_used:-false}" = "true" ]; then
    echo "🚨 最近回退：true @ ${fallback_time:-unknown}"
    [ -n "${fallback_reason:-}" ] && echo "回退原因：${fallback_reason}"
  else
    echo "🚨 最近回退：false"
  fi
  echo

  echo "【风险原因】"
  if status_risk_reason_lines | grep -q .; then
    status_risk_reason_lines | sed 's/^/  /'
  else
    echo "  无明显风险原因"
  fi
  echo

  echo "【网络闭环】"
  echo "📜 问题裁决：$(connectivity_issue_text)"
  echo "🔍 关键证据："
  connectivity_evidence_lines | sed 's/^/  /'
  echo

  echo "【策略组摘要】"
  if [ "$controller_ok" = "true" ] && [ -n "${current_proxy_lines:-}" ]; then
    printf '%s\n' "$current_proxy_lines" | sed 's/^/  /'
  else
    echo "  控制器不可访问"
  fi
  echo
}

cmd_status() {
  prepare

  case "${1:-}" in
    --verbose|-v)
      print_status_summary_verbose
      ;;
    "")
      print_status_summary_compact
      ;;
    *)
      die_usage "未知的 status 参数：$1" "clashctl status [--verbose]"
      ;;
  esac
}

cmd_status_next() {
  prepare
  system_state_default_action
}

boot_usage() {
  cat <<EOF
📜 用法：
  clashctl boot status
  clashctl boot on
  clashctl boot off
  clashctl boot runtime on|off|status
  clashctl boot proxy on|off|status
EOF
}

print_boot_status() {
  ui_title "🚦 开机代理接管"
  ui_kv "🔧" "运行后端" "$(runtime_backend 2>/dev/null || echo unknown)"
  ui_kv "🚦" "内核开机自启" "$(status_service_autostart_text)"
  ui_kv "📜" "开机代理保持" "$(status_boot_proxy_keep_text)"
  ui_kv "🐱" "开机代理接管" "$(status_boot_auto_proxy_text)"
  ui_kv "💡" "后端边界" "$(status_boot_boundary_text)"
  ui_blank
}

cmd_boot_runtime() {
  case "${1:-status}" in
    on)
      if ! service_autostart_supported; then
        die_state "当前后端不支持内核开机自启：$(runtime_backend 2>/dev/null || echo unknown)" \
                  "如需开机自启，请使用 systemd / systemd-user 后端"
      fi
      service_autostart_enable || die_state "内核开机自启开启失败" "clashctl doctor"
      success "内核开机自启已开启"
      ;;
    off)
      if ! service_autostart_supported; then
        write_runtime_value "RUNTIME_BOOT_AUTOSTART" "false"
        write_runtime_value "RUNTIME_BOOT_AUTOSTART_EXPLICIT" "true"
        ui_warn "当前后端不支持内核开机自启，已记录为关闭：$(runtime_backend 2>/dev/null || echo unknown)"
      else
        service_autostart_disable || die_state "内核开机自启关闭失败" "clashctl doctor"
        success "内核开机自启已关闭"
      fi
      ;;
    status)
      echo "$(status_service_autostart_text)"
      return 0
      ;;
    *)
      die_usage "未知的 boot runtime 参数：$1" "clashctl boot runtime on|off|status"
      ;;
  esac

  print_boot_status
}

cmd_boot_proxy() {
  local backend
  backend="$(runtime_backend 2>/dev/null || echo unknown)"

  case "${1:-status}" in
    on)
      if [ "$backend" = "script" ]; then
        ui_warn "script 后端不会开机启动内核；仅保持系统代理变量可能在重启后指向未运行的本地端口"
      fi
      boot_proxy_keep_enable || die_state "开机代理保持开启失败：当前环境不支持写入 $(system_proxy_env_file)" \
                                      "请检查权限，或执行 clashctl doctor"
      success "开机代理保持已开启"
      ;;
    off)
      boot_proxy_keep_disable || die_state "开机代理保持关闭失败：无法清理 $(system_proxy_env_file)" \
                                       "请检查权限，或执行 clashctl doctor"
      success "开机代理保持已关闭"
      ;;
    status)
      echo "$(status_boot_proxy_keep_text)"
      return 0
      ;;
    *)
      die_usage "未知的 boot proxy 参数：$1" "clashctl boot proxy on|off|status"
      ;;
  esac

  print_boot_status
}

cmd_boot() {
  prepare

  case "${1:-status}" in
    on)
      if ! service_autostart_supported; then
        die_state "当前后端不支持开机自动进入代理状态：$(runtime_backend 2>/dev/null || echo unknown)" \
                  "script 后端只能手动启动；可执行 clashctl boot proxy off 清理开机代理保持"
      fi
      boot_proxy_keep_enable || die_state "开机代理保持开启失败：当前环境不支持写入 $(system_proxy_env_file)" \
                                      "请检查权限，或执行 clashctl doctor"
      if ! service_autostart_enable; then
        boot_proxy_keep_disable >/dev/null 2>&1 || true
        die_state "内核开机自启开启失败" "clashctl doctor"
      fi
      success "开机代理接管已开启"
      print_boot_status
      ;;
    off)
      if service_autostart_supported; then
        service_autostart_disable || die_state "内核开机自启关闭失败" "clashctl doctor"
      else
        write_runtime_value "RUNTIME_BOOT_AUTOSTART" "false"
        write_runtime_value "RUNTIME_BOOT_AUTOSTART_EXPLICIT" "true"
        ui_warn "当前后端不支持内核开机自启，跳过服务 disable：$(runtime_backend 2>/dev/null || echo unknown)"
      fi
      boot_proxy_keep_disable || die_state "开机代理保持关闭失败：无法清理 $(system_proxy_env_file)" \
                                       "请检查权限，或执行 clashctl doctor"
      success "开机代理接管已关闭"
      print_boot_status
      ;;
    status)
      print_boot_status
      ;;
    runtime)
      shift || true
      cmd_boot_runtime "$@"
      ;;
    proxy)
      shift || true
      cmd_boot_proxy "$@"
      ;;
    -h|--help|help)
      boot_usage
      ;;
    *)
      die_usage "未知的 boot 子命令：$1" "clashctl boot on|off|status"
      ;;
  esac
}

url_host_bracket_if_needed() {
  local host="$1"

  [ -n "${host:-}" ] || return 1

  case "$host" in
    \[*\])
      echo "$host"
      ;;
    *:*)
      echo "[$host]"
      ;;
    *)
      echo "$host"
      ;;
  esac
}

url_host_bracket_if_needed() {
  local host="$1"

  [ -n "${host:-}" ] || return 1

  case "$host" in
    \[*\])
      echo "$host"
      ;;
    *:*)
      echo "[$host]"
      ;;
    *)
      echo "$host"
      ;;
  esac
}

ui_controller_port() {
  local controller
  controller="$(status_read_controller_raw 2>/dev/null || true)"
  [ -n "${controller:-}" ] && [ "$controller" != "null" ] || return 1
  echo "${controller##*:}"
}

ui_lan_ip() {
  ip route get 1.1.1.1 2>/dev/null | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "src") {
          print $(i+1)
          exit
        }
      }
    }
  '
}

ui_public_ip() {
  local ip=""

  ip="$(
    env \
      -u http_proxy \
      -u https_proxy \
      -u HTTP_PROXY \
      -u HTTPS_PROXY \
      -u all_proxy \
      -u ALL_PROXY \
      curl -4 -fsSL --connect-timeout 2 --max-time 3 https://api.ipify.org 2>/dev/null || true
  )"

  if [ -n "${ip:-}" ]; then
    echo "$ip"
    return 0
  fi

  ip="$(
    env \
      -u http_proxy \
      -u https_proxy \
      -u HTTP_PROXY \
      -u HTTPS_PROXY \
      -u all_proxy \
      -u ALL_PROXY \
      curl -6 -fsSL --connect-timeout 2 --max-time 3 https://api64.ipify.org 2>/dev/null || true
  )"

  [ -n "${ip:-}" ] && echo "$ip"
}

cmd_ui_box() {
  local line0="" line1="" line2="" line3="" line4="" line5=""
  local secret="${5:-}"

  line0="🔓 注意放行端口：${6:-unknown}"
  [ -n "${1:-}" ] && line1="📶 状态：$1"
  [ -n "${3:-}" ] && line2="🏠 内网：$3"
  line3="📡 公共：http://board.zash.run.place"
  [ -n "${4:-}" ] && line4="🌏 公网：$4"
  [ -n "${secret:-}" ] && line5="🔑 密钥：$secret"

  compute_box_width \
    "🐱 Web 控制台" \
    "$line0" "$line1" "$line2" "$line3" "$line4" "$line5"

  echo
  box_border_top
  box_title_line "🐱 Web 控制台"
  box_border_mid
  box_empty

  [ -n "$line0" ] && box_section_line "$line0"
  [ -n "$line1" ] && box_section_line "$line1"
  [ -n "$line2" ] && box_section_line "$line2"
  [ -n "$line3" ] && box_section_line "$line3"
  [ -n "$line4" ] && box_section_line "$line4"
  [ -n "$line5" ] && box_section_line "$line5"

  box_empty
  box_border_bottom
  echo
}

cmd_ui_help_summary() {
  echo "〽️ 常用命令"
  printf '  %-18s %s\n' "clashon" "🚀 开启代理"
  printf '  %-18s %s\n' "clashoff" "⛔ 关闭代理"
  printf '  %-18s %s\n' "clashctl select" "💫 选择节点"
  echo "🕹️  控制台"
  printf '  %-18s %s\n' "clashui" "🕹️  查看 Web 控制台"
  printf '  %-18s %s\n' "clashsecret" "🔑 查看或设置 Web 密钥"
  echo "📦 订阅"
  printf '  %-18s %s\n' "clashctl add" "➕ 添加订阅"
  printf '  %-18s %s\n' "clashctl add local" "➕ 从 runtime/subscriptions 导入本地订阅"
  printf '  %-18s %s\n' "clashctl use" "💱 切换订阅"
  printf '  %-18s %s\n' "clashctl ls" "📜 查看订阅列表"
  echo "📌 高级"
  printf '  %-18s %s\n' "clashctl lan" "🏠 局域网代理管理"
  printf '  %-18s %s\n' "clashctl tun" "🧪 Tun 模式管理"
  printf '  %-18s %s\n' "clashctl mixin" "🧩 Mixin 配置管理"
  printf '  %-18s %s\n' "clashctl sub" "🧩 订阅高级管理（启用 / 禁用 / 重命名 / 删除）"
  printf '  %-18s %s\n' "clashctl upgrade" "🚀 升级当前或指定内核"
  printf '  %-18s %s\n' "clashctl update" "🔄 更新项目代码"
  printf '  %-18s %s\n' "clashctl completion" "💡 导出 Bash / Zsh 补全脚本"
  echo "📜 日志"
  printf '  %-18s %s\n' "clashctl doctor" "🩺 诊断面板"
  printf '  %-18s %s\n' "clashctl log/logs" "📜 查看日志"
  echo
  echo "💡 显示更多帮助命令：clashctl -h"
}

logs_mihomo() {
  if [ ! -f "$LOG_DIR/mihomo.out.log" ]; then
    echo "Mihomo 日志文件不存在"
    return 0
  fi

  tail -n 200 "$LOG_DIR/mihomo.out.log"
}

logs_subconverter() {
  local file
  file="$(subconverter_log_file)"

  if [ ! -f "$file" ]; then
    echo "subconverter 日志文件不存在"
    return 0
  fi

  tail -n 200 "$file"
}

logs_service() {
  local backend
  backend="$(runtime_backend)"

  case "$backend" in
    systemd)
      systemd_service_logs
      ;;
    systemd-user)
      systemd_user_service_logs
      ;;
    script)
      echo "当前为脚本运行模式，服务日志即 Mihomo 日志"
      logs_mihomo
      ;;
    *)
      die "未知运行后端：$backend"
      ;;
  esac
}

cmd_logs() {
  prepare

  case "${1:-mihomo}" in
    mihomo)
      logs_mihomo
      ;;
    subconverter)
      logs_subconverter
      ;;
    service)
      logs_service
      ;;
    *)
      die "用法：clashctl log|logs [mihomo|subconverter|service]"
      ;;
  esac
}

doctor_print_title() {
  echo
  echo "🧰【$1】"
}

doctor_ok() {
  echo "  ✔ $1"
}

doctor_warn() {
  echo "  ⚠ $1"
}

doctor_fail() {
  echo "  ✘ $1"
}

doctor_yq_available() {
  local yq_path
  yq_path="$(yq_bin 2>/dev/null || true)"
  [ -n "${yq_path:-}" ] && [ -x "$yq_path" ]
}

doctor_warn_skip_yq_parse() {
  doctor_warn "缺少 yq，跳过配置解析类检查"
}

doctor_install_context() {
  doctor_print_title "安装环境检查"

  if [ -n "$(install_env_os 2>/dev/null || true)" ]; then
    doctor_ok "操作系统：$(install_env_os 2>/dev/null || echo unknown)"
  else
    doctor_warn "未记录安装期操作系统"
  fi

  if [ -n "$(install_env_arch 2>/dev/null || true)" ]; then
    doctor_ok "系统架构：$(install_env_arch 2>/dev/null || echo unknown)"
  else
    doctor_warn "未记录安装期系统架构"
  fi

  if [ -n "$(install_env_scope 2>/dev/null || true)" ]; then
    doctor_ok "安装范围：$(install_env_scope 2>/dev/null || echo unknown)"
  else
    doctor_warn "未记录安装范围"
  fi

  if [ -n "$(install_env_container 2>/dev/null || true)" ]; then
    doctor_ok "容器环境：$(install_env_container 2>/dev/null || echo unknown)"
  else
    doctor_warn "未记录容器环境"
  fi

  if [ -n "$(install_plan_backend 2>/dev/null || true)" ]; then
    doctor_ok "安装期选择后端：$(install_plan_backend 2>/dev/null || echo unknown)"
  else
    doctor_warn "未记录安装期运行后端"
  fi

  if [ -n "$(install_plan_container_mode 2>/dev/null || true)" ]; then
    doctor_ok "容器兼容模式：$(install_plan_container_mode 2>/dev/null || echo unknown)"
  else
    doctor_warn "未记录容器兼容模式"
  fi

  if [ -n "$(install_plan_port_policy 2>/dev/null || true)" ]; then
    doctor_ok "端口策略：$(install_plan_port_policy 2>/dev/null || echo unknown)"
  else
    doctor_warn "未记录端口策略"
  fi
}

doctor_container_tun() {
  doctor_print_title "容器与 Tun 检查"

  case "$(install_env_container 2>/dev/null || echo unknown)" in
    host)
      doctor_ok "当前运行在主机环境"
      ;;
    docker)
      doctor_warn "检测到 Docker 环境"
      ;;
    container)
      doctor_warn "检测到容器环境"
      ;;
    *)
      doctor_warn "容器环境未知"
      ;;
  esac

  case "$(runtime_backend 2>/dev/null || echo unknown)" in
    systemd)
      doctor_ok "当前运行后端：systemd"
      ;;
    systemd-user)
      doctor_ok "当前运行后端：systemd-user"
      ;;
    script)
      doctor_warn "当前运行后端：script"
      ;;
    *)
      doctor_warn "当前运行后端未知"
      ;;
  esac

  if tun_device_exists; then
    doctor_ok "/dev/net/tun 存在"
  else
    doctor_warn "/dev/net/tun 不存在"
  fi

  if tun_device_readable; then
    doctor_ok "/dev/net/tun 可读写"
  else
    doctor_warn "/dev/net/tun 不可直接读写"
  fi

  case "$(install_env_tun_safe 2>/dev/null || true)" in
    true)
      doctor_ok "安装期判定：Tun 可安全管理"
      ;;
    false)
      doctor_warn "安装期判定：Tun 不可安全管理"
      ;;
    *)
      doctor_warn "安装期未记录 Tun 安全性"
      ;;
  esac

  if has_ip_command; then
    doctor_ok "ip 命令可用"
  else
    doctor_warn "缺少 ip 命令，Tun/路由能力受限"
  fi

  case "$(tun_enabled 2>/dev/null || echo false)" in
    true)
      doctor_warn "当前 Tun 状态：开启"
      ;;
    *)
      doctor_ok "当前 Tun 状态：关闭"
      ;;
  esac
}

doctor_tun_system_proxy() {
  local tun_state system_proxy_state

  doctor_print_title "Tun 与系统代理检查"

  tun_state="$(tun_enabled 2>/dev/null || echo false)"
  system_proxy_state="$(system_proxy_status 2>/dev/null || echo off)"

  if [ "$tun_state" = "true" ]; then
    doctor_ok "Tun 模式：已开启"
  else
    doctor_ok "Tun 模式：已关闭"
  fi

  if [ "$system_proxy_state" = "on" ]; then
    doctor_ok "系统代理持久接管：已开启"
  else
    doctor_ok "系统代理持久接管：已关闭"
  fi

  if [ "$tun_state" = "true" ] && [ "$system_proxy_state" = "on" ]; then
    doctor_warn "Tun 模式与系统代理同时开启，可能造成流量接管路径重复或排障混淆"
    echo "    建议：clashctl tun on-proxy-off"
  fi
}

doctor_dependencies() {
  local dashboard_source

  doctor_print_title "依赖检查"

  [ -x "$(mihomo_bin)" ] && doctor_ok "Mihomo 已安装：$(mihomo_bin)" || doctor_fail "Mihomo 缺失：$(mihomo_bin)"
  [ -x "$(subconverter_bin)" ] && doctor_ok "subconverter 已安装：$(subconverter_bin)" || doctor_fail "subconverter 缺失：$(subconverter_bin)"
  [ -x "$(yq_bin)" ] && doctor_ok "yq 已安装：$(yq_bin)" || doctor_fail "yq 缺失：$(yq_bin)"

  dashboard_source="$(dashboard_asset_source)"
  case "$dashboard_source" in
    dir)
      doctor_ok "Dashboard 来源：dir（当前部署不依赖 unzip）"
      ;;
    zip)
      if command -v unzip >/dev/null 2>&1; then
        if dashboard_archive_valid; then
          doctor_ok "Dashboard 来源：zip（unzip 可用，压缩包可解压）"
        else
          doctor_fail "Dashboard 来源：zip（压缩包损坏或不可解压，将阻断 install/update）"
        fi
      else
        doctor_fail "Dashboard 来源：zip（缺少 unzip，无法部署，将阻断 install/update）"
      fi
      ;;
    *)
      doctor_warn "Dashboard 来源：none（dist/ 与 dist.zip 均不可用，将阻断 install/update）"
      ;;
  esac

  if command -v openssl >/dev/null 2>&1; then
    doctor_ok "Secret 生成：openssl 可用"
  elif [ -r /dev/urandom ] && command -v od >/dev/null 2>&1 && command -v tr >/dev/null 2>&1 && command -v head >/dev/null 2>&1; then
    doctor_ok "Secret 生成：fallback 可用（/dev/urandom + od/tr/head）"
  else
    doctor_fail "Secret 生成：缺少 openssl 且 fallback 不可用"
  fi
}

doctor_download_mirrors() {
  doctor_print_title "下载加速配置"

  local custom_prefix pool_source
  custom_prefix="$(github_proxy_prefix 2>/dev/null || true)"

  if [ -n "${custom_prefix:-}" ]; then
    doctor_ok "自定义镜像（CLASH_GH_PROXY）：${custom_prefix}"
    pool_source="custom"
  elif [ -n "${CLASH_GH_PROXY_POOL:-}" ]; then
    doctor_ok "自定义镜像池（CLASH_GH_PROXY_POOL）已配置"
    pool_source="custom-pool"
  else
    doctor_ok "使用内置默认镜像池（gh-proxy.org / ghfast.top / ghproxy.net / kkgithub.com）"
    pool_source="default"
  fi

  # Show mirror history from state file
  local state_file mirror_info last_ok last_fail
  state_file="$(download_mirror_state_file 2>/dev/null || true)"
  if [ -f "${state_file:-}" ]; then
    last_ok="$(grep 'LAST_SUCCESS_URL' "$state_file" 2>/dev/null | tail -n 1 | sed 's/.*=//;s/"//g' || true)"
    last_fail="$(grep 'LAST_FAILURE_URL' "$state_file" 2>/dev/null | tail -n 1 | sed 's/.*=//;s/"//g' || true)"
    [ -n "${last_ok:-}" ] && doctor_ok "上次成功镜像：${last_ok}"
    [ -n "${last_fail:-}" ] && doctor_warn "上次失败镜像：${last_fail}"
  fi

  doctor_ok "配置提示：在 .env 中设置 CLASH_GH_PROXY=https://your-mirror.com 可指定自定义加速前缀"
  doctor_ok "可用镜像列表参考：https://ghproxy.link/"
}

doctor_config() {
  local config_file active_profile mixed_port controller controller_secret_value external_ui_path dashboard_source

  doctor_print_title "配置检查"

  config_file="$RUNTIME_DIR/config.yaml"

  if [ -s "$config_file" ]; then
    doctor_ok "运行配置存在：$config_file"
  else
    doctor_fail "运行配置缺失：$config_file"
    return 0
  fi

  active_profile="$(show_active_profile 2>/dev/null || true)"
  [ -n "${active_profile:-}" ] || active_profile="default"
  doctor_ok "当前 Profile：$active_profile"

  if ! doctor_yq_available; then
    doctor_warn_skip_yq_parse
    if test_runtime_config "$config_file" >/dev/null 2>&1; then
      doctor_ok "配置校验通过"
    else
      doctor_fail "配置校验失败"
    fi
    return 0
  fi

  mixed_port="$("$(yq_bin)" eval '.["mixed-port"] // .port // ""' "$config_file" 2>/dev/null | head -n 1)"
  controller="$("$(yq_bin)" eval '.["external-controller"] // ""' "$config_file" 2>/dev/null | head -n 1)"

  if [ -n "${mixed_port:-}" ] && [ "$mixed_port" != "null" ]; then
    doctor_ok "代理端口：$mixed_port"
  else
    doctor_warn "未解析到代理端口"
  fi

  if [ -n "${controller:-}" ] && [ "$controller" != "null" ]; then
    doctor_ok "控制器地址：$(display_controller_local_addr "$controller" 2>/dev/null || echo "$controller")"
  else
    doctor_warn "未解析到控制器地址"
  fi

  controller_secret_value="$("$(yq_bin)" eval '.secret // ""' "$config_file" 2>/dev/null | head -n 1)"
  if [ -n "${controller_secret_value:-}" ] && [ "$controller_secret_value" != "null" ]; then
    doctor_ok "控制器密钥：已设置"
  else
    doctor_fail "控制器密钥：未设置"
  fi

  external_ui_path="$("$(yq_bin)" eval '.["external-ui"] // ""' "$config_file" 2>/dev/null | head -n 1)"
  dashboard_source="$(read_runtime_value "DASHBOARD_ASSET_SOURCE" 2>/dev/null || echo none)"
  case "${dashboard_source:-none}" in
    dir|zip|none) ;;
    *) dashboard_source="none" ;;
  esac
  if [ -n "${external_ui_path:-}" ] && [ "$external_ui_path" != "null" ] && [ -f "${external_ui_path%/}/index.html" ]; then
    doctor_ok "Dashboard 已接入：${external_ui_path}（来源：${dashboard_source}）"
  else
    doctor_warn "Dashboard 未接入或目录无效（来源：${dashboard_source}）"
  fi

  if test_runtime_config "$config_file" >/dev/null 2>&1; then
    doctor_ok "配置校验通过"
  else
    doctor_fail "配置校验失败"
  fi
}

doctor_subscription() {
  local active file total enabled convert_count auto_disabled_count name

  doctor_print_title "订阅检查"

  file="$(subscriptions_file 2>/dev/null || true)"
  if [ -z "${file:-}" ] || [ ! -f "$file" ]; then
    doctor_warn "订阅配置文件不存在"
    return 0
  fi

  doctor_ok "订阅策略：active-only"

  if ! doctor_yq_available; then
    doctor_warn_skip_yq_parse
    return 0
  fi

  active="$(active_subscription_name 2>/dev/null || true)"

  total="$("$(yq_bin)" eval '.sources | keys | length' "$file" 2>/dev/null || echo 0)"
  enabled="$("$(yq_bin)" eval '[.sources[] | select(.enabled == true)] | length' "$file" 2>/dev/null || echo 0)"
  convert_count="$("$(yq_bin)" eval '[.sources[] | select(.type == "convert")] | length' "$file" 2>/dev/null || echo 0)"

  auto_disabled_count="$(
    while IFS= read -r name; do
      [ -n "${name:-}" ] || continue
      if subscription_auto_disabled "$name"; then
        echo 1
      fi
    done < <("$(yq_bin)" eval '.sources | keys | .[]' "$file")
  )"
  auto_disabled_count="$(printf '%s\n' "${auto_disabled_count:-}" | awk 'NF{c++} END{print c+0}')"

  [ -n "${active:-}" ] && doctor_ok "当前主订阅：$active" || doctor_warn "当前主订阅为空"

  doctor_ok "订阅源总数：$total"
  doctor_ok "已启用订阅源：$enabled"
  doctor_ok "convert 订阅源：$convert_count"
  doctor_ok "自动禁用订阅源：$auto_disabled_count"

  if [ -n "${active:-}" ] && subscription_exists "$active"; then
    if subscription_enabled "$active"; then
      doctor_ok "当前主订阅可用：$active"
    else
      doctor_warn "当前主订阅已禁用：$active"
    fi

    if subscription_auto_disabled "$active"; then
      doctor_warn "当前主订阅曾被自动禁用：$active"
    fi
  fi
}

doctor_build() {
  local active active_sources failed_active_sources last_status last_time
  local block_reason block_time
  local error_summary error_detail error_stage

  doctor_print_title "编译状态检查"

  active="$(read_build_value "BUILD_ACTIVE_SOURCE" 2>/dev/null || true)"
  active_sources="$(status_build_active_sources 2>/dev/null || true)"
  failed_active_sources="$(status_build_failed_active_sources 2>/dev/null || true)"
  last_status="$(read_build_value "BUILD_LAST_STATUS" 2>/dev/null || true)"
  last_time="$(read_build_value "BUILD_LAST_TIME" 2>/dev/null || true)"
  error_summary="$(read_build_value "BUILD_LAST_ERROR_SUMMARY" 2>/dev/null || true)"
  error_detail="$(read_build_value "BUILD_LAST_ERROR_DETAIL" 2>/dev/null || true)"
  error_stage="$(read_build_value "BUILD_LAST_ERROR_STAGE" 2>/dev/null || true)"
  block_reason="$(read_runtime_event_value "RUNTIME_LAST_BUILD_BLOCK_REASON" 2>/dev/null || true)"
  block_time="$(read_runtime_event_value "RUNTIME_LAST_BUILD_BLOCK_TIME" 2>/dev/null || true)"

  if [ -z "${active:-}${active_sources:-}${failed_active_sources:-}${last_status:-}${last_time:-}${error_summary:-}${error_stage:-}${block_reason:-}" ]; then
    doctor_warn "未找到编译元数据（build.env）"
    return 0
  fi

  doctor_ok "编译模式：active-only"

  if [ -n "${active:-}" ]; then
    doctor_ok "当前主订阅：$active"
  else
    doctor_warn "当前主订阅为空"
  fi

  if [ -n "${active_sources:-}" ]; then
    doctor_ok "实际参与编译：$active_sources"
  else
    doctor_warn "没有任何订阅参与编译"
  fi

  if [ -n "${failed_active_sources:-}" ]; then
    doctor_warn "失败订阅源：$failed_active_sources"
  else
    doctor_ok "失败订阅源：无"
  fi

  if [ -n "${last_status:-}" ]; then
    if [ "$last_status" = "success" ]; then
      doctor_ok "最近一次编译状态：$last_status"
    else
      doctor_warn "最近一次编译状态：$last_status"
    fi
  else
    doctor_warn "最近一次编译状态未知"
  fi

  if [ -n "${last_time:-}" ]; then
    doctor_ok "最近一次编译时间：$last_time"
  else
    doctor_warn "最近一次编译时间未知"
  fi

  if [ -n "${block_reason:-}" ]; then
    if [ -n "${block_time:-}" ]; then
      doctor_warn "最近一次编译阻断原因：${block_reason} @ ${block_time}"
    else
      doctor_warn "最近一次编译阻断原因：$block_reason"
    fi
  fi

  if [ -n "${error_summary:-}" ]; then
    doctor_warn "最近一次错误摘要：$error_summary"
  fi

  if [ -n "${error_stage:-}" ]; then
    doctor_warn "最近一次错误阶段：$error_stage"
  fi

  if [ -n "${error_detail:-}" ]; then
    echo "    详细错误："
    printf '%s\n' "$error_detail" | sed 's/^/      /'
  fi
}

doctor_service() {
  local backend

  doctor_print_title "服务检查"

  backend="$(runtime_backend)"
  doctor_ok "运行后端：$backend"
  doctor_ok "内核开机自启：$(status_service_autostart_text)"
  doctor_ok "开机代理保持：$(status_boot_proxy_keep_text)"
  doctor_ok "开机代理接管：$(status_boot_auto_proxy_text)"
  doctor_ok "开机边界：$(status_boot_boundary_text)"

  case "$backend" in
    systemd)
      if systemctl is-active --quiet "$(service_unit_name)"; then
        doctor_ok "systemd 服务运行中"
        systemctl show "$(service_unit_name)" --property MainPID --value 2>/dev/null | awk '{print "    进程号：" $1}'
      else
        doctor_warn "systemd 服务未运行"
      fi
      ;;
    systemd-user)
      if systemctl --user is-active --quiet "$(service_unit_name)"; then
        doctor_ok "用户级 systemd 服务运行中"
        systemctl --user show "$(service_unit_name)" --property MainPID --value 2>/dev/null | awk '{print "    进程号：" $1}'
      else
        doctor_warn "用户级 systemd 服务未运行"
      fi
      ;;
    script)
      if [ -f "$RUNTIME_DIR/mihomo.pid" ]; then
        local pid
        pid="$(cat "$RUNTIME_DIR/mihomo.pid" 2>/dev/null || true)"
        if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
          doctor_ok "脚本模式进程运行中"
          echo "    进程号：$pid"
        else
          doctor_warn "脚本模式 PID 文件存在，但进程未运行"
        fi
      else
        doctor_warn "脚本模式当前未运行"
      fi
      ;;
    *)
      doctor_fail "未知运行后端：$backend"
      ;;
  esac
}

doctor_ports() {
  local config_file mixed_port controller controller_port dns_port bind_failure_kind

  doctor_print_title "端口检查"

  config_file="$RUNTIME_DIR/config.yaml"

  if [ ! -s "$config_file" ]; then
    doctor_warn "运行配置不存在，跳过端口检查"
    return 0
  fi

  if ! doctor_yq_available; then
    doctor_warn_skip_yq_parse
    if [ -x "$(subconverter_bin)" ]; then
      if is_port_in_use "$(subconverter_port)"; then
        doctor_ok "subconverter 端口已监听：$(subconverter_port)"
      else
        doctor_warn "subconverter 端口未监听：$(subconverter_port)"
      fi
    fi
    return 0
  fi

  mixed_port="$("$(yq_bin)" eval '.["mixed-port"] // .port // ""' "$config_file" 2>/dev/null | head -n 1)"
  controller="$("$(yq_bin)" eval '.["external-controller"] // ""' "$config_file" 2>/dev/null | head -n 1)"
  controller_port="${controller##*:}"
  dns_port="$(runtime_config_dns_port 2>/dev/null || true)"
  bind_failure_kind="$(runtime_mixed_port_bind_failure_kind 2>/dev/null || true)"

  if [ -n "${mixed_port:-}" ] && [ "$mixed_port" != "null" ]; then
    if [ "$bind_failure_kind" = "bind_denied" ]; then
      doctor_fail "mixed-port 绑定被拒绝：$mixed_port"
    elif [ "$bind_failure_kind" = "address_in_use" ]; then
      doctor_fail "mixed-port 端口被占用：$mixed_port"
    elif [ -n "${bind_failure_kind:-}" ]; then
      doctor_fail "mixed-port 绑定失败：$mixed_port"
    elif is_port_in_use "$mixed_port"; then
      doctor_ok "代理端口已监听：$mixed_port"
    else
      doctor_warn "代理端口未监听：$mixed_port"
    fi
  else
    doctor_warn "无法检查代理端口"
  fi

  if [ -n "${controller_port:-}" ] && [ "$controller_port" != "$controller" ] && [ "$controller_port" != "null" ]; then
    if is_port_in_use "$controller_port"; then
      doctor_ok "控制器端口已监听：$controller_port"
    else
      doctor_warn "控制器端口未监听：$controller_port"
    fi
  else
    doctor_warn "无法检查控制器端口"
  fi

  if [ -n "${dns_port:-}" ] && [ "$dns_port" != "null" ]; then
    if is_port_in_use "$dns_port"; then
      doctor_ok "DNS 端口已监听：$dns_port"
    else
      doctor_warn "DNS 端口未监听：$dns_port"
    fi
  else
    doctor_warn "无法检查 DNS 端口"
  fi

  if [ -x "$(subconverter_bin)" ]; then
    if is_port_in_use "$(subconverter_port)"; then
      doctor_ok "subconverter 端口已监听：$(subconverter_port)"
    else
      doctor_warn "subconverter 端口未监听：$(subconverter_port)"
    fi
  fi
}

doctor_install_ports() {
  doctor_print_title "安装端口裁决检查"

  if [ -n "$(install_plan_mixed_port 2>/dev/null || true)" ]; then
    doctor_ok "安装期代理端口：$(install_plan_mixed_port 2>/dev/null || echo unknown)"
    if [ "$(install_plan_mixed_port_auto_changed 2>/dev/null || echo false)" = "true" ]; then
      doctor_warn "代理端口在安装期发生自动避让"
    fi
  else
    doctor_warn "未记录安装期代理端口"
  fi

  if [ -n "$(install_plan_controller 2>/dev/null || true)" ]; then
    doctor_ok "安装期控制器：$(install_plan_controller 2>/dev/null || echo unknown)"
    if [ "$(install_plan_controller_auto_changed 2>/dev/null || echo false)" = "true" ]; then
      doctor_warn "控制器端口在安装期发生自动避让"
    fi
  else
    doctor_warn "未记录安装期控制器地址"
  fi

  if [ -n "$(install_plan_dns_port 2>/dev/null || true)" ]; then
    doctor_ok "安装期 DNS 端口：$(install_plan_dns_port 2>/dev/null || echo unknown)"
    if [ "$(install_plan_dns_port_auto_changed 2>/dev/null || echo false)" = "true" ]; then
      doctor_warn "DNS 端口在安装期发生自动避让"
    fi
  else
    doctor_warn "未记录安装期 DNS 端口"
  fi
}

doctor_runtime_events() {
  local fallback_used fallback_time fallback_reason risk_level
  local config_source build_applied build_applied_time build_applied_reason
  local system_proxy_text dashboard_status dashboard_source secret_status

  doctor_print_title "运行事件检查"

  fallback_used="$(runtime_last_fallback_used)"
  fallback_time="$(runtime_last_fallback_time)"
  fallback_reason="$(runtime_last_fallback_reason)"
  risk_level="$(doctor_risk_level)"
  config_source="$(status_runtime_config_source 2>/dev/null || true)"
  build_applied="$(status_runtime_build_applied 2>/dev/null || true)"
  build_applied_time="$(status_runtime_build_applied_time 2>/dev/null || true)"
  build_applied_reason="$(status_runtime_build_applied_reason 2>/dev/null || true)"
  system_proxy_text="$(persistent_system_proxy_text 2>/dev/null || echo unknown)"
  if [ -f "$(runtime_dashboard_dir)/index.html" ]; then
    dashboard_status="已部署"
  else
    dashboard_status="未部署"
  fi
  dashboard_source="$(read_runtime_value "DASHBOARD_ASSET_SOURCE" 2>/dev/null || echo none)"
  case "${dashboard_source:-none}" in
    dir|zip|none) ;;
    *) dashboard_source="none" ;;
  esac
  if [ -n "$(read_env_value "CLASH_CONTROLLER_SECRET" 2>/dev/null || true)" ]; then
    secret_status="已设置"
  else
    secret_status="未设置"
  fi

  doctor_ok "当前风险等级：${risk_level:-unknown}"
  doctor_ok "当前配置来源：${config_source:-unknown}"
  if [ "$system_proxy_text" = "unsupported" ]; then
    doctor_warn "系统代理持久接管：unsupported（当前用户不可写 $(system_proxy_env_file 2>/dev/null || echo /etc/environment)）"
  else
    doctor_ok "系统代理持久接管：${system_proxy_text}"
  fi
  doctor_ok "Dashboard 运行目录：${dashboard_status}（来源：${dashboard_source}）"
  doctor_ok ".env 控制器密钥：${secret_status}"

  case "${build_applied:-}" in
    true)
      doctor_ok "最近一次构建已应用"
      [ -n "${build_applied_time:-}" ] && echo "    应用时间：$build_applied_time"
      ;;
    false)
      doctor_warn "最近一次构建未应用"
      [ -n "${build_applied_time:-}" ] && echo "    记录时间：$build_applied_time"
      [ -n "${build_applied_reason:-}" ] && echo "    未应用原因：$build_applied_reason"
      ;;
    *)
      doctor_warn "最近一次构建应用状态未知"
      ;;
  esac

  if [ "${fallback_used:-}" = "true" ]; then
    doctor_warn "最近一次启动触发了配置回退"
    [ -n "${fallback_time:-}" ] && echo "    回退时间：$fallback_time"
    [ -n "${fallback_reason:-}" ] && echo "    回退原因：$fallback_reason"
  else
    doctor_ok "最近一次启动未触发配置回退"
  fi
}

doctor_install_verify() {
  local live_runtime="false"
  local live_controller="false"

  doctor_print_title "安装验证检查"

  case "$(install_verify_command_ready 2>/dev/null || true)" in
    true) doctor_ok "clashctl 命令入口可用" ;;
    false) doctor_fail "clashctl 命令入口不可用" ;;
    *) doctor_warn "未记录命令入口验证结果" ;;
  esac

  case "$(install_verify_config_ready 2>/dev/null || true)" in
    true) doctor_ok "安装后配置已就绪" ;;
    false) doctor_fail "安装后配置未就绪" ;;
    *) doctor_warn "未记录配置验证结果" ;;
  esac

  if status_is_running 2>/dev/null; then
    live_runtime="true"
  fi

  if proxy_controller_reachable 2>/dev/null; then
    live_controller="true"
  fi

  if [ "$live_runtime" = "true" ]; then
    doctor_ok "安装后运行态已就绪"
  else
    case "$(install_verify_runtime_ready 2>/dev/null || true)" in
      true) doctor_ok "安装后运行态已就绪" ;;
      false) doctor_warn "安装后运行态未就绪" ;;
      *) doctor_warn "未记录运行态验证结果" ;;
    esac
  fi

  if [ "$live_controller" = "true" ]; then
    doctor_ok "安装后控制器可访问"
  else
    case "$(install_verify_controller_ready 2>/dev/null || true)" in
      true) doctor_ok "安装后控制器可访问" ;;
      false) doctor_warn "安装后控制器不可访问" ;;
      *) doctor_warn "未记录控制器验证结果" ;;
    esac
  fi
}

doctor_active_switch() {
  local from to at reason

  doctor_print_title "主订阅自动切换检查"

  from="$(read_runtime_event_value "RUNTIME_LAST_ACTIVE_SWITCH_FROM" 2>/dev/null || true)"
  to="$(read_runtime_event_value "RUNTIME_LAST_ACTIVE_SWITCH_TO" 2>/dev/null || true)"
  at="$(read_runtime_event_value "RUNTIME_LAST_ACTIVE_SWITCH_TIME" 2>/dev/null || true)"
  reason="$(read_runtime_event_value "RUNTIME_LAST_ACTIVE_SWITCH_REASON" 2>/dev/null || true)"

  if [ -n "${to:-}" ]; then
    doctor_warn "检测到最近一次主订阅自动切换"
    [ -n "${from:-}" ] && echo "    from   : $from"
    echo "    to     : $to"
    [ -n "${at:-}" ] && echo "    time   : $at"
    [ -n "${reason:-}" ] && echo "    reason : $reason"
  else
    doctor_ok "最近未发生主订阅自动切换"
  fi
}

doctor_controller() {
  local controller group_count current_examples bind_failure_text

  doctor_print_title "控制器检查"

  controller="$(status_read_controller 2>/dev/null || true)"
  bind_failure_text="$(runtime_mixed_port_bind_failure_text 2>/dev/null || true)"

  if [ -z "${controller:-}" ] || [ "$controller" = "null" ]; then
    doctor_fail "未解析到 external-controller"
    return 0
  fi

  doctor_ok "控制器地址：$(display_controller_local_addr "$controller" 2>/dev/null || echo "$controller")"

  if ! status_is_running; then
    if [ -n "${bind_failure_text:-}" ]; then
      doctor_warn "${bind_failure_text}，无法检查控制器 API"
    else
      doctor_warn "内核未运行，无法检查控制器 API"
    fi
    return 0
  fi

  if proxy_controller_reachable 2>/dev/null; then
    doctor_ok "控制器 API 可访问"

    group_count="$(proxy_group_count 2>/dev/null || echo 0)"
    doctor_ok "可切换策略组数量：$group_count"

    if [ "${group_count:-0}" -gt 0 ]; then
      echo "    当前策略组摘要："
      print_proxy_groups_status | head -n 5 | sed 's/^/      /'
    fi
  else
    doctor_fail "控制器 API 不可访问"
  fi
}

cmd_doctor() {
  prepare
  load_system_state

  ui_title "📜 系统诊断"

  ui_section "总体结论"
  doctor_primary_conclusion
  ui_kv "🚨" "风险等级" "$(doctor_risk_text)"
  ui_blank

  ui_section "发现的问题"
  if doctor_problem_lines | grep -q .; then
    doctor_problem_lines | sed 's/^/  /'
  else
    echo "  🐱 未发现明显问题"
  fi
  ui_blank

  ui_section "关键证据"
  doctor_evidence_lines | sed 's/^/  /'
  ui_blank

  ui_section "修复建议"
  doctor_recommendation_lines | sed 's/^/  /'
  ui_blank

  ui_section "详细检查"
  doctor_install_context
  doctor_dependencies
  doctor_download_mirrors
  doctor_container_tun
  doctor_tun_system_proxy
  doctor_config
  doctor_subscription
  doctor_build
  doctor_service
  doctor_ports
  doctor_install_ports
  doctor_runtime_events
  doctor_install_verify
  doctor_active_switch
  doctor_controller

}

cmd_dev() {
  prepare

  case "${1:-}" in
    reset)
      echo
      echo "🧪 正在恢复到安装前状态（保留项目目录与下载文件） ..."
      echo

      bash "$PROJECT_DIR/uninstall.sh" --dev-reset

      echo
      echo "🐱 开发重置完成"
      echo "🧩 保留内容：项目目录、已下载依赖、调试环境"
      echo "👉 下一步：重新执行 install.sh 或 clashctl status"
      echo
      ;;
    "")
      echo "📜 用法：clashctl dev reset"
      ;;
    *)
      die_usage "未知的 dev 子命令：$1" "clashctl dev reset"
      ;;
  esac
}

cmd_config_show() {
  local active kernel build_status build_time config_source

  prepare

  active="$(active_subscription_name 2>/dev/null || true)"
  kernel="$(runtime_kernel_type 2>/dev/null || echo mihomo)"
  build_status="$(status_build_last_status 2>/dev/null || true)"
  build_time="$(status_build_last_time 2>/dev/null || true)"
  config_source="$(status_runtime_config_source 2>/dev/null || true)"

  ui_title "🧩 配置编译管理"
  ui_kv "🚩" "当前主订阅" "${active:-未设置}"
  ui_kv "🚀" "当前内核" "${kernel:-mihomo}"
  ui_kv "🧩" "编译模式" "active-only"
  ui_kv "🐱" "最近构建" "${build_status:-unknown}${build_time:+ @ ${build_time}}"
  ui_kv "🧩" "配置来源" "${config_source:-unknown}"
  ui_blank
  ui_next "clashctl status"
  ui_blank
}

cmd_config() {
  prepare

  case "${1:-}" in
    show)
      cmd_config_show
      ;;
    explain)
      print_build_explain
      ;;
    regen)
      regenerate_config
      apply_runtime_change_after_config_mutation
      print_config_regen_feedback
      print_config_apply_feedback
      ;;
    kernel)
      shift || true
      [ -n "${1:-}" ] || die_usage "内核类型不能为空" "clashctl config kernel <mihomo|clash>"
      write_runtime_kernel_type "$1"
      resolve_runtime_kernel
      regenerate_config
      apply_runtime_change_after_config_mutation
      print_config_kernel_feedback "$(runtime_kernel_type)"
      print_config_apply_feedback
      ;;
    "")
      ui_title "🧩 配置编译管理"
      echo "📜 用法："
      echo "  clashctl config show"
      echo "  clashctl config explain"
      echo "  clashctl config regen"
      echo "  clashctl config kernel <mihomo|clash>"
      echo
      echo "🧩 说明："
      echo "  当前编译链固定为 active-only"
      echo "  只处理当前 active 主订阅"
      echo
      ui_next "clashctl config show"
      ui_blank
      ;;
    *)
      die_usage "未知的 config 子命令：$1" "clashctl config"
      ;;
  esac
}

print_lan_status() {
  local allow_lan mixed_port lan_ip

  allow_lan="$(runtime_config_allow_lan 2>/dev/null || config_allow_lan 2>/dev/null || echo true)"
  mixed_port="$(status_read_mixed_port 2>/dev/null || runtime_config_mixed_port 2>/dev/null || true)"
  lan_ip="$(ui_lan_ip 2>/dev/null || true)"

  ui_title "🏠 局域网代理"
  if [ "$allow_lan" = "true" ]; then
    ui_kv "📶" "状态" "已开启"
    if [ -n "${lan_ip:-}" ] && [ -n "${mixed_port:-}" ] && [ "$mixed_port" != "null" ]; then
      ui_kv "🏠" "局域网代理" "http://${lan_ip}:${mixed_port}"
    else
      ui_kv "🏠" "局域网代理" "等待运行配置生成"
    fi
  else
    ui_kv "📶" "状态" "已关闭"
  fi
  ui_kv "🔧" "配置项" "allow-lan: ${allow_lan}"
  ui_blank
}

cmd_lan() {
  local action
  prepare

  action="${1:-status}"
  case "$action" in
    on|enable)
      set_config_allow_lan true
      regenerate_config
      apply_runtime_change_after_config_mutation
      success "局域网代理已开启"
      print_lan_status
      print_config_apply_feedback
      ;;
    off|disable)
      set_config_allow_lan false
      regenerate_config
      apply_runtime_change_after_config_mutation
      success "局域网代理已关闭"
      print_lan_status
      print_config_apply_feedback
      ;;
    status)
      print_lan_status
      ui_next "clashctl lan on"
      ui_blank
      ;;
    -h|--help|help|"")
      echo "📜 用法："
      echo "  clashctl lan status"
      echo "  clashctl lan on"
      echo "  clashctl lan off"
      ;;
    *)
      die_usage "未知的 lan 子命令：$action" "clashctl lan on|off|status"
      ;;
  esac
}

print_profile_use_feedback() {
  local profile="$1"

  ui_title "🔧 Profile 已切换"
  ui_kv "🔧" "当前 Profile" "$profile"
  main_feedback_runtime_state
  ui_next "clashctl status"
  ui_blank
}

cmd_profile() {
  prepare

  echo "⚠ 当前版本未启用 Profile 功能"
  return 0
}

mixin_config_file() {
  ensure_mixin_file
  echo "$(mixin_file)"
}

active_subscription_runtime_raw_file() {
  local name="$1"
  echo "$RUNTIME_DIR/tmp/source-${name}.yaml"
}

ensure_mixin_runtime_prepared() {
  local active source_file

  active="$(active_subscription_name 2>/dev/null || true)"
  [ -n "${active:-}" ] || die "当前没有活动订阅"

  subscription_exists "$active" || die "当前活动订阅不存在：$active"

  source_file="$(active_subscription_runtime_raw_file "$active")"
  mkdir -p "$RUNTIME_DIR/tmp"

  if [ -s "$source_file" ]; then
    echo "$source_file"
    return 0
  fi

  if fetch_subscription_source "$active" "$source_file"; then
    echo "$source_file"
    return 0
  fi

  rm -f "$source_file" 2>/dev/null || true
  die "无法获取当前活动订阅原始配置：$active"
}

open_editor_for_file() {
  local file="$1"
  local editor

  [ -n "${file:-}" ] || die "文件路径不能为空"
  touch "$file"

  if [ -n "${EDITOR:-}" ]; then
    editor="$EDITOR"
  elif command -v nano >/dev/null 2>&1; then
    editor="nano"
  elif command -v vim >/dev/null 2>&1; then
    editor="vim"
  elif command -v vi >/dev/null 2>&1; then
    editor="vi"
  else
    die "未找到可用编辑器，请先设置 EDITOR 环境变量"
  fi

  "$editor" "$file"
}

cmd_mixin_show() {
  local file
  prepare
  ensure_config_files
  file="$(mixin_config_file)"

  ui_title "🧩 Mixin 配置"
  ui_kv "🧩" "作用" "对原始订阅配置进行补充、覆盖或前后置合并"
  ui_kv "🔧" "配置文件" "$file"
  ui_blank
  if mixin_config_is_empty "$file"; then
    print_mixin_template_example
  else
    cat "$file"
    if mixin_config_has_secret_override "$file"; then
      ui_warn "检测到 override.secret：该字段已忽略，请改用 clashctl secret <密钥>"
    fi
  fi
  ui_blank
  ui_next "clashctl mixin edit"
  ui_blank
}

mixin_config_is_empty() {
  local file="$1"
  local compact noop

  [ -s "$file" ] || return 0

  if [ -x "$(yq_bin)" ]; then
    noop="$("$(yq_bin)" eval '
      ((.override // {}) == {}) and
      (((.prepend.proxies // []) | length) == 0) and
      (((.prepend["proxy-groups"] // []) | length) == 0) and
      (((.prepend.rules // []) | length) == 0) and
      (((.append.proxies // []) | length) == 0) and
      (((.append["proxy-groups"] // []) | length) == 0) and
      (((.append.rules // []) | length) == 0)
    ' "$file" 2>/dev/null | head -n 1 || true)"
    [ "$noop" = "true" ] && return 0
  fi

  compact="$(tr -d '[:space:]' < "$file" 2>/dev/null || true)"
  case "$compact" in
    ""|"{}")
      return 0
      ;;
  esac

  return 1
}

mixin_config_has_secret_override() {
  local file="$1"
  local exists

  [ -s "$file" ] || return 1
  [ -x "$(yq_bin)" ] || return 1

  exists="$("$(yq_bin)" eval '
    (.override // {}) as $override |
    (($override | type) == "!!map" and ($override | has("secret")))
  ' "$file" 2>/dev/null | head -n 1 || true)"

  [ "$exists" = "true" ]
}

print_mixin_template_example() {
  cat <<'EOF'
当前 mixin 还没有实际补丁。可按这个结构填写：

override:
  mixed-port: 7890
  dns:
    enable: true

prepend:
  proxies: []
  proxy-groups: []
  rules:
    - DOMAIN-SUFFIX,example.com,DIRECT

append:
  proxies: []
  proxy-groups: []
  rules:
    - MATCH,节点选择

说明：
  override 会覆盖同名字段
  override.secret 会被忽略，控制器密钥只从 .env 的 CLASH_CONTROLLER_SECRET 读取
  prepend 会把数组内容放到原始订阅前面
  append 会把数组内容放到原始订阅后面
EOF
}

cmd_mixin_edit() {
  local file
  prepare
  ensure_config_files
  file="$(mixin_config_file)"

  open_editor_for_file "$file"

  echo
  echo "ℹ️ 正在重新生成配置 ..."
  regenerate_config

  if status_is_running; then
    service_restart
    echo "🐱 Mixin 已生效（已自动重启）"
  else
    echo "🟡 Mixin 已写入（下次启动生效）"
  fi

  echo "👉 下一步：clashctl mixin runtime"
  echo
}

cmd_mixin_raw() {
  local file
  prepare
  file="$(ensure_mixin_runtime_prepared)"

  echo
  echo "📡 原始订阅配置"
  echo
  echo "📡 说明：这是当前活动订阅拉取到的原始配置，不包含 Mixin 最终合并结果"
  echo "🔧 来源文件：$file"
  echo
  cat "$file"
  echo
  echo "👉 下一步：clashctl mixin runtime"
  echo
}

cmd_mixin_runtime() {
  local file
  prepare
  file="$RUNTIME_DIR/config.yaml"

  [ -s "$file" ] || die "🧩 运行时配置不存在：$file"

  echo
  echo "🧩 运行时配置"
  echo
  echo "🧩 说明：这是当前内核真正加载的最终配置"
  echo "🔧 配置文件：$file"
  echo
  cat "$file"
  echo
  echo "👉 下一步：clashctl status"
  echo
}

cmd_mixin() {
  case "${1:-}" in
    "")
      cmd_mixin_show
      ;;
    edit|-e|--edit)
      cmd_mixin_edit
      ;;
    raw|-c|--raw)
      cmd_mixin_raw
      ;;
    runtime|-r|--runtime)
      cmd_mixin_runtime
      ;;
    help|-h|--help)
      ui_title "🧩 Mixin 配置管理"
      echo "📜 用法："
      echo "  clashctl mixin"
      echo "  clashctl mixin edit"
      echo "  clashctl mixin raw"
      echo "  clashctl mixin runtime"
      echo
      echo "🧩 说明："
      echo "  mixin 用于补充、覆盖或前后置合并原始订阅配置"
      echo "  runtime 展示当前内核真正加载的最终配置"
      echo
      echo "💡 常用动作："
      echo "  clashctl mixin"
      echo "  clashctl mixin edit"
      echo "  clashctl mixin runtime"
      echo
      echo "⚡ 快捷参数："
      echo "  clashctl mixin -e"
      echo "  clashctl mixin -c"
      echo "  clashctl mixin -r"
      echo
      ui_next "clashctl mixin"
      ui_blank
      ;;
    *)
      die_usage "未知的 mixin 子命令：$1" "clashctl mixin"
      ;;
  esac
}

ensure_relay_mixin_file() {
  local file
  ensure_config_files
  file="$(mixin_config_file)"

  [ -s "$file" ] || cat > "$file" <<'EOF'
override: {}
prepend:
  proxies: []
  proxy-groups: []
  rules: []
append:
  proxies: []
  proxy-groups: []
  rules: []
EOF

  "$(yq_bin)" eval -i '
    .override = (.override // {}) |
    .prepend = (.prepend // {}) |
    .prepend.proxies = (.prepend.proxies // []) |
    .prepend["proxy-groups"] = (.prepend["proxy-groups"] // []) |
    .prepend.rules = (.prepend.rules // []) |
    .append = (.append // {}) |
    .append.proxies = (.append.proxies // []) |
    .append["proxy-groups"] = (.append["proxy-groups"] // []) |
    .append.rules = (.append.rules // [])
  ' "$file"

  echo "$file"
}

relay_apply_mixin_change() {
  echo
  echo "ℹ️ 正在重新生成配置 ..."
  regenerate_config

  if status_is_running; then
    service_restart
    echo "🐱 多跳配置已生效（已自动重启）"
  else
    echo "🟡 多跳配置已写入（下次启动生效）"
  fi
}

cmd_relay_add() {
  local name rule="" domain="" match_mode="false" file node
  local nodes=()

  prepare
  [ -x "$(yq_bin)" ] || die_state "依赖未就绪：缺少 yq（$(yq_bin)）" "请先执行 bash install.sh"

  name="${1:-}"
  [ -n "${name:-}" ] || die_usage "缺少多跳名称" "clashctl relay add <名称> <节点A> <节点B> [更多节点] [--domain 域名|--match]"
  shift || true

  while [ $# -gt 0 ]; do
    case "$1" in
      --domain)
        shift || true
        [ -n "${1:-}" ] || die_usage "--domain 缺少域名" "clashctl relay add <名称> <节点A> <节点B> --domain example.com"
        domain="$1"
        ;;
      --match)
        match_mode="true"
        ;;
      --)
        shift || true
        while [ $# -gt 0 ]; do
          nodes+=("$1")
          shift
        done
        break
        ;;
      --*)
        die_usage "未知 relay add 参数：$1" "clashctl relay add <名称> <节点A> <节点B> [--domain 域名|--match]"
        ;;
      *)
        nodes+=("$1")
        ;;
    esac
    shift || true
  done

  [ "${#nodes[@]}" -ge 2 ] || die_usage "多跳至少需要两个节点" "clashctl relay add <名称> <节点A> <节点B>"

  if [ -n "${domain:-}" ] && [ "$match_mode" = "true" ]; then
    die_usage "--domain 与 --match 只能选择一个" "clashctl relay add <名称> <节点A> <节点B> [--domain 域名|--match]"
  fi

  if [ -n "${domain:-}" ]; then
    rule="DOMAIN-SUFFIX,${domain},${name}"
  elif [ "$match_mode" = "true" ]; then
    rule="MATCH,${name}"
  fi

  file="$(ensure_relay_mixin_file)"

  RELAY_NAME="$name" "$(yq_bin)" eval -i '
    .append["proxy-groups"] = ((.append["proxy-groups"] // []) | map(select(.name != strenv(RELAY_NAME)))) |
    .append["proxy-groups"] += [{"name": strenv(RELAY_NAME), "type": "relay", "proxies": []}]
  ' "$file"

  for node in "${nodes[@]}"; do
    RELAY_NAME="$name" RELAY_NODE="$node" "$(yq_bin)" eval -i '
      (.append["proxy-groups"][] | select(.name == strenv(RELAY_NAME)).proxies) += [strenv(RELAY_NODE)]
    ' "$file"
  done

  if [ -n "${rule:-}" ]; then
    RELAY_RULE="$rule" "$(yq_bin)" eval -i '
      .prepend.rules = ([strenv(RELAY_RULE)] + (.prepend.rules // []) | unique)
    ' "$file"
  fi

  ui_title "🔗 多跳配置已更新"
  ui_kv "🔧" "配置文件" "$file"
  ui_kv "🔗" "多跳名称" "$name"
  ui_kv "🧩" "节点链路" "$(printf '%s\n' "${nodes[@]}" | awk 'BEGIN{out=""} {out=(out?out" -> ":"")$0} END{print out}')"
  [ -n "${rule:-}" ] && ui_kv "📜" "新增规则" "$rule"

  relay_apply_mixin_change
  echo "👉 下一步：clashctl relay list"
  echo
}

cmd_relay_list() {
  local file output
  prepare
  [ -x "$(yq_bin)" ] || die_state "依赖未就绪：缺少 yq（$(yq_bin)）" "请先执行 bash install.sh"

  file="$(ensure_relay_mixin_file)"
  output="$("$(yq_bin)" eval '
    (.append["proxy-groups"] // [])[] |
    select(.type == "relay") |
    "  " + .name + "： " + ((.proxies // []) | join(" -> "))
  ' "$file" 2>/dev/null || true)"

  ui_title "🔗 多跳节点"
  ui_kv "🔧" "配置文件" "$file"
  ui_blank

  if [ -n "${output:-}" ]; then
    printf '%s\n' "$output"
  else
    echo "当前没有通过 mixin 配置的多跳组"
    ui_next "clashctl relay add 多跳-示例 节点A 节点B --domain example.com"
  fi
  ui_blank
}

cmd_relay_remove() {
  local name file
  prepare
  [ -x "$(yq_bin)" ] || die_state "依赖未就绪：缺少 yq（$(yq_bin)）" "请先执行 bash install.sh"

  name="${1:-}"
  [ -n "${name:-}" ] || die_usage "缺少多跳名称" "clashctl relay remove <名称>"

  file="$(ensure_relay_mixin_file)"
  RELAY_NAME="$name" "$(yq_bin)" eval -i '
    .append["proxy-groups"] = ((.append["proxy-groups"] // []) | map(select(.name != strenv(RELAY_NAME)))) |
    .prepend.rules = ((.prepend.rules // []) | map(select((. | endswith("," + strenv(RELAY_NAME))) | not))) |
    .append.rules = ((.append.rules // []) | map(select((. | endswith("," + strenv(RELAY_NAME))) | not)))
  ' "$file"

  ui_title "🔗 多跳配置已删除"
  ui_kv "🔧" "配置文件" "$file"
  ui_kv "🔗" "多跳名称" "$name"

  relay_apply_mixin_change
  echo "👉 下一步：clashctl relay list"
  echo
}

cmd_relay() {
  case "${1:-}" in
    add)
      shift || true
      cmd_relay_add "$@"
      ;;
    list|ls|"")
      cmd_relay_list
      ;;
    remove|rm|delete)
      shift || true
      cmd_relay_remove "$@"
      ;;
    help|-h|--help)
      ui_title "🔗 多跳节点管理"
      echo "📜 用法："
      echo "  clashctl relay add <名称> <节点A> <节点B> [更多节点] [--domain 域名|--match]"
      echo "  clashctl relay list"
      echo "  clashctl relay remove <名称>"
      echo
      echo "示例："
      echo "  clashctl relay add 多跳-示例 节点A 节点B --domain example.com"
      echo "  clashctl relay add 全局多跳 节点A 节点B --match"
      echo
      echo "说明："
      echo "  add 会写入 runtime/mixin.yaml（兼容读取 config/mixin.yaml），并重新生成运行配置"
      echo "  --domain 用于小范围测试，--match 会让所有未提前命中的流量走多跳"
      echo "  节点名称必须与订阅生成的节点名完全一致"
      ;;
    *)
      die_usage "未知的 relay 子命令：$1" "clashctl relay help"
      ;;
  esac
}

runtime_config_exists() {
  [ -s "$RUNTIME_DIR/config.yaml" ]
}

doctor_risk_level() {
  local running controller_ok config_ok

  running="false"
  controller_ok="false"
  config_ok="false"

  status_is_running && running="true"
  proxy_controller_reachable 2>/dev/null && controller_ok="true"
  runtime_config_exists && config_ok="true"

  if runtime_mixed_port_bind_failure_kind >/dev/null 2>&1; then
    echo "high"
    return
  fi

  if [ "$running" = "true" ] && [ "$controller_ok" = "true" ] && [ "$config_ok" = "true" ]; then
    echo "low"
    return
  fi

  if [ "$running" = "false" ]; then
    echo "medium"
    return
  fi

  if [ "$controller_ok" = "false" ]; then
    echo "high"
    return
  fi

  echo "medium"
}

doctor_risk_text() {
  case "$(doctor_risk_level)" in
    low) echo "🐱 低" ;;
    medium) echo "🟡 中" ;;
    high) echo "❗ 高" ;;
    *) echo "⚪ 未知" ;;
  esac
}

doctor_problem_lines() {
  local active_sub bind_failure_text mixed_port

  active_sub="$(active_subscription_name 2>/dev/null || true)"
  bind_failure_text="$(runtime_mixed_port_bind_failure_text 2>/dev/null || true)"
  mixed_port="$(runtime_mixed_port_bind_failure_port 2>/dev/null || status_read_mixed_port 2>/dev/null || true)"

  if ! runtime_config_exists; then
    echo "🚨 运行配置缺失"
  fi

  if [ -n "${bind_failure_text:-}" ]; then
    echo "🚨 ${bind_failure_text}${mixed_port:+：${mixed_port}}"
  elif ! status_is_running; then
    echo "🚨 代理内核未运行"
  fi

  if status_is_running && ! proxy_controller_reachable 2>/dev/null; then
    echo "🚨 控制器不可访问"
  fi

  if [ -n "${active_sub:-}" ] && ! active_subscription_enabled 2>/dev/null; then
    echo "🚨 当前主订阅不可用"
  fi

  if [ "$(status_build_last_status 2>/dev/null || true)" = "failed" ]; then
    echo "🚨 最近一次编译失败"
  fi

  if [ "$(tun_enabled 2>/dev/null || echo false)" = "true" ] \
    && [ "$(system_proxy_status 2>/dev/null || echo off)" = "on" ]; then
    echo "🚨 Tun 模式与系统代理同时开启"
  fi
}

doctor_primary_conclusion() {
  if ! runtime_config_exists; then
    echo "❗ 当前不可用：缺少运行配置"
    return 0
  fi

  if ! status_is_running; then
    case "$(runtime_mixed_port_bind_failure_kind 2>/dev/null || true)" in
      bind_denied)
        echo "❗ 当前不可用：mixed-port 绑定被拒绝"
        mixed_port_bind_observation_line | sed -n '1p' | sed 's/^/   /'
        return 0
        ;;
      address_in_use)
        echo "❗ 当前不可用：mixed-port 端口被占用"
        mixed_port_bind_observation_line | sed -n '1p' | sed 's/^/   /'
        return 0
        ;;
      bind_failed)
        echo "❗ 当前不可用：mixed-port 绑定失败"
        mixed_port_bind_observation_line | sed -n '1p' | sed 's/^/   /'
        return 0
        ;;
    esac

    echo "🟡 当前未连接：代理内核未启动"
    return 0
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    echo "❗ 当前异常：内核已启动，但控制器不可访问"
    return 0
  fi

  echo "🐱 当前基本可用：代理内核与控制器均正常"
}

doctor_recommendation_lines() {
  local active_sub bind_failure_kind system_proxy_text mixed_port

  active_sub="$(active_subscription_name 2>/dev/null || true)"
  bind_failure_kind="$(runtime_mixed_port_bind_failure_kind 2>/dev/null || true)"
  system_proxy_text="$(persistent_system_proxy_text 2>/dev/null || echo unknown)"
  mixed_port="$(status_read_mixed_port 2>/dev/null || true)"

  if ! runtime_config_exists; then
    if [ -n "$(subscription_url 2>/dev/null || true)" ]; then
      echo "💡 clashctl config regen"
    else
      echo "💡 clashctl add <订阅链接>"
    fi
    return 0
  fi

  if [ -n "${bind_failure_kind:-}" ]; then
    mixed_port_bind_recommendation_lines icon
    return 0
  elif ! status_is_running; then
    echo "💡 clashon"
    return 0
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    echo "💡 clashctl logs service"
    echo "💡 clashctl off && clashon"
    return 0
  fi

  if [ -n "${active_sub:-}" ] && ! active_subscription_enabled 2>/dev/null; then
    echo "💡 clashctl use"
    echo "💡 clashctl ls"
    return 0
  fi

  if [ "$(status_build_last_status 2>/dev/null || true)" = "failed" ]; then
    echo "💡 clashctl config regen"
    echo "💡 clashctl doctor"
    return 0
  fi

  if [ "$(tun_enabled 2>/dev/null || echo false)" = "true" ] \
    && [ "$(system_proxy_status 2>/dev/null || echo off)" = "on" ]; then
    echo "💡 clashctl tun on-proxy-off"
    echo "💡 如需恢复普通系统代理模式：clashctl tun off-proxy-on"
    return 0
  fi

  case "$system_proxy_text" in
    unsupported|off)
      if [ -n "${mixed_port:-}" ] && [ "$mixed_port" != "null" ]; then
        echo "💡 浏览器/应用手动设置 HTTP 代理：http://127.0.0.1:${mixed_port}"
      fi
      echo "💡 当前 Shell 可使用 clashon 注入代理变量"
      ;;
    mismatch)
      echo "💡 clashoff && clashon"
      ;;
    *)
      echo "💡 clashctl status"
      echo "💡 clashctl select"
      ;;
  esac
}

doctor_evidence_lines() {
  local active_sub mixed_port controller bind_failure_kind bind_failure_line dns_port
  local system_proxy_text process_proxy_env tun_state system_proxy_state

  active_sub="$(active_subscription_name 2>/dev/null || true)"
  mixed_port="$(runtime_mixed_port_bind_failure_port 2>/dev/null || status_read_mixed_port 2>/dev/null || true)"
  controller="$(status_read_controller 2>/dev/null || true)"
  bind_failure_kind="$(runtime_mixed_port_bind_failure_kind 2>/dev/null || true)"
  bind_failure_line="$(runtime_mixed_port_bind_failure_line 2>/dev/null || true)"
  dns_port="$(runtime_config_dns_port 2>/dev/null || true)"
  system_proxy_text="$(persistent_system_proxy_text 2>/dev/null || echo unknown)"
  process_proxy_env="$(current_process_proxy_env_text 2>/dev/null || echo unknown)"
  tun_state="$(tun_enabled 2>/dev/null || echo false)"
  system_proxy_state="$(system_proxy_status 2>/dev/null || echo off)"

  if runtime_config_exists; then
    echo "🔍 运行配置：存在"
  else
    echo "🔍 运行配置：缺失"
  fi

  if status_is_running; then
    echo "🔍 服务状态：运行中"
  else
    echo "🔍 服务状态：未运行"
  fi

  if proxy_controller_reachable 2>/dev/null; then
    echo "🔍 控制器状态：可访问"
  else
    echo "🔍 控制器状态：不可访问"
  fi

  if [ -n "${bind_failure_kind:-}" ]; then
    echo "🔍 mixed-port 绑定错误：${bind_failure_kind}"
    echo "🔍 mixed-port 环境：$(mixed_port_bind_environment_text 2>/dev/null || echo unknown)"
    if runtime_mixed_port_controller_listening 2>/dev/null; then
      echo "🔍 控制器监听：已确认"
    else
      echo "🔍 控制器监听：未确认"
    fi
    if [ -n "${dns_port:-}" ]; then
      if runtime_mixed_port_dns_listening 2>/dev/null; then
        echo "🔍 DNS 监听：${dns_port}（已确认）"
      else
        echo "🔍 DNS 监听：${dns_port}（未确认）"
      fi
    fi
    [ -n "${bind_failure_line:-}" ] && echo "🔍 日志证据：${bind_failure_line}"
  fi

  if [ -n "${active_sub:-}" ]; then
    if active_subscription_enabled 2>/dev/null; then
      echo "🔍 当前订阅：${active_sub}（可用）"
    else
      echo "🔍 当前订阅：${active_sub}（不可用）"
    fi
  else
    echo "🔍 当前订阅：未设置"
  fi

  if [ -n "${mixed_port:-}" ] && [ "$mixed_port" != "null" ]; then
    if is_port_in_use "$mixed_port"; then
      echo "🔍 代理端口：${mixed_port}（已监听）"
    else
      echo "🔍 代理端口：${mixed_port}（未监听）"
    fi
    echo "🔍 本地代理：http://127.0.0.1:${mixed_port}"
  fi

  if [ -n "${controller:-}" ] && [ "$controller" != "null" ]; then
    echo "🔍 控制器地址：$(display_controller_local_addr "$controller" 2>/dev/null || echo "$controller")"
  fi

  echo "🔍 系统代理持久接管：${system_proxy_text}"
  echo "🔍 当前命令环境代理：${process_proxy_env}"
  echo "🔍 Tun 与系统代理：tun=${tun_state}, system_proxy=${system_proxy_state}"
}

set_controller_secret() {
  local secret="$1"

  is_valid_controller_secret "$secret" || die "密钥不能为空"

  write_env_value "CLASH_CONTROLLER_SECRET" "$secret"
  export CLASH_CONTROLLER_SECRET="$secret"
}

sync_runtime_controller_secret_from_env() {
  local file="$RUNTIME_DIR/config.yaml"
  local secret

  [ -s "$file" ] || return 0
  [ -x "$(yq_bin)" ] || return 1

  secret="$(ensure_controller_secret)"
  SECRET_VALUE="$secret" "$(yq_bin)" eval -i '
    .secret = strenv(SECRET_VALUE)
  ' "$file"
}

show_controller_secret_from_env() {
  local current_secret

  current_secret="$(read_env_value "CLASH_CONTROLLER_SECRET" 2>/dev/null || true)"
  if ! is_valid_controller_secret "$current_secret"; then
    current_secret="${CLASH_CONTROLLER_SECRET:-}"
  fi

  echo
  if is_valid_controller_secret "$current_secret"; then
    ui_kv "🔑" "当前密钥" "$current_secret"
  else
    ui_kv "🚨" "当前密钥" "未设置"
  fi

  ui_kv "🔧" "密钥来源" "$PROJECT_DIR/.env"
  ui_blank
}

print_controller_secret_apply_feedback() {
  local synced="${1:-true}"

  echo

  if [ "$synced" = "true" ]; then
    if status_is_running; then
      service_restart
      ui_kv "🐱" "状态" "密钥更新成功，已重启生效"
    else
      ui_kv "🐱" "状态" "将在下次启动时生效"
    fi
  else
    ui_warn "运行时配置暂未同步：缺少 yq 或写入失败，请稍后执行 clashctl config regen"
    ui_kv "🐱" "状态" "密钥已写入 .env，运行时配置同步后生效"
  fi

  ui_kv "🔧" "密钥来源" "$PROJECT_DIR/.env"
  ui_blank
}

cmd_secret() {
  local new_secret synced

  prepare

  if [ "$#" -eq 0 ]; then
    show_controller_secret_from_env
    return 0
  fi

  [ "$#" -eq 1 ] || die_usage "secret 参数不合法" "clashctl secret <密钥>"

  new_secret="$1"
  set_controller_secret "$new_secret"

  synced="true"
  sync_runtime_controller_secret_from_env || synced="false"
  print_controller_secret_apply_feedback "$synced"
}

cmd_tun_status() {
  local enabled stack env_type effective_status

  prepare
  enabled="$(tun_enabled)"
  stack="$(tun_stack)"
  env_type="$(container_env_type)"
  effective_status="$(status_tun_effective_status 2>/dev/null || echo ineffective)"

  echo
  echo "🧪 Tun 状态"
  echo

  if [ "$enabled" = "true" ]; then
    echo "🐱 当前状态：已开启"
  else
    echo "❗ 当前状态：未开启"
  fi

  echo "🔧  Tun stack：$stack"
  echo "💻 环境类型：$env_type"

  if can_manage_tun_safely; then
    echo "🐱 环境检查：满足基础开启条件"
  else
    echo "🚨 环境检查：当前不满足基础开启条件"
  fi

  if [ "$effective_status" = "effective" ]; then
    echo "🐱 已生效"
  else
    echo "❗ 未生效"
  fi

  if [ "$enabled" = "true" ]; then
    echo "👉 下一步：clashctl tun doctor"
  else
    echo "👉 下一步：clashctl tun on"
  fi
  echo
}

cmd_tun_on() {
  local verify_result
  local container_mode risk_reason

  guard_sudo_on_user_install "on" || return 1

  prepare

  container_mode="$(tun_container_mode 2>/dev/null || echo unknown)"
  risk_reason="$(tun_container_risk_reason 2>/dev/null || true)"

  case "$container_mode" in
    host)
      ;;
    container-safe)
      ui_warn "当前处于容器环境，Tun 将按保守模式尝试开启"
      [ -n "${risk_reason:-}" ] && ui_warn "$risk_reason"
      ;;
    container-risky)
      mark_tun_last_action "on" "blocked" "${risk_reason:-container-risky}"
      mark_tun_last_verification "blocked" "${risk_reason:-container-risky}"
      print_tun_container_gate_feedback "$container_mode" "${risk_reason:-容器环境不满足 Tun 基础条件}"
      return 1
      ;;
    *)
      ui_warn "无法识别当前 Tun 容器模式，按高风险处理"
      mark_tun_last_action "on" "blocked" "unknown-container-mode"
      mark_tun_last_verification "blocked" "unknown-container-mode"
      print_tun_container_gate_feedback "container-risky" "unknown-container-mode"
      return 1
      ;;
  esac

  if ! can_manage_tun_safely; then
    # Fallback: check if the running mihomo process already has CAP_NET_ADMIN
    # (covers the case where setcap was applied after the binary check fails
    # due to getcap being unavailable, or the process received the capability
    # through another mechanism).
    local _fb_backend
    _fb_backend="$(runtime_backend 2>/dev/null || echo unknown)"
    if ! tun_process_has_cap_net_admin "$_fb_backend" 2>/dev/null; then
      echo
      echo "❗ Tun 模式无法开启"
      echo "🚨 原因：当前环境不满足基础 Tun 条件"
      echo "💡 若已通过 setcap 授权 mihomo，请确认 getcap 已安装并重试"
      echo "👉 下一步：clashctl tun doctor"
      echo
      return 1
    fi
  fi

  case "$(tun_kernel_support_level 2>/dev/null || echo unknown)" in
    full)
      ;;
    limited)
      ui_warn "$(tun_kernel_support_reason 2>/dev/null || echo '当前内核仅对 Tun 提供降级支持')"
      ;;
    *)
      ui_warn "当前内核的 Tun 支持等级未知，请谨慎开启"
      ;;
  esac

  if ! sync_tun_target_state "on" "true"; then
    return 1
  fi

  if status_is_running; then
    service_restart
  fi

  verify_result="$(tun_effective_check 2>/dev/null || true)"
  [ -n "${verify_result:-}" ] || verify_result="unknown"
  verify_result="$(tun_on_verify_result "$verify_result")"

  case "$verify_result" in
    ok)
      mark_tun_last_action "on" "success" "effective"
      mark_tun_last_verification "success" "effective"
      ;;
    policy-routing-likely-effective)
      mark_tun_last_action "on" "success" "$verify_result"
      mark_tun_last_verification "success" "$verify_result"
      ;;
    *)
      mark_tun_last_action "on" "partial" "$verify_result"
      mark_tun_last_verification "partial" "$verify_result"
      ;;
  esac

  print_tun_on_feedback "$verify_result"
}

cmd_tun_off() {
  local verify_result

  guard_sudo_on_user_install "off" || return 1

  prepare

  if ! sync_tun_target_state "off" "false"; then
    return 1
  fi

  if status_is_running; then
    service_restart
  fi

  verify_result="$(tun_disable_check 2>/dev/null || true)"
  [ -n "${verify_result:-}" ] || verify_result="unknown"

  if [ "$verify_result" = "ok" ]; then
    mark_tun_last_action "off" "success" "rolled-back"
    mark_tun_last_verification "success" "disabled"
  else
    mark_tun_last_action "off" "partial" "$verify_result"
    mark_tun_last_verification "partial" "$verify_result"
  fi

  print_tun_off_feedback "$verify_result"
}

cmd_tun_on_proxy_off() {
  local system_proxy_rc

  cmd_tun_on || return $?

  if boot_proxy_keep_disable; then
    ui_blank
    ui_ok "系统代理已关闭，当前使用 Tun 模式接管"
    ui_blank
    return 0
  fi

  system_proxy_rc=$?
  if [ "$system_proxy_rc" -eq 2 ]; then
    ui_warn "当前环境不支持清理系统代理持久块，Tun 已按前序结果处理"
  else
    ui_warn "系统代理持久块清理失败，Tun 已按前序结果处理"
  fi
  ui_next "clashctl doctor"
  ui_blank
  return "$system_proxy_rc"
}

cmd_tun_off_proxy_on() {
  local system_proxy_rc

  cmd_tun_off || return $?

  if system_proxy_enable; then
    ui_blank
    ui_ok "系统代理已开启，当前使用本地代理接管"
    ui_blank
    return 0
  fi

  system_proxy_rc=$?
  write_runtime_value "RUNTIME_BOOT_PROXY_KEEP" "false" 2>/dev/null || true
  if [ "$system_proxy_rc" -eq 2 ]; then
    ui_warn "当前环境不支持系统代理持久接管，Tun 已按前序结果处理"
  else
    ui_warn "系统代理持久接管写入失败，Tun 已按前序结果处理"
  fi
  ui_next "clashctl doctor"
  ui_blank
  return "$system_proxy_rc"
}

tun_runtime_status_text() {
  if [ "$(tun_enabled)" = "true" ]; then
    echo "已开启"
  else
    echo "未开启"
  fi
}

doctor_tun_checks() {
  local env_type stack runtime_tun_status backend dns_listen_value
  local runtime_tun_enabled runtime_tun_stack runtime_tun_auto_route runtime_tun_auto_redirect
  local effective_result route_dev primary_reason cap_rc route_takeover
  local process_cap_rc
  local problem_lines recommendation_lines rc

  trap 'rc=$?; tun_doctor_report_failure "doctor_tun_checks" "$rc" "$BASH_COMMAND"; trap - ERR; return "$rc"' ERR

  prepare

  echo
  echo "🐱 Tun 诊断"
  echo

  runtime_tun_status="$(tun_runtime_status_text)"
  stack="$(tun_stack)"
  backend="$(runtime_backend)"
  env_type="$(container_env_type)"

  runtime_tun_enabled="$(runtime_config_tun_enabled 2>/dev/null || echo false)"
  runtime_tun_stack="$(runtime_config_tun_stack 2>/dev/null || echo "")"
  runtime_tun_auto_route="$(runtime_config_tun_auto_route 2>/dev/null || echo false)"
  runtime_tun_auto_redirect="$(runtime_config_tun_auto_redirect 2>/dev/null || echo false)"
  route_dev="$(default_route_dev 2>/dev/null || true)"
  route_takeover="unknown"
  if [ -n "${route_dev:-}" ]; then
    if default_route_is_tun_like 2>/dev/null; then
      route_takeover="yes"
    else
      route_takeover="no"
    fi
  fi
  if has_cap_net_admin >/dev/null 2>&1; then
    cap_rc=0
  else
    cap_rc=$?
  fi
  process_cap_rc=2
  case "$backend" in
    systemd|systemd-user)
      if tun_process_has_cap_net_admin "$backend" >/dev/null 2>&1; then
        process_cap_rc=0
      else
        process_cap_rc=$?
      fi
      ;;
  esac

  echo "【总体结论】"
  if [ "$process_cap_rc" -eq 0 ]; then
    echo "🐱 mihomo 进程已检测到 CAP_NET_ADMIN；当前执行环境 capability 不作为主因"
  elif [ "$cap_rc" -eq 1 ]; then
    echo "❗ 当前执行环境未检测到 CAP_NET_ADMIN；root 不等于一定拥有 CAP_NET_ADMIN"
  elif can_manage_tun_safely; then
    echo "🐱 当前环境满足基础 Tun 开启条件"
  else
    echo "❗ 当前环境不满足基础 Tun 开启条件"
  fi
  echo "🧪 Tun 是否生效要看 mihomo 进程实际拿到的网络管理能力，能力边界可能来自 systemd unit 或容器环境"
  echo "🧪 当前 Tun 状态：$runtime_tun_status"
  echo "🔧  Tun stack：$stack"
  echo "🔧  运行后端：$backend"
  echo "🚀 当前内核：$(runtime_kernel_type 2>/dev/null || echo unknown)"
  echo "🧩 Tun 支持等级：$(tun_kernel_support_text 2>/dev/null || echo 未知)"
  echo "💻 环境类型：$env_type"
  echo "📜 容器裁决：$(tun_container_mode_text 2>/dev/null || echo 未知)"
  echo "💡 内核说明：$(tun_kernel_support_reason 2>/dev/null || echo 未知)"

  if [ "$(tun_container_mode 2>/dev/null || echo unknown)" = "container-risky" ]; then
    local gate_reason
    gate_reason="$(tun_container_risk_reason 2>/dev/null || true)"
    [ -n "${gate_reason:-}" ] && echo "❗ 阻断原因：$gate_reason"
  fi
  echo

  echo "【发现的问题】"
  problem_lines="$(tun_problem_lines)" || {
    rc=$?
    tun_doctor_report_failure "tun_problem_lines" "$rc" "collect problem lines"
    trap - ERR
    return "$rc"
  }
  if [ -n "${problem_lines:-}" ]; then
    printf '%s\n' "$problem_lines" | sed 's/^/  /'
  else
    echo "  🐱 未发现明显问题"
  fi
  echo

  echo "【关键证据】"
  if is_root_user; then
    echo "  🐱 当前执行用户：root"
  else
    echo "  🚨 当前执行用户：非 root"
  fi
  echo "  🔧 运行后端：$backend"
  echo "  💻 是否容器：$(tun_doctor_container_evidence_text "$env_type")"

  if tun_device_exists; then
    echo "  🐱 /dev/net/tun：存在"
  else
    echo "  ❗ /dev/net/tun：不存在"
  fi

  if tun_device_exists; then
    if tun_device_readable; then
      echo "  🐱 /dev/net/tun：可读写"
    else
      echo "  🚨 /dev/net/tun：存在但不可正常读写"
    fi
  fi

  case "$cap_rc" in
    0)
      echo "  🐱 CAP_NET_ADMIN：已检测到"
      ;;
    2)
      echo "  🚨 CAP_NET_ADMIN：无法精确判断（缺少 capsh）"
      ;;
    *)
      echo "  🚨 CAP_NET_ADMIN：未检测到"
      ;;
  esac

  if has_ip_command; then
    echo "  🐱 ip 命令：可用"
  else
    echo "  🚨 ip 命令：缺失"
  fi

  if runtime_config_exists; then
    dns_listen_value="$("$(yq_bin)" eval '.dns.listen // ""' "$RUNTIME_DIR/config.yaml" 2>/dev/null | head -n 1)"
    if [ -n "${dns_listen_value:-}" ] && [ "$dns_listen_value" != "null" ]; then
      echo "  🐱 DNS 监听：$dns_listen_value"
    else
      echo "  🚨 DNS 监听：未解析到"
    fi

    echo "  🧩 runtime tun.enable：${runtime_tun_enabled:-false}"
    if [ -n "${runtime_tun_stack:-}" ] && [ "$runtime_tun_stack" != "null" ]; then
      echo "  🧩 runtime tun.stack：$runtime_tun_stack"
    fi
    echo "  📜 runtime tun.auto-route：${runtime_tun_auto_route:-false}"
    echo "  📜 runtime tun.auto-redirect：${runtime_tun_auto_redirect:-false}"
    if [ "${runtime_tun_auto_redirect:-false}" != "true" ] \
      && [ "$env_type" = "host" ] \
      && [ "$(runtime_kernel_type 2>/dev/null || echo mihomo)" = "mihomo" ]; then
      echo "  💡 auto-redirect 建议：裸 TCP 透明接管超时时，设置 CLASH_TUN_AUTO_REDIRECT=true 后重新执行 clashctl tun on"
    fi
  else
    echo "  🚨 运行时配置：不存在"
  fi

  if [ -n "${route_dev:-}" ]; then
    echo "  🌐 默认路由设备：$route_dev"
    case "$route_takeover" in
      yes)
        echo "  🐱 默认路由接管：看起来已接管（设备命中 tun/clash/mihomo 特征）"
        ;;
      no)
        echo "  📜 主默认路由：仍指向 $route_dev（仅代表 main table；Linux Tun 可通过 policy routing / rule table 生效）"
        ;;
      *)
        echo "  📜 主默认路由：未知"
        ;;
    esac
  else
    echo "  🚨 默认路由设备：未解析到"
    echo "  📜 主默认路由：未知"
  fi
  echo "  🧪 Tun 状态文件：$runtime_tun_status"
  echo "  📜 mihomo 进程能力：$(tun_process_capability_text "$backend")"
  echo "  📜 unit capability：$(tun_unit_capability_text "$backend")"
  tun_doctor_log_evidence
  tun_doctor_policy_evidence
  tun_doctor_ip_rule_evidence
  tun_doctor_route_table_evidence
  echo

  echo "【生效验证】"
  if [ "$(tun_enabled 2>/dev/null || echo false)" = "true" ]; then
    effective_result="$(tun_effective_check 2>/dev/null || true)"
    primary_reason="$(tun_doctor_primary_reason "$effective_result" "$backend" "$route_takeover")" || {
      rc=$?
      tun_doctor_report_failure "tun_doctor_primary_reason" "$rc" "derive primary reason"
      trap - ERR
      return "$rc"
    }

    tun_doctor_conclusion_line "$primary_reason" | sed 's/^/  /'
  else
    primary_reason="$(tun_doctor_primary_reason "tun-disabled" "$backend" "$route_takeover")" || {
      rc=$?
      tun_doctor_report_failure "tun_doctor_primary_reason" "$rc" "derive primary reason"
      trap - ERR
      return "$rc"
    }
    tun_doctor_conclusion_line "$primary_reason" | sed 's/^/  /'
  fi
  echo

  echo "【建议操作】"
  recommendation_lines="$(tun_recommendation_lines "$primary_reason")" || {
    rc=$?
    tun_doctor_report_failure "tun_recommendation_lines" "$rc" "collect recommendation lines"
    trap - ERR
    return "$rc"
  }
  printf '%s\n' "$recommendation_lines" | sed 's/^/  /'
  echo

  trap - ERR
}

tun_doctor_report_failure() {
  local function_name="$1"
  local rc="$2"
  local step="$3"

  echo
  ui_error "Tun doctor 中途失败：$function_name"
  ui_kv "!" "失败步骤" "${step:-unknown}"
  ui_kv "!" "返回码" "$rc"
  ui_next "请带着上面的失败点重新排查或提交问题"
  echo
}

tun_doctor_container_evidence_text() {
  case "${1:-unknown}" in
    host)
      echo "否（host）"
      ;;
    docker|container|lxc)
      echo "是（$1）"
      ;;
    *)
      echo "未知（${1:-unknown}）"
      ;;
  esac
}

tun_runtime_pid() {
  local backend="${1:-unknown}"
  local pid_file pid unit

  unit="$(service_unit_name 2>/dev/null || echo clash-for-linux.service)"
  case "$backend" in
    systemd)
      if command -v systemctl >/dev/null 2>&1; then
        pid="$(systemctl show "$unit" --property MainPID --value 2>/dev/null || true)"
        if [ -n "${pid:-}" ] && [ "$pid" != "0" ]; then
          echo "$pid"
          return 0
        fi
      fi
      ;;
    systemd-user)
      if command -v systemctl >/dev/null 2>&1; then
        pid="$(systemctl --user show "$unit" --property MainPID --value 2>/dev/null || true)"
        if [ -n "${pid:-}" ] && [ "$pid" != "0" ]; then
          echo "$pid"
          return 0
        fi
      fi
      ;;
  esac

  pid_file="$RUNTIME_DIR/mihomo.pid"
  if [ -f "$pid_file" ]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "${pid:-}" ]; then
      echo "$pid"
      return 0
    fi
  fi

  return 1
}

tun_process_capability_text() {
  local backend="${1:-unknown}"
  local pid=""
  local cap_eff=""
  local cap_value=0
  local net_admin="no"
  local net_raw="no"

  pid="$(tun_runtime_pid "$backend" 2>/dev/null || true)"
  if [ -z "${pid:-}" ] || [ ! -r "/proc/$pid/status" ]; then
    echo "未读取到运行中 mihomo 进程能力"
    return 0
  fi

  cap_eff="$(
    sed -nE 's/^CapEff:[[:space:]]*([0-9a-fA-F]+)$/\1/p' "/proc/$pid/status" 2>/dev/null \
      | head -n 1
  )"

  if [ -z "${cap_eff:-}" ]; then
    echo "pid=$pid，未读取到 CapEff"
    return 0
  fi

  case "$cap_eff" in
    *[!0-9a-fA-F]*)
      echo "pid=$pid，CapEff 格式异常：$cap_eff"
      return 0
      ;;
  esac

  cap_value=$((16#$cap_eff))

  if (( cap_value & (1 << 12) )); then
    net_admin="yes"
  fi

  if (( cap_value & (1 << 13) )); then
    net_raw="yes"
  fi

  echo "pid=$pid，CapEff=$cap_eff，CAP_NET_ADMIN=$net_admin，CAP_NET_RAW=$net_raw"
}

tun_process_has_cap_net_admin() {
  local backend="${1:-unknown}"
  local pid=""
  local cap_eff=""
  local cap_value=0

  pid="$(tun_runtime_pid "$backend" 2>/dev/null || true)"
  [ -n "${pid:-}" ] && [ -r "/proc/$pid/status" ] || return 2

  cap_eff="$(
    sed -nE 's/^CapEff:[[:space:]]*([0-9a-fA-F]+)$/\1/p' "/proc/$pid/status" 2>/dev/null \
      | head -n 1
  )"

  [ -n "${cap_eff:-}" ] || return 2

  case "$cap_eff" in
    *[!0-9a-fA-F]*)
      return 2
      ;;
  esac

  cap_value=$((16#$cap_eff))

  if (( cap_value & (1 << 12) )); then
    return 0
  fi

  return 1
}

tun_log_tun_adapter_line() {
  local log_file="$LOG_DIR/mihomo.out.log"
  [ -f "$log_file" ] || return 1

  grep -E '\[TUN\].*Tun adapter|Tun adapter listening' "$log_file" 2>/dev/null | tail -n 1
}

tun_log_tun_adapter_cidrs() {
  local adapter_line

  adapter_line="$(tun_log_tun_adapter_line 2>/dev/null || true)"
  [ -n "${adapter_line:-}" ] || return 1

  printf '%s\n' "$adapter_line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' 2>/dev/null
}

tun_ipv4_to_int() {
  local ip="$1"
  local a b c d octet n value

  IFS=. read -r a b c d <<EOF
$ip
EOF

  [ -n "${a:-}" ] && [ -n "${b:-}" ] && [ -n "${c:-}" ] && [ -n "${d:-}" ] || return 1

  value=0
  for octet in "$a" "$b" "$c" "$d"; do
    case "$octet" in
      ''|*[!0-9]*)
        return 1
        ;;
    esac

    n=$((10#$octet))
    [ "$n" -ge 0 ] && [ "$n" -le 255 ] || return 1
    value=$(((value << 8) + n))
  done

  printf '%s\n' "$value"
}

tun_ipv4_in_cidr() {
  local ip="$1"
  local cidr="$2"
  local base prefix ip_value base_value mask

  base="${cidr%/*}"
  prefix="${cidr#*/}"

  case "$prefix" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  prefix=$((10#$prefix))
  [ "$prefix" -ge 0 ] && [ "$prefix" -le 32 ] || return 1

  ip_value="$(tun_ipv4_to_int "$ip" 2>/dev/null)" || return 1
  base_value="$(tun_ipv4_to_int "$base" 2>/dev/null)" || return 1

  if [ "$prefix" -eq 0 ]; then
    mask=0
  else
    mask=$(((0xffffffff << (32 - prefix)) & 0xffffffff))
  fi

  [ $((ip_value & mask)) -eq $((base_value & mask)) ]
}

tun_ipv4_in_default_tun_range() {
  case "$1" in
    28.*|198.18.*|198.19.*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

tun_log_source_ip_is_tun() {
  local ip="$1"
  local cidrs="${2:-}"
  local cidr

  tun_ipv4_in_default_tun_range "$ip" && return 0

  [ -n "${cidrs:-}" ] || cidrs="$(tun_log_tun_adapter_cidrs 2>/dev/null || true)"
  [ -n "${cidrs:-}" ] || return 1

  while IFS= read -r cidr; do
    [ -n "${cidr:-}" ] || continue
    tun_ipv4_in_cidr "$ip" "$cidr" && return 0
  done <<EOF
$cidrs
EOF

  return 1
}

tun_log_line_source_ip() {
  sed -nE 's/.*(^|[^0-9])(([0-9]{1,3}\.){3}[0-9]{1,3}):[0-9]+.*-->.*/\2/p' \
    | tail -n 1
}

tun_log_tun_source_line() {
  local log_file="$LOG_DIR/mihomo.out.log"
  local adapter_cidrs line source_ip matched_line

  [ -f "$log_file" ] || return 1
  adapter_cidrs="$(tun_log_tun_adapter_cidrs 2>/dev/null || true)"

  while IFS= read -r line; do
    case "$line" in
      *'-->'*) ;;
      *) continue ;;
    esac

    source_ip="$(printf '%s\n' "$line" | tun_log_line_source_ip 2>/dev/null || true)"
    [ -n "${source_ip:-}" ] || continue

    if tun_log_source_ip_is_tun "$source_ip" "$adapter_cidrs"; then
      matched_line="$line"
    fi
  done < "$log_file"

  [ -n "${matched_line:-}" ] || return 1
  printf '%s\n' "$matched_line"
}

tun_log_has_tun_traffic_evidence() {
  tun_log_tun_adapter_line >/dev/null 2>&1 || return 1
  tun_log_tun_source_line >/dev/null 2>&1 || return 1
}

tun_policy_rule_line() {
  has_ip_command 2>/dev/null || return 1
  ip rule show 2>/dev/null \
    | grep -E '(lookup 2022|iif Meta|not from all iif lo lookup 2022)' \
    | head -n 1
}

tun_policy_route_line() {
  has_ip_command 2>/dev/null || return 1
  ip route show table all 2>/dev/null \
    | grep -E '(^|[[:space:]])default .* dev (Meta|tun|utun|mihomo|clash)([[:space:]].*)? table 2022|table 2022 .*default .* dev (Meta|tun|utun|mihomo|clash)' \
    | head -n 1
}

tun_has_policy_routing_evidence() {
  tun_log_tun_adapter_line >/dev/null 2>&1 || return 1
  tun_policy_rule_line >/dev/null 2>&1 || return 1
  tun_policy_route_line >/dev/null 2>&1 || return 1
}

tun_doctor_ip_rule_evidence() {
  if ! has_ip_command 2>/dev/null; then
    echo "  🚨 ip rule：缺少 ip 命令，无法读取"
    return 0
  fi

  echo "  📜 ip rule："
  ip rule show 2>/dev/null | sed 's/^/    /' || echo "    读取失败"
}

tun_doctor_route_table_evidence() {
  if ! has_ip_command 2>/dev/null; then
    echo "  🚨 ip route table all：缺少 ip 命令，无法读取"
    return 0
  fi

  echo "  📜 ip route show table all："
  ip route show table all 2>/dev/null | sed -n '1,80p' | sed 's/^/    /' || echo "    读取失败"
}

tun_doctor_log_evidence() {
  local adapter_line traffic_line

  adapter_line="$(tun_log_tun_adapter_line 2>/dev/null || true)"
  traffic_line="$(tun_log_tun_source_line 2>/dev/null || true)"

  if [ -n "${adapter_line:-}" ]; then
    echo "  🐱 Tun adapter 日志：$adapter_line"
  else
    echo "  🚨 Tun adapter 日志：未在 mihomo.out.log 中找到"
  fi

  if [ -n "${traffic_line:-}" ]; then
    echo "  🐱 Tun 流量日志：$traffic_line"
  else
    echo "  🚨 Tun 流量日志：未发现明确 Tun 源地址流量"
  fi
}

tun_doctor_policy_evidence() {
  local rule_line route_line

  rule_line="$(tun_policy_rule_line 2>/dev/null || true)"
  route_line="$(tun_policy_route_line 2>/dev/null || true)"

  if [ -n "${rule_line:-}" ]; then
    echo "  🐱 Tun policy rule：$rule_line"
  else
    echo "  🚨 Tun policy rule：未发现 lookup 2022 / iif Meta 相关规则"
  fi

  if [ -n "${route_line:-}" ]; then
    echo "  🐱 Tun policy route：$route_line"
  else
    echo "  🚨 Tun policy route：未发现 table 2022 默认路由指向 Meta/tun 设备"
  fi
}

tun_unit_capability_text() {
  local backend="${1:-unknown}"
  local unit unit_file content

  unit="$(service_unit_name 2>/dev/null || echo clash-for-linux.service)"
  case "$backend" in
    systemd)
      if command -v systemctl >/dev/null 2>&1; then
        content="$(systemctl cat "$unit" 2>/dev/null || true)"
      fi
      unit_file="/etc/systemd/system/$unit"
      ;;
    systemd-user)
      if command -v systemctl >/dev/null 2>&1; then
        content="$(systemctl --user cat "$unit" 2>/dev/null || true)"
      fi
      unit_file="$HOME/.config/systemd/user/$unit"
      ;;
    *)
      echo "非 systemd 后端，不适用 unit capability 声明"
      return 0
      ;;
  esac

  if [ -z "${content:-}" ] && [ -f "$unit_file" ]; then
    content="$(cat "$unit_file" 2>/dev/null || true)"
  fi

  if [ -z "${content:-}" ]; then
    echo "未读取到 unit 内容，无法判断是否显式声明 capability"
    return 0
  fi

  if printf '%s\n' "$content" | grep -Eq '^(AmbientCapabilities|CapabilityBoundingSet)=.*CAP_NET_(ADMIN|RAW)'; then
    printf '%s\n' "$content" \
      | grep -E '^(AmbientCapabilities|CapabilityBoundingSet)=' \
      | tr '\n' ';' \
      | sed 's/;$//;s/^/已显式声明：/'
    return 0
  fi

  if printf '%s\n' "$content" | grep -Eq '^(AmbientCapabilities|CapabilityBoundingSet)='; then
    printf '%s\n' "$content" \
      | grep -E '^(AmbientCapabilities|CapabilityBoundingSet)=' \
      | tr '\n' ';' \
      | sed 's/;$//;s/^/已声明 capability，但未看到 CAP_NET_ADMIN 或 CAP_NET_RAW：/'
    return 0
  fi

  echo "未看到 AmbientCapabilities/CapabilityBoundingSet 显式声明"
}

tun_doctor_primary_reason() {
  local effective_result backend route_takeover cap_rc process_cap_rc

  effective_result="${1:-unknown}"
  backend="${2:-unknown}"
  route_takeover="${3:-unknown}"

  process_cap_rc=2
  case "$backend" in
    systemd|systemd-user)
      if tun_process_has_cap_net_admin "$backend" >/dev/null 2>&1; then
        process_cap_rc=0
      else
        process_cap_rc=$?
      fi
      ;;
  esac

  if tun_has_policy_routing_evidence 2>/dev/null; then
    case "$effective_result" in
      ok)
        echo "ok"
        return 0
        ;;
      disabled-in-state|disabled-in-runtime-config|tun-disabled|runtime-not-running|controller-unreachable)
        ;;
      *)
        echo "policy-routing-likely-effective"
        return 0
        ;;
    esac
  fi

  if [ "$process_cap_rc" -eq 0 ]; then
    case "$effective_result" in
      ok)
        echo "ok"
        return 0
        ;;
      disabled-in-state|disabled-in-runtime-config|tun-disabled|runtime-not-running|controller-unreachable)
        ;;
      host-ip-unavailable|current-ip-unavailable|traffic-same-as-host)
        if [ "$route_takeover" = "no" ]; then
          echo "main-route-unchanged-needs-policy-check"
          return 0
        fi
        ;;
      *)
        if [ "$route_takeover" = "no" ]; then
          echo "main-route-unchanged-needs-policy-check"
          return 0
        fi
        ;;
    esac
  fi

  if tun_log_has_tun_traffic_evidence 2>/dev/null; then
    case "$effective_result" in
      ok)
        echo "ok"
        return 0
        ;;
      disabled-in-state|disabled-in-runtime-config|tun-disabled|runtime-not-running|controller-unreachable)
        ;;
      *)
        echo "main-route-unchanged-needs-policy-check"
        return 0
        ;;
    esac
  fi

  if has_cap_net_admin >/dev/null 2>&1; then
    cap_rc=0
  else
    cap_rc=$?
  fi
  if [ "$cap_rc" -eq 1 ] && [ "$process_cap_rc" -ne 0 ]; then
    echo "missing-cap-net-admin"
    return 0
  fi

  if ! tun_device_exists 2>/dev/null; then
    echo "missing-tun-device"
    return 0
  fi

  if tun_device_exists 2>/dev/null && ! tun_device_readable 2>/dev/null; then
    echo "tun-device-not-readable"
    return 0
  fi

  if ! has_ip_command 2>/dev/null; then
    echo "missing-ip-command"
    return 0
  fi

  if [ "$route_takeover" = "no" ]; then
    case "$effective_result" in
      ok|disabled-in-state|disabled-in-runtime-config|tun-disabled|runtime-not-running|controller-unreachable)
        ;;
      *)
        echo "main-route-unchanged-needs-policy-check"
        return 0
        ;;
    esac
  fi

  case "$effective_result" in
    controller-unreachable|runtime-not-running|disabled-in-state|disabled-in-runtime-config|tun-disabled|host-ip-unavailable|current-ip-unavailable|traffic-same-as-host|default-route-not-tun|main-route-unchanged-needs-policy-check)
      echo "$effective_result"
      ;;
    *)
      if [ "$route_takeover" = "no" ]; then
        echo "main-route-unchanged-needs-policy-check"
        return 0
      fi
      echo "traffic-check-failed"
      ;;
  esac
}

tun_doctor_conclusion_line() {
  case "${1:-traffic-check-failed}" in
    ok)
      if tun_has_policy_routing_evidence 2>/dev/null; then
        echo "🐱 最终状态：已生效（Tun + policy routing + 主动流量验证通过）"
      else
        echo "🐱 最终状态：已生效（主动流量验证通过）"
      fi
      ;;
    policy-routing-likely-effective)
      if tun_log_tun_source_line >/dev/null 2>&1; then
        echo "🐱 最终状态：已生效（Tun + policy routing 已安装，并观察到 Tun 源地址流量）"
      else
        echo "🟡 最终状态：很可能已生效（Tun + policy routing 已安装；主动流量验证不足 / 未观察到明确 Tun 源地址日志）"
      fi
      ;;
    missing-cap-net-admin)
      echo "❗ Tun 未生效：当前能力检测未通过（CAP_NET_ADMIN）"
      ;;
    missing-tun-device)
      echo "❗ Tun 未生效：缺少 /dev/net/tun"
      ;;
    tun-device-not-readable)
      echo "❗ Tun 未生效：/dev/net/tun 不可读写"
      ;;
    missing-ip-command)
      echo "❗ Tun 未生效：缺少 ip 命令"
      ;;
    runtime-not-running)
      echo "❗ Tun 未生效：代理内核未运行"
      ;;
    controller-unreachable)
      echo "❗ Tun 未生效：控制器不可访问"
      ;;
    disabled-in-state|disabled-in-runtime-config)
      echo "❗ Tun 未生效：Tun 状态与运行配置不一致"
      ;;
    tun-disabled)
      echo "❗ Tun 未生效：Tun 未开启"
      ;;
    host-ip-unavailable|current-ip-unavailable)
      echo "❗ Tun 未生效：无法完成公网出口验证"
      ;;
    traffic-same-as-host)
      if tun_log_has_tun_traffic_evidence 2>/dev/null; then
        echo "🟡 流量出口验证仍与本机公网 IP 一致，但已看到 Tun adapter 与 Tun 源地址流量；需进一步确认是否为策略路由/部分生效"
      else
        echo "🟡 主动流量验证不足 / 未观察到明确 Tun 源地址日志；需结合 policy routing 证据确认"
      fi
      ;;
    default-route-not-tun|main-route-unchanged-needs-policy-check)
      if tun_log_has_tun_traffic_evidence 2>/dev/null; then
        echo "🟡 主默认路由仍指向物理网卡，但已看到 Tun adapter 与 Tun 源地址流量；需进一步确认是否为策略路由/部分生效"
      else
        echo "🟡 主默认路由仍指向物理网卡；需结合 ip rule / table all / 日志确认是否为策略路由或部分生效"
      fi
      ;;
    *)
      echo "🟡 主动流量验证不足 / 未观察到明确 Tun 源地址日志；需结合 policy routing 证据确认"
      ;;
  esac
}

tun_doctor_action_lines() {
  local reason backend unit

  reason="${1:-traffic-check-failed}"
  backend="$(runtime_backend 2>/dev/null || echo unknown)"
  unit="$(service_unit_name 2>/dev/null || echo clash-for-linux.service)"

  case "$reason" in
    missing-cap-net-admin)
      if [ "$(container_env_type 2>/dev/null || echo unknown)" != "host" ]; then
        tun_container_runtime_hint_lines || true
      else
        case "$backend" in
          systemd)
            echo "👉 当前运行后端为 systemd；若关键证据显示 unit 未声明能力，可尝试为服务显式补 CAP_NET_ADMIN / CAP_NET_RAW："
            echo "   sudo systemctl edit $unit"
            ;;
          systemd-user)
            echo "👉 当前运行后端为 systemd-user；请结合容器与 unit 证据判断，必要时改用系统服务或显式补 CAP_NET_ADMIN / CAP_NET_RAW"
            ;;
          script)
            echo "👉 当前运行后端为 script；请确认启动 mihomo 的实际进程具备 CAP_NET_ADMIN / CAP_NET_RAW"
            echo "👉 若当前就是主机脚本模式，可尝试提升权限后重新执行：sudo clashctl tun on"
            ;;
          *)
            echo "👉 请结合运行后端、容器环境和进程能力证据，确认 mihomo 实际拥有 CAP_NET_ADMIN / CAP_NET_RAW"
            ;;
        esac
      fi
      ;;
    missing-tun-device)
      if [ "$(container_env_type 2>/dev/null || echo unknown)" != "host" ]; then
        tun_container_runtime_hint_lines || true
      else
        echo "👉 请先挂载或启用 /dev/net/tun"
      fi
      ;;
    tun-device-not-readable)
      echo "👉 请修复 /dev/net/tun 权限，确保当前运行用户可读写"
      ;;
    missing-ip-command)
      if [ "$(container_env_type 2>/dev/null || echo unknown)" != "host" ]; then
        tun_container_runtime_hint_lines || true
      else
        case "$(install_env_os_variant 2>/dev/null || true)" in
          openwrt)
            echo "👉 当前环境缺少 ip 命令；OpenWrt 可安装：opkg update && opkg install ip-full"
            ;;
          *)
            echo "👉 Debian/Ubuntu 可安装：apt update && apt install -y iproute2"
            echo "👉 其他发行版请安装提供 ip 命令的 iproute / iproute2 软件包"
            ;;
        esac
      fi
      ;;
    runtime-not-running)
      echo "👉 请先启动代理：clashon"
      ;;
    controller-unreachable)
      echo "👉 请先修复控制器可访问性：clashctl doctor"
      ;;
    disabled-in-state|disabled-in-runtime-config)
      echo "👉 请重新同步 Tun 配置：clashctl tun off && clashctl tun on"
      ;;
    tun-disabled)
      echo "👉 请开启 Tun：clashctl tun on"
      ;;
    host-ip-unavailable|current-ip-unavailable)
      echo "👉 请先确认服务器可访问 https://ip.sb：curl https://ip.sb"
      ;;
    traffic-same-as-host)
      if tun_log_has_tun_traffic_evidence 2>/dev/null; then
        echo "👉 已看到 Tun 流量证据，但公网出口验证仍未通过；请结合 ip rule、ip route show table all 和内核日志判断是否为策略路由/部分生效"
      else
        echo "👉 当前流量仍走本机出口，请检查 Tun 路由规则和内核日志：clashctl logs"
      fi
      ;;
    default-route-not-tun|main-route-unchanged-needs-policy-check)
      echo "👉 主默认路由仍指向物理网卡；请结合 ip rule、ip route show table all 和 Tun 流量日志确认是否为策略路由/部分生效"
      ;;
    policy-routing-likely-effective)
      if tun_log_tun_source_line >/dev/null 2>&1; then
        echo "👉 已看到 Tun policy routing 与 Tun 源地址流量；如仍有访问异常，请重点检查分流规则和内核日志：clashctl logs"
      else
        echo "👉 Tun policy routing 已安装；主动流量验证不足，建议发起一次直连外网访问后重新执行：clashctl tun doctor"
      fi
      ;;
    *)
      echo "👉 请查看运行日志定位流量验证失败原因：clashctl logs"
      ;;
  esac
}

tun_recommendation_lines() {
  local enabled env_type can_enable container_mode risk_reason
  local effective_result disable_result
  local config_tun_enabled auto_route
  local kernel_support backend route_takeover route_dev
  local primary_reason

  primary_reason="${1:-}"
  kernel_support="$(tun_kernel_support_level 2>/dev/null || echo unknown)"
  backend="$(runtime_backend 2>/dev/null || echo unknown)"
  enabled="$(tun_enabled 2>/dev/null || echo false)"
  env_type="$(container_env_type 2>/dev/null || echo unknown)"
  container_mode="$(tun_container_mode 2>/dev/null || echo unknown)"
  risk_reason="$(tun_container_risk_reason 2>/dev/null || true)"
  config_tun_enabled="$(runtime_config_tun_enabled 2>/dev/null || echo false)"
  auto_route="$(runtime_config_tun_auto_route 2>/dev/null || echo false)"
  route_dev="$(default_route_dev 2>/dev/null || true)"
  route_takeover="unknown"
  if [ -n "${route_dev:-}" ]; then
    if default_route_is_tun_like 2>/dev/null; then
      route_takeover="yes"
    else
      route_takeover="no"
    fi
  fi

  can_enable="false"
  if can_manage_tun_safely 2>/dev/null; then
    can_enable="true"
  fi

  if [ "$enabled" != "true" ] && [ -n "${primary_reason:-}" ] && [ "$primary_reason" != "tun-disabled" ]; then
    tun_doctor_action_lines "$primary_reason"
    return 0
  fi

  if [ "$kernel_support" = "limited" ] && [ "$enabled" != "true" ]; then
    echo "1. 当前内核为 clash，Tun 仅按降级支持处理"
    echo "2. 如需最稳妥 Tun 体验，建议先执行：clashctl config kernel mihomo"
    echo "3. 再开启 Tun：clashctl tun on"
    return 0
  fi

  if [ "$enabled" = "true" ]; then
    effective_result="$(tun_effective_check 2>/dev/null || true)"
    [ -n "${effective_result:-}" ] || effective_result="unknown"
    [ -n "${primary_reason:-}" ] || primary_reason="$(tun_doctor_primary_reason "$effective_result" "$backend" "$route_takeover")"

    if [ "$effective_result" != "ok" ]; then
      tun_doctor_action_lines "$primary_reason"
      return 0
    fi

    echo "1. Tun 已生效，可继续使用"
    echo "2. 如需恢复普通代理模式，执行：clashctl tun off"
    if [ "$kernel_support" = "limited" ]; then
      echo "3. 当前 Tun 运行在 clash 内核上，如需更稳妥体验可切换：clashctl config kernel mihomo"
    fi

    return 0
  fi

  disable_result="$(tun_disable_check 2>/dev/null || true)"
  [ -n "${disable_result:-}" ] || disable_result="unknown"

  if [ "$disable_result" != "ok" ]; then
    echo "1. Tun 关闭后仍有残留，建议执行：clashctl tun off"
    echo "2. 如仍异常，执行：clashoff && clashon"
    return 0
  fi

  if [ "$can_enable" != "true" ]; then
    case "$container_mode" in
      container-risky)
        echo "👉 当前容器环境已被裁决为高风险：${risk_reason:-容器条件不足}"
        tun_container_runtime_hint_lines || true
        echo "👉 条件满足后再执行：clashctl tun on"
        ;;
      *)
        echo "1. 当前环境不满足 Tun 基础条件"
        echo "2. 优先检查：/dev/net/tun、CAP_NET_ADMIN、ip 命令"
        echo "3. 条件满足后再执行：clashctl tun on"
        ;;
    esac
    return 0
  fi

  if [ "${config_tun_enabled:-false}" = "true" ] && [ "$enabled" != "true" ]; then
    echo "1. 当前运行配置仍保留 Tun 开启状态"
    echo "2. 建议先执行：clashctl tun off"
    echo "3. 再观察：clashctl tun doctor"
    return 0
  fi

  case "$container_mode" in
    container-safe)
      echo "1. 当前容器环境已通过保守裁决，可尝试开启 Tun：clashctl tun on"
      echo "2. 开启后立即执行：clashctl tun doctor"
      echo "3. 若未生效，优先检查宿主机权限与设备映射"
      return 0
      ;;
    container-risky)
      echo "👉 当前容器环境属于高风险，不建议直接开启 Tun：${risk_reason:-容器条件不足}"
      tun_container_runtime_hint_lines || true
      echo "👉 修复后再执行：clashctl tun on"
      return 0
      ;;
  esac

  echo "1. 当前环境可尝试开启 Tun：clashctl tun on"
  echo "2. 开启后建议立即执行：clashctl tun doctor"
}

tun_problem_lines() {
  local enabled env_type config_tun_enabled auto_route
  local effective_result disable_result route_dev
  local container_mode risk_reason
  local last_action_result last_action_reason last_action_time
  local kernel_support
  kernel_support="$(tun_kernel_support_level 2>/dev/null || echo unknown)"
  container_mode="$(tun_container_mode 2>/dev/null || echo unknown)"
  risk_reason="$(tun_container_risk_reason 2>/dev/null || true)"
  last_action_result="$(status_tun_last_action_result 2>/dev/null || true)"
  last_action_reason="$(status_tun_last_action_reason 2>/dev/null || true)"
  last_action_time="$(status_tun_last_action_time 2>/dev/null || true)"

  enabled="$(tun_enabled 2>/dev/null || echo false)"
  env_type="$(container_env_type 2>/dev/null || echo unknown)"
  config_tun_enabled="$(runtime_config_tun_enabled 2>/dev/null || echo false)"
  auto_route="$(runtime_config_tun_auto_route 2>/dev/null || echo false)"
  route_dev="$(default_route_dev 2>/dev/null || true)"

  if ! tun_device_exists 2>/dev/null; then
    echo "• /dev/net/tun 不存在"
  fi

  if tun_device_exists 2>/dev/null && ! tun_device_readable 2>/dev/null; then
    echo "• /dev/net/tun 存在但不可正常读写"
  fi

  if ! has_ip_command 2>/dev/null; then
    echo "• 缺少 ip 命令，无法进行完整路由校验"
  fi

  if ! can_manage_tun_safely 2>/dev/null; then
    echo "• 当前环境不满足 Tun 安全开启条件"
  fi

  if [ "$env_type" != "host" ]; then
    case "$container_mode" in
      container-safe)
        echo "• 当前处于容器环境，Tun 虽可尝试开启，但建议重点关注流量验证结果"
        ;;
      container-risky)
        echo "• 当前处于高风险容器环境：${risk_reason:-容器条件不足}"
        ;;
      *)
        echo "• 当前处于容器环境，Tun 状态未知"
        ;;
    esac
  fi

  case "$kernel_support" in
    limited)
      echo "• 当前内核为 clash，Tun 仅按降级支持处理，稳定性可能弱于 mihomo"
      ;;
    unknown)
      echo "• 当前内核的 Tun 支持等级未知"
      ;;
  esac

  if [ "${last_action_result:-}" = "failed" ]; then
    if [ -n "${last_action_time:-}" ]; then
      echo "• 最近一次 Tun 配置同步失败：${last_action_reason:-unknown} @ ${last_action_time}"
    else
      echo "• 最近一次 Tun 配置同步失败：${last_action_reason:-unknown}"
    fi
  fi

  if ! runtime_config_exists 2>/dev/null; then
    echo "• 运行时配置不存在"
    return 0
  fi

  if [ "$enabled" = "true" ] && [ "${config_tun_enabled:-false}" != "true" ]; then
    echo "• Tun 状态文件已开启，但 runtime/config.yaml 未启用 tun.enable"
  fi

  if [ "$enabled" != "true" ] && [ "${config_tun_enabled:-false}" = "true" ]; then
    echo "• Tun 状态文件已关闭，但 runtime/config.yaml 仍启用 tun.enable"
  fi

  if [ "$enabled" = "true" ]; then
    effective_result="$(tun_effective_check 2>/dev/null || true)"
    if [ "$effective_result" != "ok" ]; then
      if tun_has_policy_routing_evidence 2>/dev/null; then
        if tun_log_tun_source_line >/dev/null 2>&1; then
          echo "• Tun + policy routing 已安装，并观察到 Tun 源地址流量；主动出口验证仍需结合场景确认"
        else
          echo "• Tun + policy routing 已安装；主动流量验证不足 / 未观察到明确 Tun 源地址日志"
        fi
      elif tun_log_has_tun_traffic_evidence 2>/dev/null; then
        echo "• 已看到 Tun adapter 与 Tun 源地址流量；需结合 policy routing 证据确认覆盖范围"
      else
        echo "• 主动流量验证不足 / 未观察到明确 Tun 源地址日志"
      fi
    fi
  else
    disable_result="$(tun_disable_check 2>/dev/null || true)"
    if [ "$disable_result" != "ok" ]; then
      echo "• Tun 当前虽为关闭态，但仍存在残留：${disable_result:-unknown}"
    fi
  fi
}

sync_tun_target_state() {
  local action="$1"
  local target="$2"
  local previous sync_output rc error_summary

  previous="$(tun_enabled 2>/dev/null || echo false)"
  set_tun_enabled "$target"

  if sync_output="$(regenerate_config 2>&1)"; then
    return 0
  fi

  rc=$?
  set_tun_enabled "$previous"

  error_summary="$(build_last_error_summary 2>/dev/null || true)"
  if [ -z "${error_summary:-}" ]; then
    error_summary="$(printf '%s\n' "$sync_output" | sed '/^[[:space:]]*$/d' | tail -n 1)"
  fi
  error_summary="$(single_line_text "${error_summary:-配置重建失败}")"
  [ -n "${error_summary:-}" ] || error_summary="配置重建失败"

  mark_tun_last_action "$action" "failed" "$error_summary"
  mark_tun_last_verification "failed" "config-sync-failed"

  ui_error "Tun 配置同步失败，已回滚状态文件"
  ui_error "$error_summary"
  ui_next "clashctl tun doctor"
  return "$rc"
}

cmd_tun() {
  case "${1:-}" in
    ""|status)
      cmd_tun_status
      ;;
    on)
      cmd_tun_on
      ;;
    off)
      cmd_tun_off
      ;;
    on-proxy-off|proxy-off)
      cmd_tun_on_proxy_off
      ;;
    off-proxy-on|proxy-on)
      cmd_tun_off_proxy_on
      ;;
    log|logs)
      cmd_logs mihomo
      ;;
    doctor)
      doctor_tun_checks
      ;;
    *)
      ui_title "🧪 Tun 模式管理"
      echo "📜 用法："
      echo "  clashctl tun"
      echo "  clashctl tun status"
      echo "  clashctl tun on"
      echo "  clashctl tun off"
      echo "  clashctl tun on-proxy-off"
      echo "  clashctl tun off-proxy-on"
      echo "  clashctl tun doctor"
      echo "  clashctl tun logs"
      echo
      echo "🧩 说明："
      echo "  Tun 属于高级接管能力"
      echo "  开启前应确认环境支持 /dev/net/tun、权限与网络能力"
      echo
      echo "💡 常用动作："
      echo "  clashctl tun status"
      echo "  clashctl tun doctor"
      echo "  clashtun on"
      echo
      ui_next "clashctl tun doctor"
      ui_blank
      ;;
  esac
}

add_trim_input() {
  printf '%s' "${1:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

add_next_subscription_name() {
  local suffix="" letter candidate

  while true; do
    for letter in a b c d e f g h i j k l m n o p q r s t u v w x y z; do
      candidate="${letter}${suffix}"
      if ! subscription_name_exists "$candidate"; then
        echo "$candidate"
        return 0
      fi
    done

    if [ -z "${suffix:-}" ]; then
      suffix=1
    else
      suffix=$((suffix + 1))
    fi
  done
}

add_prompt_url() {
  local input url

  while true; do
    printf "请输入订阅地址：" >&2
    IFS= read -r input || return 1
    url="$(add_trim_input "$input")"

    if [ -n "${url:-}" ]; then
      echo "$url"
      return 0
    fi

    echo "订阅地址不能为空，请重新输入" >&2
  done
}

add_prompt_name() {
  local input name

  while true; do
    printf "请输入订阅名称（回车自动生成）：" >&2
    IFS= read -r input || return 1
    name="$(add_trim_input "$input")"

    if [ -z "${name:-}" ]; then
      add_next_subscription_name
      return 0
    fi

    if subscription_name_exists "$name"; then
      echo "⚠ 名称已存在，请重新输入" >&2
      continue
    fi

    echo "$name"
    return 0
  done
}

add_prompt_local_url() {
  local input filename local_path

  printf "请输入本地订阅文件名（默认目录：%s/runtime/subscriptions/）：" "$PROJECT_DIR" >&2
  IFS= read -r input || return 1
  filename="$(add_trim_input "$input")"

  [ -n "${filename:-}" ] || die "本地订阅文件名不能为空"

  local_path="$PROJECT_DIR/runtime/subscriptions/$filename"

  [ -f "$local_path" ] || die "本地订阅文件不存在：$local_path"
  [ -s "$local_path" ] || die "本地订阅文件为空：$local_path"

  echo "file://$local_path"
}

cmd_add() {
  local sub_url sub_name sub_fmt

  prepare
  ensure_add_use_prerequisites

  if [ "${1:-}" = "local" ]; then
    [ "$#" -eq 1 ] || die_usage "add local 参数不合法" "clashctl add local"
    sub_url="$(add_prompt_local_url)"
    cmd_add "$sub_url"
    return $?
  fi

  case "$#" in
    0)
      sub_url="$(add_prompt_url)"
      sub_name="$(add_prompt_name)"
      ;;
    1)
      sub_url="$(add_trim_input "${1:-}")"
      [ -n "${sub_url:-}" ] || die "订阅地址不能为空"
      sub_name="$(add_prompt_name)"
      ;;
    *)
      sub_url="$(add_trim_input "${1:-}")"
      [ -n "${sub_url:-}" ] || die "订阅地址不能为空"
      sub_name="${2:-default}"
      ;;
  esac

  sub_fmt="$(detect_subscription_format "$sub_url")"

  ui_progress_line 5 "正在保存订阅..."

  set_subscription "$sub_url" "$sub_fmt" "$sub_name" "false"

  ui_progress_line 65 "正在设为当前订阅..."

  set_active_subscription "$sub_name"

  ui_progress_line 85 "正在应用配置..."

  apply_runtime_change_after_config_mutation >/dev/null

  ui_progress_done "订阅添加完成"

  print_add_feedback "$sub_name" "$sub_url"
  cmd_ls
}

cmd_use() {
  local recommended active

  prepare
  ensure_add_use_prerequisites

  case "${1:-}" in
    --recommend|-r)
      recommended="$(recommended_subscription_name 2>/dev/null || true)"
      active="$(active_subscription_name 2>/dev/null || true)"

      if [ -z "${recommended:-}" ]; then
        if [ -n "${active:-}" ]; then
          ui_title "🐱 当前无更优推荐，保持当前"
          ui_kv "🚩" "当前主订阅" "$active"
          ui_next "clashctl select  选择节点"
          ui_blank
          return 0
        fi

        ui_title "❗ 当前没有可推荐的订阅"
        ui_next "clashctl select  选择节点"
        ui_blank
        return 1
      fi

      if [ "${recommended:-}" = "${active:-}" ]; then
        ui_title "🐱 当前已是推荐订阅，无需切换"
        [ -n "${active:-}" ] && ui_kv "📡" "当前主订阅" "$active"
        ui_next "clashctl select  选择节点"
        ui_blank
        return 0
      fi

      set_active_subscription "$recommended"
      apply_runtime_change_after_config_mutation
      print_use_feedback "$recommended"
      return 0
      ;;
    "")
      print_use_context
      use_subscription_interactive
      ;;
    --verbose|-v)
      print_use_context
      use_subscription_interactive "verbose"
      ;;
    *)
      set_active_subscription "$1"
      apply_runtime_change_after_config_mutation
      print_use_feedback "$1"
      ;;
  esac
}

subscription_pick_index() {
  local count="$1"
  local input choice

  while true; do
    printf "> " >&2
    IFS= read -r input || return 1
    choice="$(printf '%s' "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    case "${choice:-}" in
      q|Q)
        return 1
        ;;
    esac

    if ! printf '%s' "$choice" | grep -Eq '^[0-9]+$'; then
      echo "请输入有效编号" >&2
      continue
    fi

    if [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
      echo "$choice"
      return 0
    fi

    echo "请输入有效编号" >&2
  done
}

use_subscription_interactive() {
  local url_mode="${1:-full}"
  local active idx count selected_name
  local -a names

  active="$(active_subscription_name 2>/dev/null || true)"

  while IFS= read -r selected_name; do
    [ -n "${selected_name:-}" ] || continue
    names+=("$selected_name")
  done < <("$(yq_bin)" eval '.sources | keys | .[]' "$(subscriptions_file)" 2>/dev/null)

  count="${#names[@]}"
  [ "$count" -gt 0 ] || die "当前没有任何订阅"

  echo
  echo "🐱 请选择订阅"
  echo

  if [ -n "${active:-}" ] && subscription_exists "$active"; then
    echo "当前主订阅：$active"
    echo
  fi

  print_subscription_table_header "true"
  idx=1
  for selected_name in "${names[@]}"; do
    print_subscription_pick_line "$idx" "$selected_name" "$url_mode" "true"
    idx=$((idx + 1))
  done

  echo
  echo "  q) 退出"
  echo

  idx="$(subscription_pick_index "$count")" || return 0
  selected_name="${names[$((idx - 1))]}"

  set_active_subscription "$selected_name"
  apply_runtime_change_after_config_mutation
  print_use_feedback "$selected_name"
}

health_overview_lines() {
  local active recommended active_health active_fail active_enabled

  active="$(active_subscription_name 2>/dev/null || true)"
  recommended="$(recommended_subscription_name 2>/dev/null || true)"

  if [ -n "${active:-}" ]; then
    if subscription_enabled "$active"; then
      active_enabled="enabled"
    else
      active_enabled="disabled"
    fi
    active_health="$(subscription_health_status "$active" 2>/dev/null || echo "unknown")"
    active_fail="$(subscription_fail_count "$active" 2>/dev/null || echo "0")"

    echo "🚩 当前主订阅：$active"
    echo "❤️ 当前健康状态：$active_health"
    echo "🚨 当前失败次数：$active_fail"
    echo "🔧 当前启用状态：$active_enabled"
  else
    echo "🚩 当前主订阅：未设置"
  fi

  if [ -n "${recommended:-}" ] && [ "${recommended:-}" != "${active:-}" ]; then
    echo "💡 推荐订阅：$recommended"
  elif [ -n "${active:-}" ]; then
    echo "💡 推荐订阅：保持当前"
  else
    echo "💡 推荐订阅：暂无"
  fi
}

health_recommendation_lines() {
  load_system_state

  case "$SYSTEM_STATE" in
    ready)
      echo "💡 clashctl status"
      echo "💡 clashctl select"
      ;;
    stopped)
      if [ "$SUBSCRIPTION_STATE" = "missing" ]; then
        echo "💡 clashctl add <订阅链接>"
      else
        echo "💡 clashon"
      fi
      ;;
    degraded|broken)
      echo "💡 clashctl doctor"
      echo "💡 clashctl status --verbose"
      ;;
    *)
      echo "💡 clashctl status"
      ;;
  esac
}

cmd_ls() {
  prepare

  case "${1:-}" in
    "") ;;
    *)
      die_usage "ls 参数不合法" "clashctl ls"
      ;;
  esac

  ui_title "📡 订阅列表"

  subscription_list_overview_lines | sed 's/^/  /'
  ui_blank

  list_subscriptions
  ui_blank

  ui_section "下一步建议"
  subscription_list_recommendation_lines | sed 's/^/  /'
  ui_blank
}

cmd_health() {
  local verbose_mode="false"
  local target_name=""

  prepare

  while [ $# -gt 0 ]; do
    case "$1" in
      --verbose|-v)
        verbose_mode="true"
        ;;
      *)
        if [ -z "${target_name:-}" ]; then
          target_name="$1"
        else
          die_usage "health 参数不合法" "clashctl health [名称] [--verbose]"
        fi
        ;;
    esac
    shift
  done

  if [ "$verbose_mode" = "true" ]; then
    if [ -n "${target_name:-}" ]; then
      ui_section "单订阅详情"
      print_subscription_health_one "$target_name" | sed 's/^/  /'
      ui_blank

      ui_section "建议操作"
      echo "  💡 clashctl use ${target_name}"
      echo "  💡 clashctl ls"
      ui_blank
      return 0
    fi

    ui_info "订阅健康已收敛到 clashctl ls"
    cmd_ls
    return $?
  fi

  if [ -n "${target_name:-}" ]; then
    ui_section "单订阅详情"
    print_subscription_health_one "$target_name" | sed 's/^/  /'
    ui_blank
    ui_section "建议操作"
    echo "  💡 clashctl use ${target_name}"
    echo "  💡 clashctl ls"
    ui_blank
    return 0
  fi

  ui_info "订阅健康已收敛到 clashctl ls"
  cmd_ls
}

cmd_select() {
  prepare

  if [ -z "${1:-}" ]; then
    print_select_context || return $?
    proxy_select_interactive_guarded
    return 0
  fi

  proxy_select_direct "$@"
}

cmd_proxy_groups() {
  local group current type found="false"

  prepare

  if ! status_is_running; then
    die_state "代理内核未运行" "clashon"
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    die_state "控制器不可访问" "clashctl doctor"
  fi

  ui_title "📦 策略组列表"
  echo "  📦 名称                 类型         当前节点"
  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    found="true"
    type="$(proxy_group_type "$group" 2>/dev/null || echo "unknown")"
    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"
    [ -n "${current:-}" ] || current="<unknown>"
    printf '  📦 %-20s %-12s %s\n' "$group" "$type" "$current"
  done < <(proxy_group_list)

  if [ "$found" != "true" ]; then
    echo "  📭 暂无可切换策略组"
  fi

  ui_blank
  ui_next "clashctl select"
  ui_blank
}

cmd_proxy_current() {
  local group current found="false"

  prepare

  if ! status_is_running; then
    die_state "代理内核未运行" "clashon"
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    die_state "控制器不可访问" "clashctl doctor"
  fi

  if [ -n "${1:-}" ]; then
    group="$1"
    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"
    [ -n "${current:-}" ] || current="<unknown>"
    ui_title "🚀 当前节点"
    ui_kv "📦" "策略组" "$group"
    ui_kv "🚀" "当前节点" "${current:-未知}"
    ui_blank
    return 0
  fi

  ui_title "🚀 当前节点总览"
  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    found="true"
    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"
    [ -n "${current:-}" ] || current="<unknown>"
    printf '  🚀 %-20s %s\n' "$group" "$current"
  done < <(proxy_group_list)

  if [ "$found" != "true" ]; then
    echo "  📭 暂无可切换策略组"
  fi

  ui_blank
}

cmd_proxy_nodes() {
  local group="$1"
  local current node found="false"

  prepare
  [ -n "${group:-}" ] || die "请使用 clashctl select 切换节点"

  if ! status_is_running; then
    die_state "代理内核未运行" "clashon"
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    die_state "控制器不可访问" "clashctl doctor"
  fi

  current="$(proxy_group_current_display "$group" 2>/dev/null || true)"

  ui_title "🚀 候选节点列表"
  ui_kv "📦" "策略组" "$group"
  [ -n "${current:-}" ] && ui_kv "🚀" "当前节点" "$current"
  ui_blank

  while IFS= read -r node; do
    [ -n "${node:-}" ] || continue
    found="true"
    if [ "$node" = "$current" ]; then
      printf '  * 🚀 %s\n' "$node"
    else
      printf '    🚀 %s\n' "$node"
    fi
  done < <(proxy_group_selectable_nodes "$group")

  if [ "$found" != "true" ]; then
    echo "  📭 当前策略组没有候选节点"
  fi

  ui_blank
  ui_next "clashctl select"
  ui_blank
}

proxy_pick_index() {
  local count="$1"
  local input

  while true; do
    printf "> " >&2
    IFS= read -r input || return 1

    case "${input:-}" in
      q|Q)
        return 1
        ;;
    esac

    if printf '%s' "$input" | grep -Eq '^[0-9]+$' && [ "$input" -ge 1 ] && [ "$input" -le "$count" ]; then
      echo "$input"
      return 0
    fi

    echo "🚨 请输入 1-$count 之间的编号，或输入 q 退出" >&2
  done
}

proxy_pick_group_interactive() {
  local idx count group current type
  local -a groups=()
  local -a ordered_groups=()

  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    groups+=("$group")
  done < <(proxy_group_display_list)

  for group in "节点选择" "自动选择"; do
    if printf '%s\n' "${groups[@]}" | grep -Fxq "$group"; then
      ordered_groups+=("$group")
    fi
  done

  for group in "${groups[@]}"; do
    case "$group" in
      节点选择|自动选择)
        continue
        ;;
    esac
    ordered_groups+=("$group")
  done

  groups=("${ordered_groups[@]}")

  count="${#groups[@]}"
  [ "$count" -gt 0 ] || die "📭 暂无可切换策略组"

  echo "📦 请选择策略组：" >&2
  echo "💡 通常优先选择：节点选择" >&2
  idx=1
  for group in "${groups[@]}"; do
    current="$(proxy_group_current "$group" 2>/dev/null || echo "-")"
    printf '  %s) 📦 %s  ->  🚀 %s\n' "$idx" "$group" "$current" >&2
    idx=$((idx + 1))
  done
  echo "  q) 退出" >&2
  echo >&2

  idx="$(proxy_pick_index "$count")" || return 1
  echo "${groups[$((idx - 1))]}"
}

select_total_node_count() {
  local file="$RUNTIME_DIR/config.yaml"
  local node_count

  [ -s "$file" ] || return 1
  [ -x "$(yq_bin)" ] || return 1

  node_count="$("$(yq_bin)" eval '(.proxies // []) | length' "$file" 2>/dev/null | head -n 1 || true)"
  case "${node_count:-}" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  echo "$node_count"
}

cmd_sub() {
  prepare

  case "${1:-}" in
    list)
      shift || true
      cmd_ls "$@"
      ;;
    use)
      shift || true
      [ -n "${1:-}" ] || die "用法：clashctl sub use <名称>"
      set_active_subscription "$1"
      apply_runtime_change_after_config_mutation
      ;;
    set)
      shift || true
      [ -n "${1:-}" ] || die "用法：clashctl sub set <url> [name]（固定 convert，推荐使用：clashctl add <订阅链接>）"
      set_subscription "${1:-}" "convert" "${2:-default}"
      apply_runtime_change_after_config_mutation
      ;;
    enable)
      shift || true
      [ -n "${1:-}" ] || die "📜 用法：clashctl sub enable <名称>"
      enable_subscription "$1"
      regenerate_config
      apply_runtime_change_after_config_mutation
      print_sub_enable_feedback "$1"
      ;;
    disable)
      shift || true
      [ -n "${1:-}" ] || die "📜 用法：clashctl sub disable <名称>"
      disable_subscription "$1"
      regenerate_config
      apply_runtime_change_after_config_mutation
      print_sub_disable_feedback "$1"
      ;;
    rename)
      shift || true
      [ -n "${1:-}" ] || die "📜 用法：clashctl sub rename <旧名称> <新名称>"
      [ -n "${2:-}" ] || die "📜 用法：clashctl sub rename <旧名称> <新名称>"
      rename_subscription "$1" "$2"
      regenerate_config
      apply_runtime_change_after_config_mutation
      print_sub_rename_feedback "$1" "$2"
      ;;
    remove|rm|del)
      shift || true
      [ -n "${1:-}" ] || die "📜 用法：clashctl sub remove <名称>"
      remove_subscription "$1"
      regenerate_config
      apply_runtime_change_after_config_mutation
      print_sub_remove_feedback "$1"
      ;;
    health)
      shift || true
      cmd_health "$@"
      ;;
    "")
      ui_title "📡 订阅高级管理"
      echo "📜 用法："
      echo "  clashctl sub list"
      echo "  clashctl sub use <名称>"
      echo "  clashctl sub enable <名称>"
      echo "  clashctl sub disable <名称>"
      echo "  clashctl sub rename <旧名称> <新名称>"
      echo "  clashctl sub remove <名称>"
      echo "  clashctl sub health [名称]"
      echo
      echo "🧩 说明："
      echo "  add / use / ls 属于主路径"
      echo "  health 保留为多订阅健康审计"
      echo "  sub 仅用于高级维护操作"
      echo
      echo "💡 常用动作："
      echo "  clashctl sub list"
      echo "  clashctl sub health"
      echo "  clashctl sub enable <名称>"
      echo
      ui_next "clashctl ls"
      ui_blank
      ;;
    *)
      die_usage "未知的 sub 子命令：$1" "clashctl sub"
      ;;
  esac
}

proxy_select_interactive() {
  local group="${1:-}"
  local current idx count total_count node selected_node
  local -a nodes=()

  prepare

  if ! status_is_running; then
    die_state "代理内核未运行" "clashon"
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    die_state "控制器不可访问" "clashctl doctor"
  fi

  if [ -z "${group:-}" ]; then
    ui_title "🚀 节点切换"
    group="$(proxy_pick_group_interactive)" || return 0
  elif ! proxy_group_supports_manual_pick "$group"; then
    die "该策略组不支持手动挑节点：$group"
  fi

    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"

  while IFS= read -r node; do
    [ -n "${node:-}" ] || continue
    nodes+=("$node")
  done < <(proxy_group_selectable_nodes "$group")

  count="${#nodes[@]}"
  [ "$count" -gt 0 ] || die "📭 当前策略组没有候选节点：$group"
  total_count="$(select_total_node_count 2>/dev/null || true)"

  echo
  echo "📦 当前策略组：$group"
  [ -n "${current:-}" ] && echo "🚀 当前节点：$current"
  echo "📦 当前策略组候选数：$count"
  [ -n "${total_count:-}" ] && echo "🔢 全部节点总数：$total_count"
  echo "ℹ️ 以下仅显示当前策略组可切换节点"
  echo
  echo "🚀 请选择节点："

  idx=1
  for node in "${nodes[@]}"; do
    if [ "$node" = "$current" ]; then
      printf '  %s) 🚀 %s [当前]\n' "$idx" "$node"
    else
      printf '  %s) 🚀 %s\n' "$idx" "$node"
    fi
    idx=$((idx + 1))
  done

  echo "  q) 退出"
  echo

  idx="$(proxy_pick_index "$count")" || return 0
  selected_node="${nodes[$((idx - 1))]}"

  proxy_group_select "$group" "$selected_node"
  print_select_feedback "$group"
}

proxy_pick_group_for_select() {
  local idx count group current type
  local -a groups=()
  local -a ordered_groups=()

  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    groups+=("$group")
  done < <(proxy_group_display_list)

  for group in "节点选择" "自动选择"; do
    if printf '%s\n' "${groups[@]}" | grep -Fxq "$group"; then
      ordered_groups+=("$group")
    fi
  done

  for group in "${groups[@]}"; do
    case "$group" in
      节点选择|自动选择)
        continue
        ;;
    esac
    ordered_groups+=("$group")
  done

  groups=("${ordered_groups[@]}")

  count="${#groups[@]}"
  [ "$count" -gt 0 ] || die "📭 暂无可切换策略组"

  echo "📦 请选择策略组：" >&2
  echo "💡 通常优先选择：节点选择" >&2
  idx=1
  for group in "${groups[@]}"; do
    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"
    type="$(proxy_group_type_label "$group" 2>/dev/null || echo "unknown")"
    [ -n "${current:-}" ] || current="<unknown>"
    printf '  %s) 📦 %s [%s]  ->  🚀 %s\n' "$idx" "$group" "$type" "$current" >&2
    idx=$((idx + 1))
  done
  echo "  q) 退出" >&2
  echo >&2

  idx="$(proxy_pick_index "$count")" || return 1
  echo "${groups[$((idx - 1))]}"
}

print_proxy_group_manual_pick_blocked() {
  local group="$1"
  local current type message

  message="$(proxy_group_manual_pick_error_message "$group" 2>/dev/null || echo "该策略组不支持手动切换：$group")"
  current="$(proxy_group_current_display "$group" 2>/dev/null || true)"
  type="$(proxy_group_type_label "$group" 2>/dev/null || echo "unknown")"

  ui_warn "$message"
  ui_kv "📦" "策略组" "$group"
  ui_kv "🧭" "策略组类型" "$type"
  if [ -n "${current:-}" ]; then
    ui_kv "🚀" "当前节点" "$current"
  else
    ui_kv "🚀" "当前节点" "<unknown>"
  fi
  ui_blank
}

proxy_select_interactive_guarded() {
  local group="${1:-}"
  local current idx count total_count node selected_node
  local -a nodes=()

  prepare

  if ! status_is_running; then
    die_state "代理内核未运行" "clashon"
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    die_state "控制器不可访问" "clashctl doctor"
  fi

  if [ -z "${group:-}" ]; then
    ui_title "🚀 节点切换"
    group="$(proxy_pick_group_for_select)" || return 0
  fi

  proxy_group_exists "$group" || die "策略组不存在：$group"

  if ! proxy_group_supports_manual_pick "$group"; then
    print_proxy_group_manual_pick_blocked "$group"
    return 0
  fi

  current="$(proxy_group_current_display "$group" 2>/dev/null || true)"

  while IFS= read -r node; do
    [ -n "${node:-}" ] || continue
    nodes+=("$node")
  done < <(proxy_group_selectable_nodes "$group")

  count="${#nodes[@]}"
  [ "$count" -gt 0 ] || die "📭 当前策略组没有候选节点：$group"
  total_count="$(select_total_node_count 2>/dev/null || true)"

  echo
  echo "📦 当前策略组：$group"
  [ -n "${current:-}" ] && echo "🚀 当前节点：$current"
  echo "📦 当前策略组候选数：$count"
  [ -n "${total_count:-}" ] && echo "🔢 全部节点总数：$total_count"
  echo "ℹ️ 以下仅显示当前策略组可切换节点"
  echo
  echo "🚀 请选择节点："

  idx=1
  for node in "${nodes[@]}"; do
    if [ "$node" = "$current" ]; then
      printf '  %s) 🚀 %s [当前]\n' "$idx" "$node"
    else
      printf '  %s) 🚀 %s\n' "$idx" "$node"
    fi
    idx=$((idx + 1))
  done

  echo "  q) 退出"
  echo

  idx="$(proxy_pick_index "$count")" || return 0
  selected_node="${nodes[$((idx - 1))]}"

  proxy_group_select "$group" "$selected_node"
  print_select_feedback "$group"
}

cmd_proxy() {
  echo "⚠ 当前版本不提供 proxy 子命令"
  echo "👉 使用 clashon / clashoff 控制代理"
  echo "👉 使用 clashctl select 切换节点"
  return 0
}

proxy_env_detected() {
  local value

  for value in \
    "${http_proxy:-}" "${https_proxy:-}" \
    "${HTTP_PROXY:-}" "${HTTPS_PROXY:-}" \
    "${all_proxy:-}" "${ALL_PROXY:-}"; do
    [ -n "${value:-}" ] && return 0
  done

  if [ "$(system_proxy_status 2>/dev/null || echo off)" = "on" ]; then
    return 0
  fi

  return 1
}

warn_if_no_proxy_env() {
  proxy_env_detected && return 0

  ui_warn "当前未检测到代理环境"
  ui_next "建议先执行 clashon"
  ui_info "否则可能下载缓慢或失败"
}

cmd_upgrade() {
  local verbose="false"
  local target_kernel=""
  local current_version target_version actual_version

  prepare

  while [ $# -gt 0 ]; do
    case "$1" in
      mihomo|clash)
        target_kernel="$1"
        ;;
      -v|--verbose)
        verbose="true"
        ;;
      *)
        die_usage "upgrade 参数不合法" "clashctl upgrade [mihomo|clash] [-v|--verbose]"
        ;;
    esac
    shift
  done

  warn_if_no_proxy_env

  [ -n "${target_kernel:-}" ] || target_kernel="$(runtime_kernel_type)"
  target_kernel="$(normalize_kernel_type "$target_kernel")"
  current_version="$(kernel_installed_version_text "$target_kernel")"
  target_version="$(kernel_target_version "$target_kernel")"

  ui_title "🚀 正在升级 ${target_kernel} 内核 ..."
  ui_kv "🧩" "升级方式" "升级到当前设定目标版本，不自动追踪官方 latest"
  ui_kv "📦" "当前版本" "$current_version"
  ui_kv "🎯" "目标版本" "$target_version"
  ui_blank

  upgrade_runtime_kernel "$target_kernel" "$verbose"
  actual_version="$(kernel_installed_version_text "$target_kernel")"

  ui_title "🐱 内核升级完成"
  ui_kv "🚀" "当前内核" "$(runtime_kernel_type)"
  ui_kv "🎯" "目标版本" "$target_version"
  ui_kv "🧪" "实际版本" "$actual_version"
  ui_kv "🧩" "影响范围" "仅更新代理内核，不更新项目脚本"
  ui_next "clashctl status"
  ui_blank
}

cmd_update() {
  local force_mode="false"
  local regenerate_mode="false"

  prepare

  while [ $# -gt 0 ]; do
    case "$1" in
      --force)
        force_mode="true"
        ;;
      --regenerate)
        regenerate_mode="true"
        ;;
      *)
        die_usage "update 参数不合法" "clashctl update [--force] [--regenerate]"
        ;;
    esac
    shift
  done

  warn_if_no_proxy_env

  ui_title "🔄 正在更新项目代码 ..."

  update_project_code "$force_mode" "$regenerate_mode"

  ui_title "🐱 项目代码已更新"
  ui_kv "🧩" "影响范围" "脚本、CLI、配置处理逻辑可能已变化"
  if [ "$regenerate_mode" = "true" ]; then
    ui_kv "🧩" "配置状态" "已重新生成"
  else
    ui_kv "🚨" "配置状态" "未自动重新生成"
  fi
  ui_next "clashctl status"
  ui_blank
}

cmd_start_direct() {
  prepare
  start_runtime
}

cmd_stop_direct() {
  prepare
  stop_runtime
}

cmd_restart_direct() {
  prepare
  stop_runtime || true
  start_runtime
}

status_read_mixed_port() {
  runtime_config_mixed_port 2>/dev/null || true
}

status_read_controller_raw() {
  runtime_config_controller_addr 2>/dev/null || true
}

controller_externally_reachable() {
  local controller host

  controller="$(status_read_controller_raw 2>/dev/null || true)"
  [ -n "${controller:-}" ] && [ "$controller" != "null" ] || return 1

  host="${controller%:*}"

  case "$host" in
    0.0.0.0|::|[::])
      return 0
      ;;
    127.0.0.1|localhost|::1|[::1])
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

status_read_controller() {
  local controller
  controller="$(status_read_controller_raw 2>/dev/null || true)"
  display_controller_local_addr "$controller" 2>/dev/null || echo "$controller"
}

status_read_controller_lan() {
  local controller lan_ip port
  controller="$(status_read_controller_raw 2>/dev/null || true)"
  [ -n "${controller:-}" ] && [ "$controller" != "null" ] || return 1

  controller_externally_reachable || return 1

  port="${controller##*:}"
  lan_ip="$(ui_lan_ip 2>/dev/null || true)"
  [ -n "${lan_ip:-}" ] || return 1
  echo "${lan_ip}:${port}"
}

status_read_controller_public() {
  local controller public_ip port
  controller="$(status_read_controller_raw 2>/dev/null || true)"
  [ -n "${controller:-}" ] && [ "$controller" != "null" ] || return 1

  controller_externally_reachable || return 1

  port="${controller##*:}"
  public_ip="$(ui_public_ip 2>/dev/null || true)"
  [ -n "${public_ip:-}" ] || return 1
  echo "${public_ip}:${port}"
}

print_select_feedback() {
  local group="$1"
  local current

  current="$(proxy_group_current_display "$group" 2>/dev/null || true)"

  ui_title "🚀 节点切换完成"

  if [ -n "${group:-}" ]; then
    ui_kv "📦" "已切换策略组" "$group"
  fi

  ui_kv "🚀" "当前节点" "${current:-<unknown>}"

  main_feedback_runtime_state
  ui_next "clashctl status"
  ui_blank
}

status_current_proxy_brief() {
  local default_group default_current fallback_group fallback_current
  local bind_failure_text

  if ! status_is_running; then
    bind_failure_text="$(runtime_mixed_port_bind_failure_text 2>/dev/null || true)"
    if [ -n "${bind_failure_text:-}" ]; then
      echo "$bind_failure_text"
      return 0
    fi

    echo "未启动"
    return 0
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    echo "控制器不可访问"
    return 0
  fi

  default_group="$(default_proxy_group_name 2>/dev/null || true)"
  if [ -n "${default_group:-}" ]; then
    default_current="$(default_proxy_group_current 2>/dev/null || true)"
    echo "${default_group} -> ${default_current:-<unknown>}"
    return 0
  fi

  fallback_group="$(proxy_group_list 2>/dev/null | sed -n '1p')"
  if [ -n "${fallback_group:-}" ]; then
    fallback_current="$(proxy_group_current_display "$fallback_group" 2>/dev/null || true)"
    echo "${fallback_group} -> ${fallback_current:-<unknown>}"
    return 0
  fi

  echo "暂无可切换策略组"
}

cmd_proxy_groups() {
  local group current type found="false"

  prepare

  if ! status_is_running; then
    die_state "代理内核未运行" "clashon"
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    die_state "控制器不可访问" "clashctl doctor"
  fi

  ui_title "📦 策略组列表"
  echo "  📦 名称                 类型         当前节点"
  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    found="true"
    type="$(proxy_group_type "$group" 2>/dev/null || echo "unknown")"
    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"
    printf '  📦 %-20s %-12s %s\n' "$group" "$type" "${current:-<unknown>}"
  done < <(proxy_group_list)

  if [ "$found" != "true" ]; then
    echo "  📭 暂无可切换策略组"
  fi

  ui_blank
  ui_next "clashctl select"
  ui_blank
}

cmd_proxy_current() {
  local group current found="false"

  prepare

  if ! status_is_running; then
    die_state "代理内核未运行" "clashon"
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    die_state "控制器不可访问" "clashctl doctor"
  fi

  if [ -n "${1:-}" ]; then
    group="$1"
    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"
    ui_title "🚀 当前节点"
    ui_kv "📦" "策略组" "$group"
    ui_kv "🚀" "当前节点" "${current:-<unknown>}"
    ui_blank
    return 0
  fi

  ui_title "🚀 当前节点总览"
  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    found="true"
    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"
    printf '  🚀 %-20s %s\n' "$group" "${current:-<unknown>}"
  done < <(proxy_group_list)

  if [ "$found" != "true" ]; then
    echo "  📭 暂无可切换策略组"
  fi

  ui_blank
}

cmd_proxy_nodes() {
  local group="$1"
  local current node found="false"

  prepare
  [ -n "${group:-}" ] || die "请使用 clashctl select 切换节点"

  if ! status_is_running; then
    die_state "代理内核未运行" "clashon"
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    die_state "控制器不可访问" "clashctl doctor"
  fi

  current="$(proxy_group_current_display "$group" 2>/dev/null || true)"

  ui_title "🚀 候选节点列表"
  ui_kv "📦" "策略组" "$group"
  ui_kv "🚀" "当前节点" "${current:-<unknown>}"
  ui_blank

  while IFS= read -r node; do
    [ -n "${node:-}" ] || continue
    found="true"
    if [ "$node" = "$current" ]; then
      printf '  * 🚀 %s\n' "$node"
    else
      printf '    🚀 %s\n' "$node"
    fi
  done < <(proxy_group_selectable_nodes "$group")

  if [ "$found" != "true" ]; then
    echo "  📭 该策略组暂无可切换真实节点"
  fi

  ui_blank
  ui_next "clashctl select"
  ui_blank
}

proxy_pick_group_for_select() {
  local idx count group current type
  local -a groups=()
  local -a ordered_groups=()

  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    groups+=("$group")
  done < <(proxy_group_display_list)

  for group in "节点选择" "自动选择"; do
    if printf '%s\n' "${groups[@]}" | grep -Fxq "$group"; then
      ordered_groups+=("$group")
    fi
  done

  for group in "${groups[@]}"; do
    case "$group" in
      节点选择|自动选择)
        continue
        ;;
    esac
    ordered_groups+=("$group")
  done

  groups=("${ordered_groups[@]}")

  count="${#groups[@]}"
  [ "$count" -gt 0 ] || die "📭 暂无可切换策略组"

  echo "📦 请选择策略组：" >&2
  echo "💡 通常优先选择：节点选择" >&2
  idx=1
  for group in "${groups[@]}"; do
    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"
    type="$(proxy_group_type_label "$group" 2>/dev/null || echo "unknown")"
    printf '  %s) 📦 %s [%s]  ->  🚀 %s\n' "$idx" "$group" "$type" "${current:-<unknown>}" >&2
    idx=$((idx + 1))
  done
  echo "  q) 退出" >&2
  echo >&2

  idx="$(proxy_pick_index "$count")" || return 1
  echo "${groups[$((idx - 1))]}"
}

proxy_select_interactive_guarded() {
  local group="${1:-}"
  local current idx count total_count node selected_node
  local choose_group="false"
  local -a nodes=()

  prepare

  if ! status_is_running; then
    die_state "代理内核未运行" "clashon"
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    die_state "控制器不可访问" "clashctl doctor"
  fi

  if [ -z "${group:-}" ]; then
    ui_title "🚀 节点切换"
    choose_group="true"
  fi

  while true; do
    if [ -z "${group:-}" ]; then
      group="$(proxy_pick_group_for_select)" || return 0
    fi

    proxy_group_exists "$group" || die "策略组不存在：$group"

    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"
    nodes=()
    while IFS= read -r node; do
      [ -n "${node:-}" ] || continue
      nodes+=("$node")
    done < <(proxy_group_selectable_nodes "$group")

    count="${#nodes[@]}"
    if [ "$count" -le 0 ]; then
      ui_warn "该策略组暂无可切换真实节点"
      ui_kv "📦" "策略组" "$group"
      ui_kv "🚀" "当前节点" "${current:-<unknown>}"
      ui_blank
      if [ "$choose_group" = "true" ]; then
        group=""
        continue
      fi
      return 0
    fi

    total_count="$(select_total_node_count 2>/dev/null || true)"

    echo
    echo "📦 当前策略组：$group"
    echo "🚀 当前节点：${current:-<unknown>}"
    echo "📦 当前策略组候选数：$count"
    [ -n "${total_count:-}" ] && echo "🔢 全部节点总数：$total_count"
    echo "ℹ️ 以下仅显示当前策略组可切换节点"
    echo
    echo "🚀 请选择节点："

    idx=1
    for node in "${nodes[@]}"; do
      if [ "$node" = "$current" ]; then
        printf '  %s) 🚀 %s [当前]\n' "$idx" "$node"
      else
        printf '  %s) 🚀 %s\n' "$idx" "$node"
      fi
      idx=$((idx + 1))
    done

    echo "  q) 退出"
    echo

    idx="$(proxy_pick_index "$count")" || return 0
    selected_node="${nodes[$((idx - 1))]}"
    proxy_node_is_selectable_candidate "$selected_node" || die "节点不是可切换节点：$selected_node"

    proxy_group_select "$group" "$selected_node"
    print_select_feedback "$group"
    return 0
  done
}

cmd="${1:-}"
shift || true

case "$cmd" in
  add)            cmd_add "$@" ;;
  use)            cmd_use "$@" ;;
  ls)             cmd_ls "$@" ;;
  health)         cmd_health "$@" ;;
  select)         cmd_select "$@" ;;
  on)             cmd_on "$@" ;;
  off)            cmd_off "$@" ;;
  status)         cmd_status "$@" ;;
  status-next)    cmd_status_next "$@" ;;
  boot)           cmd_boot "$@" ;;
  log|logs)       cmd_logs "$@" ;;
  doctor)         cmd_doctor "$@" ;;
  ui)             cmd_ui "$@" ;;
  secret)         cmd_secret "$@" ;;
  tun)            cmd_tun "$@" ;;
  dev)            cmd_dev "$@" ;;
  config)         cmd_config "$@" ;;
  lan)            cmd_lan "$@" ;;
  mixin)          cmd_mixin "$@" ;;
  relay)          cmd_relay "$@" ;;
  profile)        cmd_profile "$@" ;;
  sub)            cmd_sub "$@" ;;
  proxy)          cmd_proxy "$@" ;;
  upgrade)        cmd_upgrade "$@" ;;
  update)         cmd_update "$@" ;;
  completion)     cmd_completion "$@" ;;
  tui)            cmd_tui "$@" ;;
  start-direct)   cmd_start_direct "$@" ;;
  stop-direct)    cmd_stop_direct "$@" ;;
  restart-direct) cmd_restart_direct "$@" ;;
  -h|--help|"") usage ;;
  help)
    case "${1:-}" in
      advanced) usage_advanced ;;
      *) usage ;;
    esac
    ;;
  *) die "未知命令：$cmd" ;;
esac
