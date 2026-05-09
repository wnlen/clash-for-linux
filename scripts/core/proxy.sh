#!/usr/bin/env bash

# shellcheck source=scripts/core/common.sh
source "${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/core/common.sh"

proxy_host() {
  echo "${CLASH_PROXY_HOST:-127.0.0.1}"
}

proxy_port() {
  local config_file="${1:-$RUNTIME_DIR/config.yaml}"
  local port

  [ -s "$config_file" ] || die "配置文件不存在：$config_file"

  port="$("$(yq_bin)" eval '.["mixed-port"] // .port // ""' "$config_file" 2>/dev/null | head -n 1)"
  [ -n "${port:-}" ] && [ "$port" != "null" ] || die "未在配置文件中找到代理端口"

  echo "$port"
}

proxy_http_url() {
  echo "http://$(proxy_host):$(proxy_port)"
}

proxy_socks_url() {
  echo "socks5://$(proxy_host):$(proxy_port)"
}

proxy_no_proxy_value() {
  echo "${NO_PROXY_DEFAULT:-127.0.0.1,localhost,::1}"
}

system_proxy_env_file() {
  echo "${SYSTEM_PROXY_ENV_FILE:-/etc/environment}"
}

system_proxy_block_begin() {
  echo "# >>> clash-for-linux system proxy >>>"
}

system_proxy_block_end() {
  echo "# <<< clash-for-linux system proxy <<<"
}

system_proxy_supported() {
  local file dir

  file="$(system_proxy_env_file)"
  dir="$(dirname "$file")"

  if [ -f "$file" ]; then
    [ -w "$file" ]
    return $?
  fi

  [ -d "$dir" ] && [ -w "$dir" ]
}

system_proxy_status() {
  local file
  file="$(system_proxy_env_file)"

  [ -f "$file" ] || {
    echo "off"
    return 0
  }

  if grep -Fq "$(system_proxy_block_begin)" "$file" 2>/dev/null; then
    echo "on"
  else
    echo "off"
  fi
}

system_proxy_http_value() {
  local file value
  file="$(system_proxy_env_file)"
  [ -f "$file" ] || return 1

  value="$(sed -nE 's/^http_proxy="?([^"\r\n]+)"?$/\1/p' "$file" | tail -n 1)"
  [ -n "${value:-}" ] || return 1

  echo "$value"
}

system_proxy_matches_runtime() {
  local expected actual

  expected="$(proxy_http_url 2>/dev/null || true)"
  actual="$(system_proxy_http_value 2>/dev/null || true)"

  [ -n "${expected:-}" ] || return 1
  [ -n "${actual:-}" ] || return 1
  [ "$expected" = "$actual" ]
}

system_proxy_write_block() {
  local mode="$1"
  local file tmp http_url socks_url no_proxy

  file="$(system_proxy_env_file)"
  tmp="$(mktemp)"

  [ -f "$file" ] && cat "$file" > "$tmp"

  awk -v begin="$(system_proxy_block_begin)" -v end="$(system_proxy_block_end)" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    skip != 1 {print}
  ' "$tmp" > "${tmp}.clean"

  mv -f "${tmp}.clean" "$tmp"

  if [ "$mode" = "on" ]; then
    if ! http_url="$(proxy_http_url 2>/dev/null)"; then
      rm -f "$tmp" 2>/dev/null || true
      return 1
    fi
    if ! socks_url="$(proxy_socks_url 2>/dev/null)"; then
      rm -f "$tmp" 2>/dev/null || true
      return 1
    fi
    no_proxy="$(proxy_no_proxy_value)"

    {
      echo "$(system_proxy_block_begin)"
      echo "http_proxy="$http_url""
      echo "https_proxy="$http_url""
      echo "HTTP_PROXY="$http_url""
      echo "HTTPS_PROXY="$http_url""
      echo "all_proxy="$socks_url""
      echo "ALL_PROXY="$socks_url""
      echo "no_proxy="$no_proxy""
      echo "NO_PROXY="$no_proxy""
      echo "$(system_proxy_block_end)"
    } >> "$tmp"
  fi

  cat "$tmp" > "$file"
  rm -f "$tmp" 2>/dev/null || true
}

system_proxy_enable() {
  system_proxy_supported || return 2
  system_proxy_write_block "on"
  write_runtime_value "RUNTIME_BOOT_PROXY_KEEP" "true"
}

system_proxy_disable() {
  system_proxy_supported || return 2
  system_proxy_write_block "off"
  write_runtime_value "RUNTIME_BOOT_PROXY_KEEP" "false"
}

boot_proxy_keep_status() {
  local status
  status="$(system_proxy_status 2>/dev/null || echo off)"

  if [ "$status" = "on" ]; then
    echo "on"
    return 0
  fi

  if ! system_proxy_supported; then
    echo "unsupported"
    return 0
  fi

  echo "off"
}

boot_proxy_keep_enable() {
  system_proxy_enable
}

boot_proxy_keep_disable() {
  if ! system_proxy_supported && [ "$(system_proxy_status 2>/dev/null || echo off)" = "off" ]; then
    write_runtime_value "RUNTIME_BOOT_PROXY_KEEP" "false"
    return 0
  fi

  system_proxy_disable
}

print_proxy_show() {
  local status
  status="$(system_proxy_status)"

  echo
  echo "🐱 当前代理环境"
  echo
  echo "🌐 HTTP：$(proxy_http_url)"
  echo "🧦 SOCKS5：$(proxy_socks_url)"
  echo "🚫 NO_PROXY：$(proxy_no_proxy_value)"
  echo "📜 系统代理：${status}（$(system_proxy_env_file)）"
  echo
}

controller_addr() {
  local config_file="${1:-$RUNTIME_DIR/config.yaml}"

  [ -s "$config_file" ] || die "配置文件不存在：$config_file"

  "$(yq_bin)" eval '.["external-controller"] // ""' "$config_file" 2>/dev/null | head -n 1
}

controller_secret() {
  local config_file="${1:-$RUNTIME_DIR/config.yaml}"

  [ -s "$config_file" ] || die "配置文件不存在：$config_file"

  "$(yq_bin)" eval '.secret // ""' "$config_file" 2>/dev/null | head -n 1
}

controller_api_base() {
  local addr host port

  addr="$(controller_addr)"
  [ -n "${addr:-}" ] || die "未找到 external-controller"
  [ "$addr" != "null" ] || die "未找到 external-controller"

  host="${addr%:*}"
  port="${addr##*:}"
  case "$host" in
    0.0.0.0)
      addr="127.0.0.1:${port}"
      ;;
  esac

  echo "http://$addr"
}

controller_curl() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local base secret

  base="$(controller_api_base)"
  secret="$(controller_secret)"

  if [ -n "${data:-}" ]; then
    curl -fsSL -X "$method" \
      -H "Content-Type: application/json" \
      ${secret:+-H "Authorization: Bearer $secret"} \
      --data "$data" \
      "$base$path"
  else
    curl -fsSL -X "$method" \
      ${secret:+-H "Authorization: Bearer $secret"} \
      "$base$path"
  fi
}

proxy_controller_reachable() {
  controller_curl GET "/version" >/dev/null 2>&1
}

proxy_groups_json() {
  controller_curl GET "/proxies"
}

proxy_group_exists() {
  local group="$1"

  [ -n "${group:-}" ] || return 1

  [ "$(
    GROUP="$group" proxy_groups_json \
      | GROUP="$group" "$(yq_bin)" -p=json eval \
          '.proxies | to_entries | .[] | select(.key == env(GROUP)) | "true"' \
          - 2>/dev/null \
      | head -n 1
  )" = "true" ]
}

proxy_group_type() {
  local group="$1"

  [ -n "${group:-}" ] || die "策略组名称不能为空"
  proxy_group_exists "$group" || die "策略组不存在：$group"

  GROUP="$group" proxy_groups_json \
    | GROUP="$group" "$(yq_bin)" -p=json eval \
        '.proxies | to_entries | .[] | select(.key == env(GROUP)) | .value.type // ""' \
        - 2>/dev/null
}

proxy_group_type_key() {
  local type

  type="$(proxy_group_type "$1" 2>/dev/null || true)"
  printf '%s' "${type:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]_-'
}

proxy_group_type_label() {
  local group="$1"
  local type_key raw_type

  type_key="$(proxy_group_type_key "$group")"

  case "$type_key" in
    selector)
      echo "select"
      ;;
    urltest)
      echo "自动选择 / url-test"
      ;;
    fallback)
      echo "故障转移 / fallback"
      ;;
    loadbalance)
      echo "负载均衡 / load-balance"
      ;;
    *)
      raw_type="$(proxy_group_type "$group" 2>/dev/null || true)"
      if [ -n "${raw_type:-}" ] && [ "$raw_type" != "null" ]; then
        echo "$raw_type"
      else
        echo "unknown"
      fi
      ;;
  esac
}

proxy_group_can_show_candidates() {
  local type_key

  type_key="$(proxy_group_type_key "$1")"

  case "$type_key" in
    selector|urltest|fallback|loadbalance)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

proxy_group_is_selector() {
  proxy_group_can_show_candidates "$1"
}

proxy_group_is_manual_selector() {
  proxy_group_supports_manual_pick "$1"
}

proxy_group_is_auto_managed() {
  local group="$1"
  local type_key

  [ -n "${group:-}" ] || return 0
  proxy_group_exists "$group" || return 0

  type_key="$(proxy_group_type_key "$group")"

  case "$type_key" in
    urltest|fallback|loadbalance)
      return 0
      ;;
  esac

  case "$group" in
    自动选择|故障转移)
      return 0
      ;;
  esac

  return 1
}

proxy_group_list() {
  proxy_groups_json \
    | "$(yq_bin)" -p=json eval '
        .proxies
        | to_entries
        | map(select(.value.all != null))
        | .[].key
      ' - 2>/dev/null
}

proxy_group_current() {
  local group="$1"

  [ -n "${group:-}" ] || die "策略组名称不能为空"
  proxy_group_exists "$group" || die "策略组不存在：$group"

  GROUP="$group" proxy_groups_json \
    | GROUP="$group" "$(yq_bin)" -p=json eval \
        '.proxies | to_entries | .[] | select(.key == env(GROUP)) | .value.now // ""' \
        - 2>/dev/null
}

proxy_group_nodes() {
  local group="$1"

  [ -n "${group:-}" ] || die "策略组名称不能为空"
  proxy_group_exists "$group" || die "策略组不存在：$group"

  GROUP="$group" proxy_groups_json \
    | GROUP="$group" "$(yq_bin)" -p=json eval \
        '.proxies | to_entries | .[] | select(.key == env(GROUP)) | .value.all[] // ""' \
        - 2>/dev/null
}

proxy_node_is_descriptive_entry() {
  local node="$1"

  case "${node:-}" in
    "")
      return 0
      ;;
    剩余流量：*|剩余流量:*|套餐到期：*|套餐到期:*|到期时间：*|到期时间:*|流量重置：*|流量重置:*|官网：*|官网:*|通知：*|通知:*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

proxy_node_is_selectable_candidate() {
  local node="$1"

  proxy_node_is_descriptive_entry "$node" && return 1
  return 0
}

proxy_group_selectable_nodes() {
  local group="$1"
  local node

  [ -n "${group:-}" ] || die "策略组名称不能为空"
  proxy_group_exists "$group" || die "策略组不存在：$group"

  while IFS= read -r node; do
    [ -n "${node:-}" ] || continue
    proxy_node_is_selectable_candidate "$node" || continue
    echo "$node"
  done < <(proxy_group_nodes "$group")
}

proxy_group_has_selectable_candidates() {
  local group="$1"
  local node

  [ -n "${group:-}" ] || return 1
  proxy_group_exists "$group" || return 1
  proxy_group_can_show_candidates "$group" || return 1

  while IFS= read -r node; do
    [ -n "${node:-}" ] || continue
    return 0
  done < <(proxy_group_selectable_nodes "$group")

  return 1
}

proxy_group_manual_pick_error_message() {
  local group="$1"
  local type_key type_label

  [ -n "${group:-}" ] || {
    echo "该策略组不支持手动切换"
    return 0
  }

  type_key="$(proxy_group_type_key "$group")"
  type_label="$(proxy_group_type_label "$group")"

  case "$type_key" in
    urltest|fallback|loadbalance)
      echo "该策略组为${type_label}类型，不支持手动切换：$group"
      ;;
    *)
      echo "该策略组不支持手动切换：$group"
      ;;
  esac
}

proxy_group_supports_manual_pick() {
  local group="$1"
  local has_now=""
  local type_key

  [ -n "${group:-}" ] || return 1
  proxy_group_exists "$group" || return 1

  type_key="$(proxy_group_type_key "$group")"
  [ "$type_key" = "selector" ] || return 1

  has_now="$(
    GROUP="$group" proxy_groups_json \
      | GROUP="$group" "$(yq_bin)" -p=json eval \
          '.proxies | to_entries | .[] | select(.key == env(GROUP)) | .value.now != null' \
          - 2>/dev/null \
      | head -n 1
  )"
  [ "${has_now:-false}" = "true" ] || return 1

  proxy_group_has_selectable_candidates "$group"
}

proxy_group_display_list() {
  local group

  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    proxy_group_has_selectable_candidates "$group" || continue
    echo "$group"
  done < <(proxy_group_list)
}

proxy_group_manual_list() {
  local group

  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    proxy_group_supports_manual_pick "$group" || continue
    echo "$group"
  done < <(proxy_group_list)
}

proxy_group_select() {
  local group="$1"
  local node="$2"
  local base secret
  local code response_file response_body
  local available_node found

  [ -n "${group:-}" ] || die "策略组名称不能为空"
  [ -n "${node:-}" ] || die "节点名称不能为空"

  proxy_group_exists "$group" || die "策略组不存在：$group"
  proxy_group_supports_manual_pick "$group" || die "该策略组不支持手动切换：$group"

  found=false
  while IFS= read -r available_node; do
    [ -n "${available_node:-}" ] || continue
    if [ "$available_node" = "$node" ]; then
      found=true
      break
    fi
  done < <(proxy_group_selectable_nodes "$group")

  if [ "$found" != "true" ]; then
    die "节点不存在于策略组中：$group -> $node"
  fi

  base="$(controller_api_base)"
  secret="$(controller_secret)"
  response_file="$(mktemp)"
  code="$(
    curl -sS -o "$response_file" -w "%{http_code}" -X PUT \
      -H "Content-Type: application/json" \
      ${secret:+-H "Authorization: Bearer $secret"} \
      --data "{\"name\":\"$node\"}" \
      "$base/proxies/$group"
  )"

  if [ "${code:-000}" -lt 200 ] || [ "${code:-000}" -ge 300 ]; then
    response_body="$(cat "$response_file" 2>/dev/null || true)"
    rm -f "$response_file" 2>/dev/null || true
    if [ -n "${response_body:-}" ]; then
      die "节点切换失败：$response_body"
    fi
    die "节点切换失败：controller 返回 HTTP $code"
  fi

  rm -f "$response_file" 2>/dev/null || true
}

proxy_group_select() {
  local group="$1"
  local node="$2"
  local base secret
  local code response_file response_body
  local available_node found

  [ -n "${group:-}" ] || die "策略组名称不能为空"
  [ -n "${node:-}" ] || die "节点名称不能为空"

  proxy_group_exists "$group" || die "策略组不存在：$group"
  proxy_group_supports_manual_pick "$group" || die "$(proxy_group_manual_pick_error_message "$group")"

  found=false
  while IFS= read -r available_node; do
    [ -n "${available_node:-}" ] || continue
    if [ "$available_node" = "$node" ]; then
      found=true
      break
    fi
  done < <(proxy_group_selectable_nodes "$group")

  if [ "$found" != "true" ]; then
    die "节点不存在于策略组中：$group -> $node"
  fi

  base="$(controller_api_base)"
  secret="$(controller_secret)"
  response_file="$(mktemp)"
  code="$(
    curl -sS -o "$response_file" -w "%{http_code}" -X PUT \
      -H "Content-Type: application/json" \
      ${secret:+-H "Authorization: Bearer $secret"} \
      --data "{\"name\":\"$node\"}" \
      "$base/proxies/$group"
  )"

  if [ "${code:-000}" -lt 200 ] || [ "${code:-000}" -ge 300 ]; then
    response_body="$(cat "$response_file" 2>/dev/null || true)"
    rm -f "$response_file" 2>/dev/null || true
    if [ -n "${response_body:-}" ]; then
      die "节点切换失败：$response_body"
    fi
    die "节点切换失败：controller 返回 HTTP $code"
  fi

  rm -f "$response_file" 2>/dev/null || true
}

proxy_group_count() {
  proxy_group_list 2>/dev/null | awk 'NF{c++} END{print c+0}'
}

default_proxy_group_name() {
  local config_file="${1:-$RUNTIME_DIR/config.yaml}"
  local group_name

  [ -s "$config_file" ] || return 1

  group_name="$("$(yq_bin)" eval '
    .["proxy-groups"][] |
    select(
      (.type == "select") or
      (.type == "url-test") or
      (.type == "fallback") or
      (.type == "load-balance")
    ) |
    .name
  ' "$config_file" 2>/dev/null | head -n 1)"

  [ -n "${group_name:-}" ] || return 1
  echo "$group_name"
}

default_proxy_group_current() {
  local group

  group="$(default_proxy_group_name 2>/dev/null || true)"
  [ -n "${group:-}" ] || return 1

  proxy_group_current "$group" 2>/dev/null || return 1
}

proxy_node_is_direct_like() {
  local node="$1"

  case "${node:-}" in
    DIRECT|REJECT|REJECT-DROP|PASS)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

proxy_group_first_relay_node() {
  local group="$1"
  local node

  [ -n "${group:-}" ] || return 1

  while IFS= read -r node; do
    [ -n "${node:-}" ] || continue
    if proxy_node_is_direct_like "$node"; then
      continue
    fi
    echo "$node"
    return 0
  done < <(proxy_group_selectable_nodes "$group")

  return 1
}

ensure_default_proxy_group_relay_selected() {
  local group current relay select_error

  local switched=""

  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue

    current="$(proxy_group_current "$group" 2>/dev/null || true)"
    [ -n "${current:-}" ] || continue

    if ! proxy_node_is_direct_like "$current"; then
      continue
    fi

    relay="$(proxy_group_first_relay_node "$group" 2>/dev/null || true)"
    [ -n "${relay:-}" ] || continue

    if [ "$relay" = "$current" ]; then
      continue
    fi

    if ! select_error="$(proxy_group_select "$group" "$relay" 2>&1 >/dev/null)"; then
      if [ -n "${select_error:-}" ]; then
        warn "策略组自动切换失败，已跳过：${group} ${current} -> ${relay}；${select_error}"
      else
        warn "策略组自动切换失败，已跳过：${group} ${current} -> ${relay}"
      fi
      continue
    fi

    if [ -n "${switched:-}" ]; then
      switched="${switched},${group}|${current}|${relay}"
    else
      switched="${group}|${current}|${relay}"
    fi
  done < <(proxy_group_manual_list)

  [ -n "${switched:-}" ] && echo "$switched"
}

print_proxy_groups_status() {
  local group current

  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    current="$(proxy_group_current "$group" 2>/dev/null || true)"

    if [ -n "${current:-}" ]; then
      echo "$group -> $current"
    else
      echo "$group -> <unknown>"
    fi
  done < <(proxy_group_list)
}

print_proxy_groups_summary() {
  local group current

  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    current="$(proxy_group_current "$group" 2>/dev/null || true)"

    if [ -n "${current:-}" ]; then
      echo "$group -> $current"
    else
      echo "$group"
    fi
  done < <(proxy_group_list)
}

proxy_node_test_delay() {
  local node="$1"
  local url="${2:-http://www.gstatic.com/generate_204}"
  local timeout_ms="${3:-3000}"
  local encoded_node

  [ -n "${node:-}" ] || return 1
  encoded_node="$(proxy_node_url_encode "$node")"

  controller_curl GET "/proxies/${encoded_node}/delay?timeout=${timeout_ms}&url=${url}" 2>/dev/null \
    | "$(yq_bin)" -p=json eval '.delay // 0' - 2>/dev/null \
    | head -n 1
}

proxy_group_nodes_delay_map() {
  local group="$1"

  [ -n "${group:-}" ] || return 1

  GROUP="$group" proxy_groups_json 2>/dev/null \
    | GROUP="$group" "$(yq_bin)" -p=json eval '
        . as $root |
        (.proxies | to_entries | .[] | select(.key == env(GROUP)) | .value.all // []) | .[] |
        . as $n |
        $n + "\t" + (
          ($root.proxies[$n].history | select(length > 0) | .[-1].delay // 0) // 0 |
          tostring
        )
      ' - 2>/dev/null
}

proxy_node_match_key() {
  local node="$1"

  printf '%s' "${node:-}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

proxy_node_matches_descriptive_prefix() {
  local node="$1"
  local keyword="$2"

  case "$node" in
    "$keyword"|"$keyword:"*|"$keyword："*|"$keyword"[[:space:]]*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

proxy_node_is_descriptive_entry() {
  local node="$1"
  local match_key
  local keyword

  match_key="$(proxy_node_match_key "$node")"

  case "$match_key" in
    ""|null|空值|"<unknown>")
      return 0
      ;;
  esac

  for keyword in \
    "剩余流量" \
    "流量" \
    "已用流量" \
    "总流量" \
    "套餐到期" \
    "到期时间" \
    "过期时间" \
    "官网" \
    "网址" \
    "url" \
    "expire" \
    "traffic" \
    "remaining" \
    "used" \
    "流量重置" \
    "通知"; do
    proxy_node_matches_descriptive_prefix "$match_key" "$keyword" && return 0
  done

  return 1
}

proxy_group_first_selectable_node() {
  local group="$1"
  local node

  [ -n "${group:-}" ] || return 1
  proxy_group_exists "$group" || return 1

  while IFS= read -r node; do
    [ -n "${node:-}" ] || continue
    echo "$node"
    return 0
  done < <(proxy_group_selectable_nodes "$group")

  return 1
}

proxy_group_current_display() {
  local group="$1"
  local current=""

  [ -n "${group:-}" ] || return 1
  proxy_group_exists "$group" || return 1

  current="$(proxy_group_current "$group" 2>/dev/null || true)"
  if [ -n "${current:-}" ] && proxy_node_is_selectable_candidate "$current"; then
    echo "$current"
    return 0
  fi

  proxy_group_first_selectable_node "$group"
}

proxy_group_display_list() {
  proxy_groups_json \
    | "$(yq_bin)" -p=json eval '
        .proxies | to_entries | .[] |
        select(.value.all != null) |
        select(
          (.value.type // "" | downcase | sub("[-_ ]+"; "")) as $t |
          ($t == "selector" or $t == "urltest" or $t == "fallback" or $t == "loadbalance")
        ) |
        .key
      ' - 2>/dev/null
}

proxy_node_url_encode() {
  local byte code char out=""

  while IFS= read -r byte; do
    [ -n "${byte:-}" ] || continue
    code=$((16#$byte))
    if { [ "$code" -ge 48 ] && [ "$code" -le 57 ]; } \
      || { [ "$code" -ge 65 ] && [ "$code" -le 90 ]; } \
      || { [ "$code" -ge 97 ] && [ "$code" -le 122 ]; } \
      || [ "$byte" = "2d" ] || [ "$byte" = "2e" ] || [ "$byte" = "5f" ] || [ "$byte" = "7e" ]; then
      printf -v char "\\x$byte"
      out+="$char"
    else
      out+="%${byte^^}"
    fi
  done < <(printf '%s' "$1" | od -An -tx1 -v | tr ' ' '\n')

  printf '%s' "$out"
}

proxy_json_string_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

proxy_group_select() {
  local group="$1"
  local node="$2"
  local base secret
  local code response_file response_body
  local available_node found
  local group_enc node_json

  [ -n "${group:-}" ] || die "策略组名称不能为空"
  [ -n "${node:-}" ] || die "节点名称不能为空"

  proxy_group_exists "$group" || die "策略组不存在：$group"
  proxy_group_can_show_candidates "$group" || die "$(proxy_group_manual_pick_error_message "$group")"
  proxy_node_is_selectable_candidate "$node" || die "节点不是可切换节点：$node"

  found=false
  while IFS= read -r available_node; do
    [ -n "${available_node:-}" ] || continue
    if [ "$available_node" = "$node" ]; then
      found=true
      break
    fi
  done < <(proxy_group_selectable_nodes "$group")

  if [ "$found" != "true" ]; then
    die "节点不存在于策略组中：$group -> $node"
  fi

  base="$(controller_api_base)"
  secret="$(controller_secret)"
  group_enc="$(proxy_node_url_encode "$group")"
  node_json="$(proxy_json_string_escape "$node")"
  response_file="$(mktemp)"
  code="$(
    curl -sS -o "$response_file" -w "%{http_code}" -X PUT \
      -H "Content-Type: application/json" \
      ${secret:+-H "Authorization: Bearer $secret"} \
      --data "{\"name\":\"$node_json\"}" \
      "$base/proxies/$group_enc"
  )"

  if [ "${code:-000}" -lt 200 ] || [ "${code:-000}" -ge 300 ]; then
    response_body="$(cat "$response_file" 2>/dev/null || true)"
    rm -f "$response_file" 2>/dev/null || true
    if [ -n "${response_body:-}" ]; then
      die "controller 原始错误：$response_body"
    fi
    die "节点切换失败：controller 返回 HTTP $code"
  fi

  rm -f "$response_file" 2>/dev/null || true
}

default_proxy_group_current() {
  local group

  group="$(default_proxy_group_name 2>/dev/null || true)"
  [ -n "${group:-}" ] || return 1

  proxy_group_current_display "$group" 2>/dev/null || return 1
}

print_proxy_groups_status() {
  local group current

  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"

    if [ -n "${current:-}" ]; then
      echo "$group -> $current"
    else
      echo "$group -> <unknown>"
    fi
  done < <(proxy_group_list)
}

print_proxy_groups_summary() {
  local group current

  while IFS= read -r group; do
    [ -n "${group:-}" ] || continue
    current="$(proxy_group_current_display "$group" 2>/dev/null || true)"

    if [ -n "${current:-}" ]; then
      echo "$group -> $current"
    else
      echo "$group"
    fi
  done < <(proxy_group_list)
}
