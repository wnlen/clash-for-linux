#!/usr/bin/env bash
# TUI 仪表盘 — 基于 gum (https://github.com/charmbracelet/gum)

# ─── 颜色定义 ──────────────────────────────────────────────
TUI_PRIMARY="212"       # 粉色
TUI_ACCENT="99"         # 紫色
TUI_SUCCESS="76"        # 绿色
TUI_WARNING="214"       # 橙色
TUI_DANGER="196"        # 红色
TUI_MUTED="240"         # 灰色
TUI_INFO="39"           # 蓝色

# ─── gum 检测 ──────────────────────────────────────────────
tui_ensure_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  echo
  echo "❗ TUI 需要 gum（Charm 出品的终端 UI 工具）"
  echo
  echo "安装方式："
  echo "  macOS:   brew install gum"
  echo "  Arch:    pacman -S gum"
  echo "  Nix:     nix-env -iA nixpkgs.gum"
  echo "  Go:      go install github.com/charmbracelet/gum@latest"
  echo "  通用:    见 https://github.com/charmbracelet/gum#installation"
  echo
  exit 1
}

# ─── 工具函数 ──────────────────────────────────────────────
tui_styled() {
  local fg="${1:-$TUI_PRIMARY}"
  shift
  gum style --foreground "$fg" -- "$@"
}

tui_header() {
  gum style \
    --border double \
    --border-foreground "$TUI_PRIMARY" \
    --padding "0 2" \
    --align center \
    --bold \
    -- "$@"
}

tui_section_header() {
  gum style \
    --foreground "$TUI_ACCENT" \
    --bold \
    -- "$1"
}

tui_kv_line() {
  local icon="$1" key="$2" value="$3"
  printf '%s %s：%s\n' "$icon" "$key" "$value"
}

tui_separator() {
  gum style --foreground "$TUI_MUTED" -- "────────────────────────────────────────"
}

tui_status_badge() {
  local text="$1"
  local color="$2"
  gum style --foreground "$color" --bold -- "$text"
}

tui_spinner_exec() {
  local title="$1"
  shift
  gum spin --spinner dot --title "$title" -- "$@"
}

tui_confirm() {
  local prompt="$1"
  gum confirm --prompt.foreground "$TUI_PRIMARY" "$prompt"
}

tui_pager() {
  gum pager --border-foreground "$TUI_MUTED"
}

# ─── 状态采集 ──────────────────────────────────────────────
tui_collect_status() {
  load_system_state 2>/dev/null || true

  TUI_RUNTIME_STATE="${RUNTIME_STATE:-unknown}"
  TUI_BUILD_STATE="${BUILD_STATE:-unknown}"
  TUI_SUBSCRIPTION_STATE="${SUBSCRIPTION_STATE:-unknown}"
  TUI_SYSTEM_STATE="${SYSTEM_STATE:-unknown}"
  TUI_RISK_LEVEL="${RISK_LEVEL:-unknown}"
  TUI_TUN_ENABLED="${TUN_ENABLED:-false}"
  TUI_TUN_EFFECTIVE="${TUN_EFFECTIVE:-unknown}"

  TUI_ACTIVE_SUB="$(active_subscription_name 2>/dev/null || true)"
  TUI_CURRENT_NODE="$(status_current_proxy_brief 2>/dev/null || echo '未知')"
  TUI_MIXED_PORT="$(status_read_mixed_port 2>/dev/null || true)"
  TUI_CONTROLLER="$(status_read_controller 2>/dev/null || true)"
  TUI_KERNEL="$(runtime_kernel_type 2>/dev/null || echo 'mihomo')"
  TUI_BACKEND="$(runtime_backend 2>/dev/null || echo 'unknown')"
  TUI_CONNECTIVITY="$(connectivity_issue_text 2>/dev/null || echo '未知')"
  TUI_BOOT_AUTO="$(status_boot_auto_proxy_text 2>/dev/null || echo 'unknown')"
  TUI_PROXY_MODE="$(clash_mode_get 2>/dev/null || echo 'rule')"

  if system_proxy_supported 2>/dev/null; then
    TUI_SYS_PROXY="$(system_proxy_status 2>/dev/null || echo 'off')"
  else
    TUI_SYS_PROXY="unsupported"
  fi
}

# ─── 状态面板 ──────────────────────────────────────────────
tui_status_icon() {
  case "$1" in
    running|ready|on|true|healthy|effective|success)
      echo "●"
      ;;
    stopped|off|false|missing)
      echo "○"
      ;;
    degraded|medium|disabled|ineffective|failed)
      echo "◐"
      ;;
    broken|high|critical|invalid)
      echo "✖"
      ;;
    *)
      echo "◌"
      ;;
  esac
}

tui_status_color() {
  case "$1" in
    running|ready|on|true|healthy|effective|success|low)
      echo "$TUI_SUCCESS"
      ;;
    stopped|off|false|missing)
      echo "$TUI_MUTED"
      ;;
    degraded|medium|disabled|ineffective|unknown)
      echo "$TUI_WARNING"
      ;;
    broken|high|critical|invalid|failed)
      echo "$TUI_DANGER"
      ;;
    *)
      echo "$TUI_MUTED"
      ;;
  esac
}

tui_render_status_panel() {
  local runtime_icon runtime_text runtime_color
  local risk_icon risk_color

  runtime_icon="$(tui_status_icon "$TUI_RUNTIME_STATE")"
  runtime_color="$(tui_status_color "$TUI_RUNTIME_STATE")"
  case "$TUI_RUNTIME_STATE" in
    running) runtime_text="已运行" ;;
    stopped) runtime_text="已停止" ;;
    degraded) runtime_text="降级运行" ;;
    *) runtime_text="$TUI_RUNTIME_STATE" ;;
  esac

  risk_icon="$(tui_status_icon "$TUI_RISK_LEVEL")"
  risk_color="$(tui_status_color "$TUI_RISK_LEVEL")"

  local lines=""
  lines+="$(tui_kv_line "$runtime_icon" "代理状态" "$runtime_text")"$'\n'
  lines+="$(tui_kv_line "📡" "当前订阅" "${TUI_ACTIVE_SUB:-未设置}")"$'\n'
  lines+="$(tui_kv_line "🚀" "当前节点" "${TUI_CURRENT_NODE}")"$'\n'
  lines+="$(tui_kv_line "🌐" "可用性" "${TUI_CONNECTIVITY}")"$'\n'
  lines+="$(tui_kv_line "🗺" "代理模式" "${TUI_PROXY_MODE:-rule}")"$'\n'
  lines+="$(tui_kv_line "$risk_icon" "风险等级" "${TUI_RISK_LEVEL}")"$'\n'
  lines+="$(tui_kv_line "🔧" "运行内核" "${TUI_KERNEL}")"$'\n'
  lines+="$(tui_kv_line "⚙️" "运行后端" "${TUI_BACKEND}")"$'\n'

  if [ -n "${TUI_MIXED_PORT:-}" ] && [ "$TUI_MIXED_PORT" != "null" ]; then
    lines+="$(tui_kv_line "🌐" "代理端口" "${TUI_MIXED_PORT}")"$'\n'
  fi

  if [ "$TUI_TUN_ENABLED" = "true" ]; then
    local tun_icon tun_text
    tun_icon="$(tui_status_icon "$TUI_TUN_EFFECTIVE")"
    case "$TUI_TUN_EFFECTIVE" in
      effective) tun_text="已生效" ;;
      *) tun_text="未生效" ;;
    esac
    lines+="$(tui_kv_line "$tun_icon" "Tun 模式" "$tun_text")"$'\n'
  fi

  lines+="$(tui_kv_line "📜" "系统代理" "${TUI_SYS_PROXY}")"$'\n'
  lines+="$(tui_kv_line "🚦" "开机接管" "${TUI_BOOT_AUTO}")"

  gum style \
    --border rounded \
    --border-foreground "$TUI_PRIMARY" \
    --padding "0 1" \
    --margin "0 0" \
    -- "$lines"
}

# ─── 主菜单 ──────────────────────────────────────────────
tui_main_menu_items() {
  local items=()

  case "$TUI_RUNTIME_STATE" in
    running)
      items+=("⛔  关闭代理")
      ;;
    *)
      items+=("🚀  开启代理")
      ;;
  esac

  items+=("💫  切换节点")
  items+=("💱  切换订阅")
  items+=("🌐  代理模式")
  items+=("🔌  活跃连接")
  items+=("📡  订阅管理")
  items+=("📋  订阅列表")
  items+=("🔍  状态详情")
  items+=("🩺  系统诊断")
  items+=("📜  查看日志")
  items+=("🧩  配置管理")
  items+=("🧪  Tun 管理")
  items+=("🚦  开机接管")
  items+=("🔑  密钥管理")
  items+=("🔄  刷新状态")
  items+=("❌  退出")

  printf '%s\n' "${items[@]}"
}

tui_main_loop() {
  local choice

  while true; do
    clear
    tui_header "🐱 Clash TUI 控制台"
    echo

    tui_collect_status
    tui_render_status_panel
    echo

    choice="$(tui_main_menu_items | gum choose \
      --header "选择操作" \
      --header.foreground "$TUI_ACCENT" \
      --cursor.foreground "$TUI_PRIMARY" \
      --selected.foreground "$TUI_PRIMARY" \
      --height 16)" || break

    case "$choice" in
      "🚀  开启代理")        tui_proxy_on ;;
      "⛔  关闭代理")        tui_proxy_off ;;
      "💫  切换节点")        tui_node_select ;;
      "💱  切换订阅")        tui_subscription_use ;;
      "🌐  代理模式")        tui_mode_panel ;;
      "🔌  活跃连接")        tui_connections_panel ;;
      "📡  订阅管理")        tui_subscription_manage ;;
      "📋  订阅列表")        tui_subscription_list ;;
      "🔍  状态详情")        tui_status_detail ;;
      "🩺  系统诊断")        tui_doctor_panel ;;
      "📜  查看日志")        tui_log_viewer ;;
      "🧩  配置管理")        tui_config_panel ;;
      "🧪  Tun 管理")        tui_tun_panel ;;
      "🚦  开机接管")        tui_boot_panel ;;
      "🔑  密钥管理")        tui_secret_panel ;;
      "🔄  刷新状态")        continue ;;
      "❌  退出")            break ;;
      *)                      break ;;
    esac
  done

  clear
  echo "👋 已退出 Clash TUI"
}

# ─── 代理控制 ──────────────────────────────────────────────
tui_proxy_on() {
  clear
  tui_header "🚀 开启代理"
  echo

  if tui_confirm "确认开启代理？"; then
    echo
    cmd_on 2>&1 | tui_pager
  fi

  tui_press_enter
}

tui_proxy_off() {
  clear
  tui_header "⛔ 关闭代理"
  echo

  if tui_confirm "确认关闭代理？"; then
    echo
    cmd_off 2>&1 | tui_pager
  fi

  tui_press_enter
}

# ─── 节点选择 ──────────────────────────────────────────────
tui_node_select() {
  local group groups_arr group_choice
  local node nodes_arr current node_choice
  local type_label

  # 前置检查（只做一次）
  if ! status_is_running 2>/dev/null; then
    clear
    tui_header "💫 切换节点"
    echo
    gum style --foreground "$TUI_DANGER" -- "❗ 代理内核未运行，请先开启代理"
    tui_press_enter
    return
  fi

  if ! proxy_controller_reachable 2>/dev/null; then
    clear
    tui_header "💫 切换节点"
    echo
    gum style --foreground "$TUI_DANGER" -- "❗ 控制器不可访问"
    tui_press_enter
    return
  fi

  # ── 外层循环：策略组选择 ──────────────────────────────────
  while true; do
    clear
    tui_header "💫 切换节点"
    echo

    groups_arr=()
    while IFS= read -r group; do
      [ -n "${group:-}" ] || continue
      local gcurrent gtype
      gcurrent="$(proxy_group_current_display "$group" 2>/dev/null || echo '-')"
      gtype="$(proxy_group_type_label "$group" 2>/dev/null || echo 'unknown')"
      groups_arr+=("$group  │  $gtype  │  $gcurrent")
    done < <(proxy_group_display_list 2>/dev/null)

    if [ ${#groups_arr[@]} -eq 0 ]; then
      gum style --foreground "$TUI_WARNING" -- "📭 暂无可切换策略组"
      tui_press_enter
      return
    fi

    group_choice="$(printf '%s\n' "🔙  返回主菜单" "${groups_arr[@]}" | gum filter \
      --header "选择策略组（ESC / 🔙 返回主菜单）" \
      --header.foreground "$TUI_ACCENT" \
      --indicator.foreground "$TUI_PRIMARY" \
      --match.foreground "$TUI_PRIMARY" \
      --placeholder "搜索策略组..." \
      --height 20)" || return  # ESC → 返回主菜单

    case "$group_choice" in
      "🔙  返回主菜单"*) return ;;
    esac

    group="$(printf '%s' "$group_choice" | sed 's/[[:space:]]*│.*$//' | sed 's/[[:space:]]*$//')"
    [ -n "${group:-}" ] || continue

    # ── 内层循环：节点选择 ────────────────────────────────────
    local _tui_use_cached_delays=false
    declare -A _tui_delay_map=()

    while true; do
      clear
      tui_header "💫 切换节点"
      echo

      type_label="$(proxy_group_type_label "$group" 2>/dev/null || echo 'unknown')"
      current="$(proxy_group_current_display "$group" 2>/dev/null || echo '-')"

      # 获取延迟数据：优先使用测速缓存，否则从 API 读取
      if [ "$_tui_use_cached_delays" = "false" ]; then
        _tui_delay_map=()
        while IFS=$'\t' read -r _dn _dd; do
          [ -n "${_dn:-}" ] || continue
          _tui_delay_map["$_dn"]="${_dd:-0}"
        done < <(proxy_group_nodes_delay_map "$group" 2>/dev/null)
      fi
      _tui_use_cached_delays=false

      nodes_arr=()
      while IFS= read -r node; do
        [ -n "${node:-}" ] || continue
        local _dms="${_tui_delay_map[$node]:-0}"
        local _dbadge
        if [ "${_dms}" -eq 0 ] 2>/dev/null; then
          _dbadge="(?)"
        elif [ "${_dms}" -lt 200 ] 2>/dev/null; then
          _dbadge="(${_dms}ms)"
        elif [ "${_dms}" -lt 500 ] 2>/dev/null; then
          _dbadge="(${_dms}ms)"
        else
          _dbadge="(${_dms}ms)"
        fi
        if [ "$node" = "$current" ]; then
          nodes_arr+=("● $node  │  $_dbadge  [当前]")
        else
          nodes_arr+=("  $node  │  $_dbadge")
        fi
      done < <(proxy_group_selectable_nodes "$group" 2>/dev/null)

      if [ ${#nodes_arr[@]} -eq 0 ]; then
        gum style --foreground "$TUI_WARNING" -- "该策略组暂无可切换节点"
        tui_press_enter
        break  # 返回策略组选择
      fi

      tui_section_header "策略组：$group （$type_label）"
      echo "当前节点：$current"
      echo

      node_choice="$(printf '%s\n' "🔙  返回策略组" "⚡  测速所有节点" "${nodes_arr[@]}" | gum filter \
        --header "选择节点（ESC返回 / ⚡测速 / 搜索节点）" \
        --header.foreground "$TUI_ACCENT" \
        --indicator.foreground "$TUI_PRIMARY" \
        --match.foreground "$TUI_PRIMARY" \
        --placeholder "搜索节点..." \
        --height 20)" || break  # ESC → 返回策略组

      case "$node_choice" in
        "🔙  返回策略组"*) break ;; # 返回外层策略组选择

        "⚡  测速所有节点"*)
          # ── 并发测速：所有节点同时发起测速请求 ──────
          clear
          tui_header "💫 切换节点"
          echo
          tui_section_header "⚡ 延迟测速：$group"
          echo

          local _all_test=() _test_n
          while IFS= read -r _test_n; do
            [ -n "${_test_n:-}" ] || continue
            _all_test+=("$_test_n")
          done < <(proxy_group_selectable_nodes "$group" 2>/dev/null)

          local _total=${#_all_test[@]}
          gum style --foreground "$TUI_MUTED" -- "共 ${_total} 个节点，并发测速中（约 3 秒）..."
          echo

          local _tmpdir
          _tmpdir="$(mktemp -d)" || { tui_press_enter; continue; }

          local _i=0 _test_enc
          for _test_n in "${_all_test[@]}"; do
            _i=$(( _i + 1 ))
            _test_enc="$(proxy_node_url_encode "$_test_n")"
            (
              set +e
              _d="$(controller_curl GET \
                "/proxies/${_test_enc}/delay?timeout=3000&url=http://www.gstatic.com/generate_204" \
                2>/dev/null \
                | "$(yq_bin)" -p=json eval '.delay // 0' - 2>/dev/null)" || _d=0
              printf '%s\t%s\n' "$_test_n" "${_d:-0}" > "${_tmpdir}/${_i}"
            ) &
          done

          local _done=0
          while [ "${_done}" -lt "${_i}" ]; do
            _done=0
            local _k
            for (( _k=1; _k<=_i; _k++ )); do
              [ -f "${_tmpdir}/${_k}" ] && _done=$(( _done + 1 ))
            done
            printf '\r  已完成 %d / %d ...' "${_done}" "${_i}"
            [ "${_done}" -lt "${_i}" ] && sleep 0.2
          done
          wait || true
          printf '\r\033[K'

          # 展示结果并缓存到 _tui_delay_map
          _tui_delay_map=()
          local _rn _rd
          for (( _k=1; _k<=_i; _k++ )); do
            [ -f "${_tmpdir}/${_k}" ] || continue
            IFS=$'\t' read -r _rn _rd < "${_tmpdir}/${_k}"
            _rd="${_rd:-0}"
            _tui_delay_map["$_rn"]="$_rd"
            printf '  %-44.44s ' "${_rn}"
            if [ "${_rd}" -le 0 ] 2>/dev/null; then
              printf '\033[31m超时\033[0m\n'
            elif [ "${_rd}" -lt 200 ] 2>/dev/null; then
              printf '\033[32m%sms\033[0m\n' "${_rd}"
            elif [ "${_rd}" -lt 500 ] 2>/dev/null; then
              printf '\033[33m%sms\033[0m\n' "${_rd}"
            else
              printf '\033[31m%sms\033[0m\n' "${_rd}"
            fi
          done
          rm -rf "${_tmpdir}" 2>/dev/null || true

          echo
          gum style --foreground "$TUI_SUCCESS" --bold -- "✔ 测速完成"
          sleep 0.5
          _tui_use_cached_delays=true
          continue  # 留在当前策略组，使用缓存的延迟数据刷新节点列表
          ;;
      esac

      node="$(printf '%s' "$node_choice" | sed 's/^● //;s/^  //;s/[[:space:]]*│.*$//' | sed 's/[[:space:]]*$//')"
      [ -n "${node:-}" ] || continue

      if ! proxy_group_supports_manual_pick "$group" 2>/dev/null; then
        echo
        gum style --foreground "$TUI_WARNING" -- "$(proxy_group_manual_pick_error_message "$group")"
        tui_press_enter
        break  # 返回策略组选择
      fi

      echo
      if (proxy_group_select "$group" "$node") 2>/dev/null; then
        echo
        gum style --foreground "$TUI_SUCCESS" --bold -- "✔ 节点已切换"
        tui_kv_line "📦" "策略组" "$group"
        tui_kv_line "🚀" "当前节点" "$node"
      else
        echo
        gum style --foreground "$TUI_DANGER" -- "❗ 节点切换失败"
      fi

      tui_press_enter
      break  # 切换完成 → 返回策略组选择
    done
    # 外层 while 继续 → 重新显示策略组列表
  done
}

# ─── 订阅管理 ──────────────────────────────────────────────
tui_subscription_use() {
  local names_arr name_choice active idx
  local -a names=()

  clear
  tui_header "💱 切换订阅"
  echo

  active="$(active_subscription_name 2>/dev/null || true)"

  while IFS= read -r name_choice; do
    [ -n "${name_choice:-}" ] || continue
    names+=("$name_choice")
  done < <("$(yq_bin)" eval '.sources | keys | .[]' "$(subscriptions_file)" 2>/dev/null)

  if [ ${#names[@]} -eq 0 ]; then
    gum style --foreground "$TUI_WARNING" -- "当前没有任何订阅"
    tui_press_enter
    return
  fi

  names_arr=()
  for name_choice in "${names[@]}"; do
    local health enabled_text
    if subscription_enabled "$name_choice" 2>/dev/null; then
      enabled_text="启用"
    else
      enabled_text="禁用"
    fi
    health="$(subscription_health_status "$name_choice" 2>/dev/null || echo 'unknown')"

    if [ "$name_choice" = "$active" ]; then
      names_arr+=("● $name_choice  │  $enabled_text  │  $health  [当前]")
    else
      names_arr+=("  $name_choice  │  $enabled_text  │  $health")
    fi
  done

  echo "当前主订阅：${active:-未设置}"
  echo

  name_choice="$(printf '%s\n' "${names_arr[@]}" | gum choose \
    --header "选择要切换到的订阅" \
    --header.foreground "$TUI_ACCENT" \
    --cursor.foreground "$TUI_PRIMARY" \
    --selected.foreground "$TUI_PRIMARY")" || return

  name_choice="$(printf '%s' "$name_choice" | sed 's/^● //;s/^  //;s/[[:space:]]*│.*$//' | sed 's/[[:space:]]*$//')"
  [ -n "${name_choice:-}" ] || return

  echo
  gum spin --spinner dot --title "正在切换订阅..." -- sleep 0.5

  set_active_subscription "$name_choice" 2>/dev/null
  apply_runtime_change_after_config_mutation 2>/dev/null || true

  echo
  gum style --foreground "$TUI_SUCCESS" --bold -- "✔ 订阅已切换"
  tui_kv_line "📡" "当前主订阅" "$name_choice"

  tui_press_enter
}

tui_subscription_manage() {
  local choice

  while true; do
    clear
    tui_header "📡 订阅管理"
    echo

    choice="$(gum choose \
      --header "选择操作" \
      --header.foreground "$TUI_ACCENT" \
      --cursor.foreground "$TUI_PRIMARY" \
      "➕  添加订阅" \
      "📋  查看列表" \
      "💱  切换订阅" \
      "🩷  健康审计" \
      "🔙  返回主菜单")" || return

    case "$choice" in
      "➕  添加订阅")   tui_subscription_add ;;
      "📋  查看列表")   tui_subscription_list ;;
      "💱  切换订阅")   tui_subscription_use ;;
      "🩷  健康审计")   tui_health_audit ;;
      "🔙  返回主菜单") return ;;
      *)                 return ;;
    esac
  done
}

tui_subscription_add() {
  local url name fmt

  clear
  tui_header "➕ 添加订阅"
  echo

  url="$(gum input \
    --header "输入订阅地址" \
    --header.foreground "$TUI_ACCENT" \
    --placeholder "https://..." \
    --width 60)" || return

  url="$(printf '%s' "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -n "${url:-}" ] || return

  name="$(gum input \
    --header "输入订阅名称" \
    --header.foreground "$TUI_ACCENT" \
    --placeholder "my-sub" \
    --value "default" \
    --width 30)" || return

  [ -n "${name:-}" ] || name="default"

  echo
  gum spin --spinner dot --title "正在添加订阅..." -- sleep 0.5

  fmt="$(detect_subscription_format "$url" 2>/dev/null || echo 'clash')"
  set_subscription "$url" "$fmt" "$name" "false" 2>/dev/null
  set_active_subscription "$name" 2>/dev/null
  apply_runtime_change_after_config_mutation 2>/dev/null || true

  echo
  gum style --foreground "$TUI_SUCCESS" --bold -- "✔ 订阅已添加"
  tui_kv_line "📡" "名称" "$name"
  tui_kv_line "🌐" "地址" "$url"

  tui_press_enter
}

tui_subscription_list() {
  clear
  tui_header "📋 订阅列表"
  echo
  cmd_ls 2>&1 | tui_pager
  tui_press_enter
}

tui_health_audit() {
  clear
  tui_header "🩷 订阅健康审计"
  echo
  cmd_health 2>&1 | tui_pager
  tui_press_enter
}

# ─── 状态详情 ──────────────────────────────────────────────
tui_status_detail() {
  local mode

  clear
  tui_header "🔍 状态详情"
  echo

  mode="$(gum choose \
    --header "选择查看模式" \
    --header.foreground "$TUI_ACCENT" \
    --cursor.foreground "$TUI_PRIMARY" \
    "📊  简要状态" \
    "📜  详细状态" \
    "🔙  返回")" || return

  echo

  case "$mode" in
    "📊  简要状态")
      print_status_summary_compact 2>&1 | tui_pager
      ;;
    "📜  详细状态")
      print_status_summary_verbose 2>&1 | tui_pager
      ;;
    "🔙  返回")
      return
      ;;
  esac

  tui_press_enter
}

# ─── 诊断面板 ──────────────────────────────────────────────
tui_doctor_panel() {
  clear
  tui_header "🩺 系统诊断"
  echo

  gum spin --spinner dot --title "正在进行系统诊断..." -- sleep 0.3

  cmd_doctor 2>&1 | tui_pager
  tui_press_enter
}

# ─── 日志查看 ──────────────────────────────────────────────
tui_log_viewer() {
  local choice

  clear
  tui_header "📜 日志查看"
  echo

  choice="$(gum choose \
    --header "选择日志类型" \
    --header.foreground "$TUI_ACCENT" \
    --cursor.foreground "$TUI_PRIMARY" \
    "📜  Mihomo 日志" \
    "📜  Subconverter 日志" \
    "📜  服务日志" \
    "🔙  返回")" || return

  echo

  case "$choice" in
    "📜  Mihomo 日志")
      logs_mihomo 2>&1 | tui_pager
      ;;
    "📜  Subconverter 日志")
      logs_subconverter 2>&1 | tui_pager
      ;;
    "📜  服务日志")
      logs_service 2>&1 | tui_pager
      ;;
    "🔙  返回")
      return
      ;;
  esac

  tui_press_enter
}

# ─── 配置管理 ──────────────────────────────────────────────
tui_config_panel() {
  local choice

  while true; do
    clear
    tui_header "🧩 配置管理"
    echo

    choice="$(gum choose \
      --header "选择操作" \
      --header.foreground "$TUI_ACCENT" \
      --cursor.foreground "$TUI_PRIMARY" \
      "📊  查看配置状态" \
      "🔄  重新生成配置" \
      "🔧  切换运行内核" \
      "🧩  Mixin 管理" \
      "🔗  Relay 管理" \
      "🔙  返回主菜单")" || return

    case "$choice" in
      "📊  查看配置状态") tui_config_show ;;
      "🔄  重新生成配置") tui_config_regen ;;
      "🔧  切换运行内核") tui_config_kernel ;;
      "🧩  Mixin 管理")   tui_mixin_panel ;;
      "🔗  Relay 管理")   tui_relay_panel ;;
      "🔙  返回主菜单")   return ;;
      *)                    return ;;
    esac
  done
}

tui_config_show() {
  clear
  tui_header "📊 配置状态"
  echo
  cmd_config_show 2>&1 | tui_pager
  tui_press_enter
}

tui_config_regen() {
  clear
  tui_header "🔄 重新生成配置"
  echo

  if tui_confirm "确认重新生成运行配置？"; then
    echo
    gum spin --spinner dot --title "正在重新生成配置..." -- sleep 0.3
    regenerate_config 2>&1
    apply_runtime_change_after_config_mutation 2>&1 || true
    echo
    gum style --foreground "$TUI_SUCCESS" --bold -- "✔ 配置已重新生成"
    print_config_apply_feedback 2>&1
  fi

  tui_press_enter
}

tui_config_kernel() {
  local choice current

  clear
  tui_header "🔧 切换运行内核"
  echo

  current="$(runtime_kernel_type 2>/dev/null || echo 'mihomo')"
  echo "当前内核：$current"
  echo

  choice="$(gum choose \
    --header "选择运行内核" \
    --header.foreground "$TUI_ACCENT" \
    --cursor.foreground "$TUI_PRIMARY" \
    "mihomo" \
    "clash" \
    "取消")" || return

  [ "$choice" != "取消" ] || return

  echo
  gum spin --spinner dot --title "正在切换内核..." -- sleep 0.3
  write_runtime_kernel_type "$choice" 2>/dev/null
  resolve_runtime_kernel 2>/dev/null
  regenerate_config 2>/dev/null
  apply_runtime_change_after_config_mutation 2>/dev/null || true

  echo
  gum style --foreground "$TUI_SUCCESS" --bold -- "✔ 内核已切换"
  tui_kv_line "🚀" "当前内核" "$choice"

  tui_press_enter
}

tui_mixin_panel() {
  local choice

  clear
  tui_header "🧩 Mixin 管理"
  echo

  choice="$(gum choose \
    --header "选择操作" \
    --header.foreground "$TUI_ACCENT" \
    --cursor.foreground "$TUI_PRIMARY" \
    "📊  查看 Mixin" \
    "✏️  编辑 Mixin" \
    "🔙  返回")" || return

  case "$choice" in
    "📊  查看 Mixin")
      cmd_mixin_show 2>&1 | tui_pager
      tui_press_enter
      ;;
    "✏️  编辑 Mixin")
      local file
      ensure_config_files 2>/dev/null || true
      file="$(mixin_config_file 2>/dev/null || true)"
      if [ -n "${file:-}" ]; then
        open_editor_for_file "$file"
      fi
      ;;
    "🔙  返回")
      return
      ;;
  esac
}

tui_relay_panel() {
  local choice

  while true; do
    clear
    tui_header "🔗 Relay 多跳管理"
    echo

    choice="$(gum choose \
      --header "选择操作" \
      --header.foreground "$TUI_ACCENT" \
      --cursor.foreground "$TUI_PRIMARY" \
      "📋  查看 Relay 列表" \
      "➕  添加 Relay" \
      "🔙  返回")" || return

    case "$choice" in
      "📋  查看 Relay 列表")
        cmd_relay_list 2>&1 | tui_pager
        tui_press_enter
        ;;
      "➕  添加 Relay")
        echo
        gum style --foreground "$TUI_INFO" -- "请使用命令行添加 Relay："
        echo "  clashctl relay add <名称> <节点A> <节点B> [--domain <域名>]"
        tui_press_enter
        ;;
      "🔙  返回")
        return
        ;;
    esac
  done
}

# ─── Tun 管理 ──────────────────────────────────────────────
tui_tun_panel() {
  local choice

  while true; do
    clear
    tui_header "🧪 Tun 模式管理"
    echo

    local tun_enabled tun_effective
    tun_enabled="$(tun_enabled 2>/dev/null || echo false)"
    tun_effective="$(status_tun_effective_status 2>/dev/null || echo unknown)"

    tui_kv_line "🧪" "Tun 开关" "$tun_enabled"
    tui_kv_line "🧪" "Tun 状态" "$tun_effective"
    echo

    choice="$(gum choose \
      --header "选择操作" \
      --header.foreground "$TUI_ACCENT" \
      --cursor.foreground "$TUI_PRIMARY" \
      "🟢  开启 Tun" \
      "🔴  关闭 Tun" \
      "🔍  Tun 状态详情" \
      "🩺  Tun 诊断" \
      "🔙  返回主菜单")" || return

    case "$choice" in
      "🟢  开启 Tun")
        if tui_confirm "确认开启 Tun 模式？"; then
          echo
          cmd_tun_on 2>&1 | tui_pager
        fi
        tui_press_enter
        ;;
      "🔴  关闭 Tun")
        if tui_confirm "确认关闭 Tun 模式？"; then
          echo
          cmd_tun_off 2>&1 | tui_pager
        fi
        tui_press_enter
        ;;
      "🔍  Tun 状态详情")
        cmd_tun_status 2>&1 | tui_pager
        tui_press_enter
        ;;
      "🩺  Tun 诊断")
        tui_tun_doctor
        ;;
      "🔙  返回主菜单")
        return
        ;;
    esac
  done
}

tui_tun_doctor() {
  clear
  tui_header "🩺 Tun 诊断"
  echo

  gum spin --spinner dot --title "正在进行 Tun 诊断..." -- sleep 0.3
  # cmd_tun doctor 需要通过 cmd_tun 调用
  (cmd_tun doctor) 2>&1 | tui_pager
  tui_press_enter
}

# ─── 开机接管 ──────────────────────────────────────────────
tui_boot_panel() {
  local choice

  while true; do
    clear
    tui_header "🚦 开机代理接管"
    echo

    tui_kv_line "🔧" "运行后端" "$(runtime_backend 2>/dev/null || echo unknown)"
    tui_kv_line "🚦" "内核开机自启" "$(status_service_autostart_text 2>/dev/null || echo unknown)"
    tui_kv_line "📜" "开机代理保持" "$(status_boot_proxy_keep_text 2>/dev/null || echo unknown)"
    tui_kv_line "🐱" "开机代理接管" "$(status_boot_auto_proxy_text 2>/dev/null || echo unknown)"
    echo

    choice="$(gum choose \
      --header "选择操作" \
      --header.foreground "$TUI_ACCENT" \
      --cursor.foreground "$TUI_PRIMARY" \
      "🟢  开启开机接管" \
      "🔴  关闭开机接管" \
      "🔙  返回主菜单")" || return

    case "$choice" in
      "🟢  开启开机接管")
        if tui_confirm "确认开启开机代理接管？"; then
          echo
          cmd_boot on 2>&1 | tui_pager
        fi
        tui_press_enter
        ;;
      "🔴  关闭开机接管")
        if tui_confirm "确认关闭开机代理接管？"; then
          echo
          cmd_boot off 2>&1 | tui_pager
        fi
        tui_press_enter
        ;;
      "🔙  返回主菜单")
        return
        ;;
    esac
  done
}

# ─── 密钥管理 ──────────────────────────────────────────────
tui_secret_panel() {
  local choice current

  clear
  tui_header "🔑 密钥管理"
  echo

  current="$(controller_secret 2>/dev/null || true)"
  if [ -n "${current:-}" ] && [ "$current" != "null" ]; then
    tui_kv_line "🔑" "当前密钥" "$current"
  else
    tui_kv_line "🔑" "当前密钥" "未设置"
  fi
  echo

  choice="$(gum choose \
    --header "选择操作" \
    --header.foreground "$TUI_ACCENT" \
    --cursor.foreground "$TUI_PRIMARY" \
    "🔄  自动生成新密钥" \
    "✏️  手动设置密钥" \
    "🔙  返回")" || return

  case "$choice" in
    "🔄  自动生成新密钥")
      cmd_secret 2>&1
      tui_press_enter
      ;;
    "✏️  手动设置密钥")
      local new_secret
      new_secret="$(gum input \
        --header "输入新密钥" \
        --header.foreground "$TUI_ACCENT" \
        --placeholder "输入密钥..." \
        --width 40)" || return

      if [ -n "${new_secret:-}" ]; then
        cmd_secret "$new_secret" 2>&1
      fi
      tui_press_enter
      ;;
    "🔙  返回")
      return
      ;;
  esac
}

# ─── 通用辅助 ──────────────────────────────────────────────
tui_press_enter() {
  echo
  gum style --foreground "$TUI_MUTED" -- "按 Enter 继续..."
  read -r _ 2>/dev/null || true
}

# ─── 入口 ──────────────────────────────────────────────────

# ─── 代理模式切换 ──────────────────────────────────────────
tui_mode_panel() {
  local current choice mode

  while true; do
    clear
    tui_header "🌐 代理模式"
    echo

    current="$(clash_mode_get 2>/dev/null || echo 'rule')"

    case "$current" in
      global) tui_kv_line "🌍" "当前模式" "全局 (global)" ;;
      direct) tui_kv_line "🔗" "当前模式" "直连 (direct)" ;;
      rule)   tui_kv_line "📋" "当前模式" "规则 (rule)" ;;
      *)      tui_kv_line "🗺" "当前模式" "$current" ;;
    esac
    echo

    choice="$(gum choose \
      --header "选择代理模式" \
      --header.foreground "$TUI_ACCENT" \
      --cursor.foreground "$TUI_PRIMARY" \
      --selected.foreground "$TUI_PRIMARY" \
      "🌍  全局模式 (global)  — 所有流量走代理" \
      "📋  规则模式 (rule)    — 按规则分流（推荐）" \
      "��  直连模式 (direct)  — 所有流量直连" \
      "🔙  返回主菜单")" || return

    case "$choice" in
      "🌍  全局模式 (global)"*) mode="global" ;;
      "📋  规则模式 (rule)"*)   mode="rule" ;;
      "🔗  直连模式 (direct)"*) mode="direct" ;;
      "🔙  返回主菜单") return ;;
      *) return ;;
    esac

    echo
    gum spin --spinner dot --title "正在切换模式..." -- sleep 0.3

    if clash_mode_set "$mode" 2>/dev/null; then
      TUI_PROXY_MODE="$mode"
      echo
      gum style --foreground "$TUI_SUCCESS" --bold -- "✔ 模式已切换"
      tui_kv_line "🗺" "当前模式" "$mode"
    else
      echo
      gum style --foreground "$TUI_DANGER" -- "❗ 模式切换失败，请确认内核正在运行"
    fi

    tui_press_enter
  done
}

# ─── 活跃连接 ──────────────────────────────────────────────
tui_connections_panel() {
  if ! status_is_running 2>/dev/null; then
    clear; tui_header "🔌 活跃连接"; echo
    gum style --foreground "$TUI_DANGER" -- "❗ 代理内核未运行"
    tui_press_enter; return
  fi
  if ! proxy_controller_reachable 2>/dev/null; then
    clear; tui_header "🔌 活跃连接"; echo
    gum style --foreground "$TUI_DANGER" -- "❗ 控制器不可访问"
    tui_press_enter; return
  fi

  local page=0 page_size=20

  while true; do
    clear
    tui_header "🔌 活跃连接"
    echo

    local conn_json count dl_b ul_b dl ul
    conn_json="$(connections_json 2>/dev/null)" || conn_json='{"connections":[]}'

    count="$(printf '%s\n' "$conn_json" | "$(yq_bin)" -p=json eval '.connections | length' - 2>/dev/null)" || count=0
    dl_b="$(printf '%s\n' "$conn_json" | "$(yq_bin)" -p=json eval '[.connections[].download // 0] | add // 0' - 2>/dev/null)" || dl_b=0
    ul_b="$(printf '%s\n' "$conn_json" | "$(yq_bin)" -p=json eval '[.connections[].upload   // 0] | add // 0' - 2>/dev/null)" || ul_b=0
    dl=$(( ${dl_b:-0} / 1024 ))
    ul=$(( ${ul_b:-0} / 1024 ))

    tui_kv_line "🔌" "活跃连接数" "${count:-0}"
    tui_kv_line "📊" "累计流量"   "${dl:-0}KB↓  ${ul:-0}KB↑"
    echo

    if [ "${count:-0}" -le 0 ]; then
      gum style --foreground "$TUI_MUTED" -- "暂无活跃连接"
      echo
    else
      # yq 只做字段提取，不做截断和数学运算
      local all_rows
      all_rows="$(printf '%s\n' "$conn_json" | "$(yq_bin)" -p=json eval '
          .connections[] |
          (.metadata.host // .metadata.destinationIP // "-") + "|" +
          (.metadata.type // .metadata.network // "-")       + "|" +
          ((.chains // []) | reverse | join("→"))             + "|" +
          (.rule // "-")                                      + "|" +
          ((.download // 0) | tostring)                       + "|" +
          ((.upload   // 0) | tostring)
        ' - 2>/dev/null)" || all_rows=""

      local total_rows
      total_rows="$(printf '%s\n' "$all_rows" | grep -c . 2>/dev/null)" || total_rows=0
      local total_pages=$(( (total_rows + page_size - 1) / page_size ))
      [ "${total_pages:-0}" -le 0 ] && total_pages=1

      local start_row=$(( page * page_size + 1 ))
      local end_row=$(( page * page_size + page_size ))
      local page_rows
      page_rows="$(printf '%s\n' "$all_rows" | sed -n "${start_row},${end_row}p" 2>/dev/null)" || page_rows=""

      # 表头
      gum style --foreground "$TUI_ACCENT" --bold -- \
        "$(printf '%-36s  %-7s  %-26s  %-14s  %s' "目标主机" "协议" "代理链" "规则" "流量")"
      gum style --foreground "$TUI_MUTED" -- "$(printf '%.0s─' {1..98})"

      if [ -n "$page_rows" ]; then
        while IFS='|' read -r host proto chain rule dl_row ul_row; do
          local dlk ulk
          dlk=$(( ${dl_row:-0} / 1024 ))
          ulk=$(( ${ul_row:-0} / 1024 ))
          printf '%-36.36s  %-7.7s  %-26.26s  %-14.14s  %sK↓ %sK↑\n' \
            "$host" "$proto" "$chain" "$rule" "$dlk" "$ulk"
        done <<< "$page_rows"
      fi

      echo
      gum style --foreground "$TUI_MUTED" -- \
        "第 $((page+1)) / ${total_pages} 页（共 ${total_rows} 条）"
      echo

      local menu_items=("🔄  刷新")
      [ $((page+1)) -lt "$total_pages" ] && menu_items+=("▶  下一页")
      [ "$page" -gt 0 ]                  && menu_items+=("◀  上一页")
      menu_items+=("🔙  返回主菜单")

      local choice
      choice="$(printf '%s\n' "${menu_items[@]}" | gum choose \
        --header "操作" \
        --header.foreground "$TUI_ACCENT" \
        --cursor.foreground "$TUI_PRIMARY")" || return

      case "$choice" in
        "🔄  刷新")   page=0; continue ;;
        "▶  下一页")  page=$((page+1)); continue ;;
        "◀  上一页")  page=$((page-1)); continue ;;
        *)            return ;;
      esac
      continue
    fi

    local choice
    choice="$(gum choose \
      --header "操作" \
      --header.foreground "$TUI_ACCENT" \
      --cursor.foreground "$TUI_PRIMARY" \
      "🔄  刷新" \
      "🔙  返回主菜单")" || return
    case "$choice" in
      "🔄  刷新") continue ;;
      *)          return ;;
    esac
  done
}
# ─── 延迟测速 ──────────────────────────────────────────────
tui_latency_test() {
  local group="$1"

  clear
  tui_header "🔬 延迟测速"
  echo

  if [ -z "${group:-}" ]; then
    groups_arr=()
    while IFS= read -r group; do
      [ -n "${group:-}" ] || continue
      groups_arr+=("$group")
    done < <(proxy_group_display_list 2>/dev/null)

    if [ ${#groups_arr[@]} -eq 0 ]; then
      gum style --foreground "$TUI_WARNING" -- "暂无可用策略组"
      tui_press_enter
      return
    fi

    group="$(printf '%s\n' "${groups_arr[@]}" | gum choose \
      --header "选择要测速的策略组" \
      --header.foreground "$TUI_ACCENT" \
      --cursor.foreground "$TUI_PRIMARY" \
      --height 16)" || return
  fi

  echo
  tui_section_header "策略组：$group"
  echo

  local _all_test=() _test_n
  while IFS= read -r _test_n; do
    [ -n "${_test_n:-}" ] || continue
    _all_test+=("$_test_n")
  done < <(proxy_group_selectable_nodes "$group" 2>/dev/null)

  if [ ${#_all_test[@]} -eq 0 ]; then
    gum style --foreground "$TUI_WARNING" -- "该策略组无可测速节点"
    tui_press_enter
    return
  fi

  local _total=${#_all_test[@]}
  gum style --foreground "$TUI_MUTED" -- "共 ${_total} 个节点，并发测速中（约 3 秒）..."
  echo

  local _tmpdir
  _tmpdir="$(mktemp -d)" || { tui_press_enter; return; }

  local _i=0 _test_enc
  for _test_n in "${_all_test[@]}"; do
    _i=$(( _i + 1 ))
    _test_enc="$(proxy_node_url_encode "$_test_n")"
    (
      set +e
      _d="$(controller_curl GET \
        "/proxies/${_test_enc}/delay?timeout=3000&url=http://www.gstatic.com/generate_204" \
        2>/dev/null \
        | "$(yq_bin)" -p=json eval '.delay // 0' - 2>/dev/null)" || _d=0
      printf '%s\t%s\n' "$_test_n" "${_d:-0}" > "${_tmpdir}/${_i}"
    ) &
  done

  local _done=0
  while [ "${_done}" -lt "${_i}" ]; do
    _done=0
    local _k
    for (( _k=1; _k<=_i; _k++ )); do
      [ -f "${_tmpdir}/${_k}" ] && _done=$(( _done + 1 ))
    done
    printf '\r  已完成 %d / %d ...' "${_done}" "${_i}"
    [ "${_done}" -lt "${_i}" ] && sleep 0.2
  done
  wait || true
  printf '\r\033[K'

  local _rn _rd
  for (( _k=1; _k<=_i; _k++ )); do
    [ -f "${_tmpdir}/${_k}" ] || continue
    IFS=$'\t' read -r _rn _rd < "${_tmpdir}/${_k}"
    _rd="${_rd:-0}"
    printf '  %-40s ' "${_rn}"
    if [ "${_rd}" -le 0 ] 2>/dev/null; then
      printf '\033[31m超时/失败\033[0m\n'
    elif [ "${_rd}" -lt 200 ] 2>/dev/null; then
      printf '\033[32m%sms ▓▓▓\033[0m\n' "${_rd}"
    elif [ "${_rd}" -lt 500 ] 2>/dev/null; then
      printf '\033[33m%sms ▓▓░\033[0m\n' "${_rd}"
    else
      printf '\033[31m%sms ▓░░\033[0m\n' "${_rd}"
    fi
  done
  rm -rf "${_tmpdir}" 2>/dev/null || true

  echo
  gum style --foreground "$TUI_SUCCESS" --bold -- "✔ 测速完成"

  tui_press_enter
}

cmd_tui() {
  prepare
  tui_ensure_gum
  tui_main_loop
}
