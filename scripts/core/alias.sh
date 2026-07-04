#!/usr/bin/env bash

_clashctl_real() {
  if command -v clashctl-bin >/dev/null 2>&1; then
    clashctl-bin "$@"
    return $?
  fi

  command clashctl "$@"
}

_clashctl_real_on() {
  local project_dir clashctl_script

  project_dir="$(_clash_alias_project_dir)"
  clashctl_script="$project_dir/scripts/core/clashctl.sh"

  if [ -f "$clashctl_script" ]; then
    bash "$clashctl_script" on "$@"
    return $?
  fi

  _clashctl_real on "$@"
}

_clashctl_real_on_target() {
  local project_dir clashctl_script

  project_dir="$(_clash_alias_project_dir)"
  clashctl_script="$project_dir/scripts/core/clashctl.sh"

  if [ -f "$clashctl_script" ]; then
    echo "bash $clashctl_script on"
  else
    echo "_clashctl_real on"
  fi
}

_clash_alias_project_dir() {
  local self_dir

  if [ -n "${CLASH_FOR_LINUX_PROJECT_DIR:-}" ]; then
    echo "$CLASH_FOR_LINUX_PROJECT_DIR"
    return 0
  fi

  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  echo "$self_dir"
}

_clash_alias_state_file() {
  echo "$(_clash_alias_project_dir)/runtime/shell-proxy.env"
}

_clash_alias_runtime_config_file() {
  echo "$(_clash_alias_project_dir)/runtime/config.yaml"
}

_clash_alias_yq_bin() {
  echo "$(_clash_alias_project_dir)/runtime/bin/yq"
}

_clash_alias_env_value() {
  local key="$1"
  local env_file value

  case "$key" in
    ""|*[!A-Za-z0-9_]*)
      return 0
      ;;
  esac

  eval "value=\${$key:-}"
  if [ -n "${value:-}" ]; then
    printf '%s' "$value"
    return 0
  fi

  env_file="$(_clash_alias_project_dir)/.env"
  [ -f "$env_file" ] || return 0

  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?${key}=['\"]?([^'\"]*)['\"]?$/\2/p" "$env_file" | tail -n 1
}

_clash_alias_shell_auto_restore_enabled() {
  local value

  value="$(_clash_alias_env_value CLASH_SHELL_AUTO_RESTORE_PROXY)"
  case "${value:-true}" in
    false|False|FALSE|0|no|No|NO|off|Off|OFF)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

_clash_alias_set_persist_enabled() {
  local enabled="$1"
  local state_file
  state_file="$(_clash_alias_state_file)"

  mkdir -p "$(dirname "$state_file")"
  cat > "$state_file" <<EOF
SHELL_PROXY_PERSIST_ENABLED="${enabled}"
SHELL_PROXY_PERSIST_TIME="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
EOF
}

_clash_alias_persist_enabled() {
  local state_file enabled
  state_file="$(_clash_alias_state_file)"
  [ -f "$state_file" ] || return 1

  enabled="$(sed -nE 's/^SHELL_PROXY_PERSIST_ENABLED=\"?([^\"\r\n]+)\"?$/\1/p' "$state_file" | head -n 1)"
  [ "${enabled:-false}" = "true" ]
}

_clash_alias_print_sep() {
  echo
}

_clash_alias_proxy_on() {
  _clashctl_real proxy on >/dev/null || return $?
  _clash_alias_export_proxy || return $?
}

_clash_alias_proxy_on_system() {
  _clashctl_real proxy on >/dev/null || return $?
  _clash_alias_export_system_proxy || return $?
}

_clash_alias_proxy_off() {
  _clashctl_real proxy off >/dev/null || true
}

_clash_alias_proxy_show() {
  return 0
}

_clash_alias_export_system_proxy() {
  local proxy_file http_url https_url all_url no_proxy

  proxy_file="${SYSTEM_PROXY_ENV_FILE:-/etc/environment}"
  [ -f "$proxy_file" ] || return 1
  grep -Fq "# >>> clash-for-linux system proxy >>>" "$proxy_file" 2>/dev/null || return 1

  http_url="$(sed -nE 's/^http_proxy="?([^"\r\n]+)"?$/\1/p' "$proxy_file" | tail -n 1)"
  https_url="$(sed -nE 's/^https_proxy="?([^"\r\n]+)"?$/\1/p' "$proxy_file" | tail -n 1)"
  all_url="$(sed -nE 's/^all_proxy="?([^"\r\n]+)"?$/\1/p' "$proxy_file" | tail -n 1)"
  no_proxy="$(sed -nE 's/^NO_PROXY="?([^"\r\n]+)"?$/\1/p' "$proxy_file" | tail -n 1)"
  [ -n "${no_proxy:-}" ] || no_proxy="$(sed -nE 's/^no_proxy="?([^"\r\n]+)"?$/\1/p' "$proxy_file" | tail -n 1)"

  [ -n "${http_url:-}" ] || return 1
  [ -n "${https_url:-}" ] || https_url="$http_url"
  [ -n "${all_url:-}" ] || all_url="${http_url/http:\/\//socks5://}"
  [ -n "${no_proxy:-}" ] || no_proxy="127.0.0.1,localhost,::1"

  _clash_alias_export_proxy_values "$http_url" "$https_url" "$all_url" "$no_proxy"
}

_clash_alias_runtime_proxy_port() {
  local config_file yq_bin port

  config_file="$(_clash_alias_runtime_config_file)"
  [ -s "$config_file" ] || return 1

  yq_bin="$(_clash_alias_yq_bin)"
  if [ -x "$yq_bin" ]; then
    port="$("$yq_bin" eval '.["mixed-port"] // .port // ""' "$config_file" 2>/dev/null | head -n 1)"
  else
    port="$(sed -nE 's/^[[:space:]]*(mixed-port|port):[[:space:]]*"?([0-9]+)"?[[:space:]]*$/\2/p' "$config_file" | head -n 1)"
  fi

  [ -n "${port:-}" ] && [ "$port" != "null" ] || return 1
  echo "$port"
}

_clash_alias_export_runtime_proxy() {
  local port host http_url all_url no_proxy

  port="$(_clash_alias_runtime_proxy_port)" || return $?
  host="${CLASH_PROXY_HOST:-127.0.0.1}"
  http_url="http://${host}:${port}"
  all_url="socks5://${host}:${port}"
  no_proxy="${NO_PROXY_DEFAULT:-127.0.0.1,localhost,::1}"

  _clash_alias_export_proxy_values "$http_url" "$http_url" "$all_url" "$no_proxy"
}

_clash_alias_export_proxy_values() {
  local http_url="$1"
  local https_url="$2"
  local all_url="$3"
  local no_proxy="$4"

  export http_proxy="$http_url"
  export https_proxy="$https_url"
  export HTTP_PROXY="$http_url"
  export HTTPS_PROXY="$https_url"
  export all_proxy="$all_url"
  export ALL_PROXY="$all_url"
  export no_proxy="$no_proxy"
  export NO_PROXY="$no_proxy"
}

_clash_alias_export_proxy() {
  _clash_alias_export_system_proxy || _clash_alias_export_runtime_proxy
}

_clash_alias_unset_shell_proxy() {
  unset \
    http_proxy https_proxy HTTP_PROXY HTTPS_PROXY \
    all_proxy ALL_PROXY no_proxy NO_PROXY
}

_clash_alias_status_next() {
  _clashctl_real status-next 2>/dev/null || echo "clashctl status"
}

_clash_alias_prepare_on() {
  # 这里不直接自己做 regenerate / restart / fallback，
  # 而是统一交给 clashctl on 主链处理，避免双执行链。
  # shell 层只负责“闭环体验”，不抢 runtime / build 的职责。
  return 0
}

_clash_alias_after_on() {
  _clash_alias_set_persist_enabled "true"
  _clash_alias_export_proxy || return $?
}

_clash_alias_run_on() {
  local on_output on_rc had_errexit

  _clash_alias_prepare_on || return $?

  on_output="$(mktemp "${TMPDIR:-/tmp}/clashon.XXXXXX")" || {
    echo "❗ 开启代理失败：无法创建临时输出文件" >&2
    return 1
  }

  had_errexit="false"
  case "$-" in
    *e*)
      had_errexit="true"
      set +e
      ;;
  esac

  CLASH_ALIAS_CALL=1 _clashctl_real_on "$@" >"$on_output" 2>&1
  on_rc=$?

  if [ "$had_errexit" = "true" ]; then
    set -e
  fi

  if [ "$on_rc" -ne 0 ]; then
    if _clash_alias_export_system_proxy; then
      echo "🚨 clashctl on 返回非 0，但系统代理已写入，继续同步当前 Shell（底层返回码：$on_rc）" >&2
      if [ -s "$on_output" ]; then
        sed 's/^/  /' "$on_output" >&2
      fi
    elif _clash_alias_proxy_on_system; then
      echo "🚨 clashctl on 返回非 0，已通过 proxy on 继续同步当前 Shell（底层返回码：$on_rc）" >&2
      if [ -s "$on_output" ]; then
        sed 's/^/  /' "$on_output" >&2
      fi
    else
      echo "❗ 开启代理失败（底层返回码：$on_rc）" >&2
      if [ -s "$on_output" ]; then
        sed 's/^/  /' "$on_output" >&2
      else
        echo "  底层命令没有输出错误详情：$(_clashctl_real_on_target)" >&2
      fi
      rm -f "$on_output" 2>/dev/null || true
      return "$on_rc"
    fi
  else
    cat "$on_output"
  fi

  rm -f "$on_output" 2>/dev/null || true

  _clash_alias_after_on || {
    on_rc=$?
    echo "❗ 开启代理失败：当前 Shell 代理环境同步失败（返回码：$on_rc）" >&2
    return "$on_rc"
  }
}

_clash_alias_run_off() {
  _clash_alias_unset_shell_proxy
  _clash_alias_set_persist_enabled "false"
  _clashctl_real off "$@" || return $?
}

_clash_alias_auto_restore_proxy() {
  _clash_alias_shell_auto_restore_enabled || return 0
  _clash_alias_persist_enabled || return 0
  _clash_alias_export_proxy || return 0

  return 0
}

clashctl() {
  case "${1:-}" in
    on)
      shift || true
      _clash_alias_run_on "$@"
      ;;
    off)
      shift || true
      _clash_alias_run_off "$@"
      ;;
    proxy)
      case "${2:-}" in
        on)
          _clash_alias_proxy_on || return $?
          _clash_alias_print_sep
          _clash_alias_proxy_show
          ;;
        off)
          _clash_alias_unset_shell_proxy
          _clash_alias_proxy_off
          _clash_alias_print_sep
          echo "🧹 系统代理已关闭"
          ui_blank
          ;;
        *)
          _clashctl_real "$@"
          ;;
      esac
      ;;
    ui)
      shift || true
      # ui 前如果 runtime 已运行但当前 shell 没代理，不强制注入；
      # 保持 UI 行为纯粹，只走原命令。
      _clashctl_real ui "$@"
      ;;
    status)
      shift || true
      _clashctl_real status "$@"
      ;;
    *)
      _clashctl_real "$@"
      ;;
  esac
}

# 快捷入口全部收敛到 clashctl 函数
clashon() {
  clashctl on "$@" || return $?
}

clashoff() {
  clashctl off "$@" || return $?
}

clashproxy() {
  case "${1:-show}" in
    on)
      clashctl proxy on
      ;;
    off)
      clashctl proxy off
      ;;
    show|status)
      clashctl proxy show
      ;;
    groups)
      clashctl proxy groups
      ;;
    current)
      shift || true
      clashctl proxy current "$@"
      ;;
    nodes)
      shift || true
      clashctl proxy nodes "$@"
      ;;
    select)
      shift || true
      clashctl proxy select "$@"
      ;;
    *)
      echo "📜 用法：clashproxy [show|on|off|groups|current|nodes|select]"
      echo "💡 主路径切节点请使用：clashselect 或 clashctl select"
      return 2
      ;;
  esac
}

clashls() {
  clashctl ls "$@"
}

clashselect() {
  clashctl select "$@"
}

clashui() {
  clashctl ui "$@"
}

clashsecret() {
  clashctl secret "$@"
}

clashtun() {
  clashctl tun "$@"
}

clashrelay() {
  clashctl relay "$@"
}

clashupgrade() {
  clashctl upgrade "$@"
}

clashmixin() {
  case "${1:-}" in
    -e|--edit)
      clashctl mixin edit
      ;;
    -c|--raw)
      clashctl mixin raw
      ;;
    -r|--runtime)
      clashctl mixin runtime
      ;;
    "")
      clashctl mixin
      ;;
    *)
      clashctl mixin "$@"
      ;;
  esac
}

# shell 被 source 后做轻量恢复：
# 若上次 clashon 持久化开启，则新终端自动恢复当前 shell 代理变量。
_clash_alias_auto_restore_proxy
