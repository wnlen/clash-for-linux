#!/usr/bin/env bash

: "${PROJECT_DIR:=}"
: "${INSTALL_SCOPE:=}"
: "${INSTALL_HOME:=}"
: "${RUNTIME_DIR:=}"
: "${BIN_DIR:=}"
: "${LOG_DIR:=}"
: "${CONFIG_DIR:=}"
: "${RESOURCE_DIR:=}"

DEFAULT_MIHOMO_VERSION="${MIHOMO_VERSION:-v1.19.23}"
DEFAULT_CLASH_VERSION="${CLASH_VERSION:-v1.18.0}"
DEFAULT_SUBCONVERTER_VERSION="${SUBCONVERTER_VERSION:-v0.9.9}"
DEFAULT_YQ_VERSION="${YQ_VERSION:-v4.52.4}"
DEFAULT_DASHBOARD_UI_URL="${DASHBOARD_UI_URL:-https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip}"

log()      { printf '%s\n' "$*"; }
info()     { printf 'ℹ %s\n' "$*"; }
success()  { printf '✔ %s\n' "$*"; }
warn()     { printf '⚠ %s\n' "$*" >&2; }
error()    { printf '✘ %s\n' "$*" >&2; }
die()      { error "$*"; exit 1; }

ui_color() {
    local color="$1"
    local msg="$2"

    if [[ ! "$color" =~ ^#[0-9a-fA-F]{6}$ ]]; then
        printf '%s\n' "$msg"
        return
    fi

    local hex="${color#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))

    local color_code="\033[38;2;${r};${g};${b}m"
    local reset_code="\033[0m"

    printf "%b%s%b\n" "$color_code" "$msg" "$reset_code"
}

die_usage() {
  local message="$1"
  local next_step="${2:-}"

  ui_error "$message"
  [ -n "${next_step:-}" ] && ui_next "$next_step" >&2
  exit 1
}

die_state() {
  local message="$1"
  local next_step="${2:-}"

  ui_error "$message"
  [ -n "${next_step:-}" ] && ui_next "$next_step" >&2
  exit 1
}

die_missing() {
  local thing="$1"
  local next_step="${2:-}"

  ui_error "${thing}不存在或不可用"
  [ -n "${next_step:-}" ] && ui_next "$next_step" >&2
  exit 1
}

ui_blank() {
  echo
}

ui_title() {
  local text="$1"
  echo
  echo "$text"
  echo
}

ui_section() {
  local text="$1"
  echo "【$text】"
}

ui_ok() {
  printf '🐱 %s\n' "$*"
}

ui_info() {
  printf 'ℹ️  %s\n' "$*"
}

ui_warn() {
  printf '🚨 %s\n' "$*"
}

ui_error() {
  printf '❗ %s\n' "$*" >&2
}

ui_next() {
  printf '👉 %s\n' "$*"
}

ui_download() {
  printf '⏳ %s\n' "$*"
}

ui_target() {
  ui_color "#fd79a8" "🎯 $*" >&2
}

ui_kv() {
  local icon="$1"
  local key="$2"
  local value="$3"
  printf '%s %s：%s\n' "$icon" "$key" "$value"
}

ui_progress_line() {
  local percent="$1"
  local message="$2"

  if [ -t 2 ]; then
    printf '\r\033[K⏳ [%3s%%] %s' "$percent" "$message" >&2
  else
    printf '⏳ [%3s%%] %s\n' "$percent" "$message" >&2
  fi
}

ui_progress_done() {
  local message="${1:-完成}"

  if [ -t 2 ]; then
    printf '\r\033[K✅ [100%%] %s\n' "$message" >&2
  else
    printf '✅ [100%%] %s\n' "$message" >&2
  fi
}

ui_progress_clear() {
  if [ -t 2 ]; then
    printf '\r\033[K' >&2
  fi
}

install_phase_begin() {
  local icon="$1"
  local text="$2"
  echo
  printf '%s %s\n' "$icon" "$text"
}

install_phase_done() {
  local text="$1"
  printf '✔ %s\n' "$text"
}

install_arch_text() {
  get_arch 2>/dev/null || echo "unknown"
}

install_state_text() {
  local has_subscription install_ready runtime_ready controller_ready build_status

  if install_has_subscription; then
    has_subscription="true"
  else
    has_subscription="false"
  fi

  install_ready="$(read_runtime_event_value "RUNTIME_LAST_INSTALL_READY" 2>/dev/null || true)"
  runtime_ready="$(install_verify_runtime_ready 2>/dev/null || true)"
  controller_ready="$(install_verify_controller_ready 2>/dev/null || true)"
  build_status="$(read_build_value "BUILD_LAST_STATUS" 2>/dev/null || true)"

  if [ "${has_subscription:-false}" != "true" ]; then
    echo "stopped"
    return 0
  fi

  if [ "${build_status:-}" = "failed" ]; then
    echo "broken"
    return 0
  fi

  if [ "${install_ready:-false}" = "true" ] \
    || { [ "${runtime_ready:-false}" = "true" ] && [ "${controller_ready:-false}" = "true" ]; }; then
    echo "ready"
    return 0
  fi

  echo "verifying"
}

install_build_result_text() {
  local command_ready config_ready build_status

  command_ready="$(install_verify_command_ready 2>/dev/null || true)"
  config_ready="$(install_verify_config_ready 2>/dev/null || true)"
  build_status="$(read_build_value "BUILD_LAST_STATUS" 2>/dev/null || true)"

  if [ "${build_status:-}" = "failed" ]; then
    echo "failed"
    return 0
  fi

  if [ "${command_ready:-false}" = "true" ] && { [ "${config_ready:-false}" = "true" ] || ! install_has_subscription; }; then
    echo "success"
  else
    echo "pending"
  fi
}

install_next_step_text() {
  case "$(install_state_text)" in
    ready)
      echo "clashctl select"
      ;;
    verifying)
      if install_has_subscription; then
        echo "clashon"
      else
        echo "clashctl add <订阅链接>"
      fi
      ;;
    broken)
      echo "clashctl doctor"
      ;;
    stopped)
      echo "clashctl add <订阅链接>"
      ;;
    *)
      echo "clashctl status"
      ;;
  esac
}

install_stage_title() {
  local text="$1"
  echo
  echo "==> $text"
}

install_stage_done() {
  local text="$1"
  echo "✔ $text"
}

install_stage_skip() {
  local text="$1"
  echo "↷ $text"
}

init_project_context() {
  PROJECT_DIR="$1"
  CONFIG_DIR="$PROJECT_DIR/config"
  RESOURCE_DIR="$PROJECT_DIR/resources"
}

is_wsl_env() {
  grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null
}

path_is_wsl_windows_mount() {
  local path="$1"

  path="$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")"

  case "$path" in
    /mnt/[a-zA-Z]|/mnt/[a-zA-Z]/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_project_not_wsl_windows_mount() {
  if is_wsl_env && path_is_wsl_windows_mount "$PROJECT_DIR"; then
    die_state \
      "当前项目目录位于 WSL Windows 挂载盘：$PROJECT_DIR" \
      "请将项目移动到 Linux 原生目录后重新安装，例如：cd ~ && git clone <repo> clash-for-linux && cd clash-for-linux && bash install.sh"
  fi
}

load_env_if_exists() {
  if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$PROJECT_DIR/.env"
    set +a
  fi

  normalize_env_compat
}

normalize_env_compat() {
  if [ -n "${KERNEL_NAME:-}" ]; then
    KERNEL_TYPE="$KERNEL_NAME"
  fi

  if [ -n "${CLASH_CONFIG_URL:-}" ]; then
    CLASH_SUBSCRIPTION_URL="$CLASH_CONFIG_URL"
  fi

  if [ -n "${VERSION_MIHOMO:-}" ]; then
    MIHOMO_VERSION="$VERSION_MIHOMO"
  fi

  if [ -n "${VERSION_YQ:-}" ]; then
    YQ_VERSION="$VERSION_YQ"
  fi

  if [ -n "${VERSION_SUBCONVERTER:-}" ]; then
    SUBCONVERTER_VERSION="$VERSION_SUBCONVERTER"
  fi

  if [ -n "${URL_CLASH_UI:-}" ]; then
    CLASH_PUBLIC_UI_URL="$URL_CLASH_UI"
  fi

  if [ -n "${URL_GH_PROXY:-}" ]; then
    CLASH_GH_PROXY="$URL_GH_PROXY"
  fi

  if [ -n "${CLASH_SUB_UA:-}" ]; then
    CLASH_SUBSCRIPTION_UA="$CLASH_SUB_UA"
  fi


  # 旧默认值迁移：公网默认监听
  if [ "${EXTERNAL_CONTROLLER:-}" = "127.0.0.1:9090" ]; then
    EXTERNAL_CONTROLLER="0.0.0.0:9090"
  fi
  # 已废弃：active-only 主链不再消费该字段
  unset BUILD_MIN_SUCCESS_SOURCES 2>/dev/null || true

  return 0
}

migrate_env_legacy_compat_fields() {
  local file="$1"
  local tmp

  [ -n "${file:-}" ] || return 0
  [ -f "$file" ] || return 0

  tmp="$(mktemp "${file}.tmp.XXXXXX")" || return 0

  awk '
    $0 ~ /^[[:space:]]*(export[[:space:]]+)?BUILD_MIN_SUCCESS_SOURCES=/ { next }
    $0 ~ /^[[:space:]]*(export[[:space:]]+)?CLASH_SUBSCRIPTION_FORMAT=/ { next }
    $0 ~ /^[[:space:]]*(export[[:space:]]+)?EXTERNAL_CONTROLLER="?127\.0\.0\.1:9090"?$/ {
      print "export EXTERNAL_CONTROLLER=\"0.0.0.0:9090\""
      next
    }
    { print }
  ' "$file" > "$tmp" || {
    rm -f "$tmp" 2>/dev/null || true
    return 0
  }

  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp" 2>/dev/null || true
    return 0
  fi

  if [ ! -w "$file" ]; then
    rm -f "$tmp" 2>/dev/null || true
    warn ".env 当前用户不可写，已跳过兼容迁移：$file"
    return 0
  fi

  mv -f "$tmp" "$file"
}

github_proxy_prefix() {
  local prefix="${CLASH_GH_PROXY:-}"
  prefix="${prefix%/}"
  echo "$prefix"
}

bundled_asset_enabled() {
  case "${CLASH_BUNDLED_ASSET_ENABLED:-true}" in
    true|1|yes|on) return 0 ;;
    false|0|no|off) return 1 ;;
    *) return 0 ;;
  esac
}

bundled_asset_root() {
  if [ -n "${CLASH_BUNDLED_ASSET_DIR:-}" ]; then
    echo "$CLASH_BUNDLED_ASSET_DIR"
    return 0
  fi

  [ -n "${RESOURCE_DIR:-}" ] || return 1
  echo "$RESOURCE_DIR/bin"
}

copy_bundled_asset() {
  local category="$1"
  local version="$2"
  local file="$3"
  local out="$4"
  local asset_name="${5:-$file}"
  local root candidate

  [ "$category" != "clash" ] || return 1
  bundled_asset_enabled || return 1

  root="$(bundled_asset_root 2>/dev/null || true)"
  [ -n "${root:-}" ] || return 1

  for candidate in \
    "$root/$category/$file" \
    "$root/$category/$version/$file" \
    "$root/$file" \
    "$RESOURCE_DIR/$category/$file"; do
    [ -s "$candidate" ] || continue

    mkdir -p "$(dirname "$out")"
    if [ "$candidate" != "$out" ]; then
      cp -f "$candidate" "$out"
    fi
    success "${asset_name} 已使用内置资源：$candidate"
    return 0
  done

  return 1
}

download_connect_timeout() {
  echo "${CLASH_DOWNLOAD_CONNECT_TIMEOUT:-8}"
}

download_probe_timeout() {
  echo "${CLASH_DOWNLOAD_PROBE_TIMEOUT:-4}"
}

download_max_time() {
  echo "${CLASH_DOWNLOAD_MAX_TIME:-1200}"
}

download_cache_enabled() {
  case "${CLASH_DOWNLOAD_CACHE_ENABLED:-true}" in
    true|1|yes|on) return 0 ;;
    false|0|no|off) return 1 ;;
    *) return 0 ;;
  esac
}

download_fail_cooldown() {
  echo "${CLASH_DOWNLOAD_FAIL_COOLDOWN:-1800}"
}

download_cache_dir() {
  echo "$RUNTIME_DIR/cache/assets"
}

download_mirror_state_file() {
  echo "$RUNTIME_DIR/cache/download-mirrors.env"
}

download_now_epoch() {
  date +%s
}

download_hash_key() {
  local text="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$text" | sha256sum | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$text" | shasum -a 256 | awk '{print $1}'
    return 0
  fi

  printf '%s' "$text" | cksum | awk '{print $1 "-" $2}'
}

download_cache_key() {
  local url="$1"
  download_hash_key "$url"
}

download_cache_file() {
  local url="$1"
  echo "$(download_cache_dir)/$(download_cache_key "$url").bin"
}

download_cache_meta_file() {
  local url="$1"
  echo "$(download_cache_dir)/$(download_cache_key "$url").meta"
}

download_cache_restore() {
  local url="$1"
  local out="$2"
  local cache_file

  download_cache_enabled || return 1

  cache_file="$(download_cache_file "$url")"
  [ -s "$cache_file" ] || return 1

  mkdir -p "$(dirname "$out")"
  cp -f "$cache_file" "$out"
  return 0
}

download_cache_store() {
  local url="$1"
  local src="$2"
  local source_url="${3:-}"
  local cache_file meta_file

  download_cache_enabled || return 0
  [ -s "$src" ] || return 0

  cache_file="$(download_cache_file "$url")"
  meta_file="$(download_cache_meta_file "$url")"

  mkdir -p "$(download_cache_dir)"
  cp -f "$src" "$cache_file"

  cat > "$meta_file" <<EOF
CACHE_URL="$url"
CACHE_SOURCE_URL="$source_url"
CACHE_TIME="$(now_datetime)"
EOF
}

github_url_is_mirrorable() {
  case "$1" in
    https://github.com/*|https://raw.githubusercontent.com/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

default_github_mirror_pool() {
  cat <<'EOF'
gh-proxy|https://gh-proxy.org|full
ghfast|https://ghfast.top|hostpath
ghproxy-net|https://ghproxy.net|hostpath
kkgithub|https://kkgithub.com|hostpath
EOF
}

custom_github_mirror_pool() {
  if [ -n "${CLASH_GH_PROXY_POOL:-}" ]; then
    printf '%s\n' "$CLASH_GH_PROXY_POOL"
  fi
}

normalize_github_mirror_entry() {
  local entry="$1"
  local label prefix mode

  [ -n "${entry//[[:space:]]/}" ] || return 1
  case "$entry" in
    \#*) return 1 ;;
  esac

  if printf '%s' "$entry" | grep -Fq '|'; then
    IFS='|' read -r label prefix mode <<EOF
$entry
EOF
    label="${label:-mirror}"
    prefix="${prefix:-}"
    mode="${mode:-full}"
    [ -n "${prefix:-}" ] || return 1
    printf '%s|%s|%s\n' "$label" "${prefix%/}" "$mode"
    return 0
  fi

  prefix="${entry%/}"
  [ -n "${prefix:-}" ] || return 1
  printf '%s|%s|full\n' "$prefix" "$prefix"
}

github_url_host() {
  local url="$1"
  local no_scheme

  no_scheme="${url#https://}"
  no_scheme="${no_scheme#http://}"
  echo "${no_scheme%%/*}"
}

github_url_path() {
  local url="$1"
  local no_scheme

  no_scheme="${url#https://}"
  no_scheme="${no_scheme#http://}"
  echo "${no_scheme#*/}"
}

build_github_mirror_url() {
  local entry="$1"
  local url="$2"
  local label prefix mode host path

  IFS='|' read -r label prefix mode <<EOF
$entry
EOF

  case "${mode:-full}" in
    full)
      echo "${prefix%/}/${url}"
      ;;
    hostpath)
      host="$(github_url_host "$url")"
      path="$(github_url_path "$url")"
      echo "${prefix%/}/${host}/${path}"
      ;;
    origin)
      echo "$url"
      ;;
    *)
      echo "${prefix%/}/${url}"
      ;;
  esac
}

github_mirror_candidate_entries() {
  local url="$1"
  local entry normalized
  local seen=""

  github_url_is_mirrorable "$url" || {
    echo "origin||origin"
    return 0
  }

  if [ -n "$(github_proxy_prefix)" ]; then
    entry="custom|$(github_proxy_prefix)|full"
    normalized="$(normalize_github_mirror_entry "$entry" 2>/dev/null || true)"
    if [ -n "${normalized:-}" ]; then
      printf '%s\n' "$normalized"
      seen="${seen}${normalized}"$'\n'
    fi
  fi

  if [ -n "${CLASH_GH_PROXY_POOL:-}" ]; then
    while IFS= read -r entry; do
      normalized="$(normalize_github_mirror_entry "$entry" 2>/dev/null || true)"
      [ -n "${normalized:-}" ] || continue
      if ! printf '%s' "$seen" | grep -Fxq "$normalized"; then
        printf '%s\n' "$normalized"
        seen="${seen}${normalized}"$'\n'
      fi
    done <<EOF
$(custom_github_mirror_pool)
EOF
  else
    while IFS= read -r entry; do
      normalized="$(normalize_github_mirror_entry "$entry" 2>/dev/null || true)"
      [ -n "${normalized:-}" ] || continue
      if ! printf '%s' "$seen" | grep -Fxq "$normalized"; then
        printf '%s\n' "$normalized"
        seen="${seen}${normalized}"$'\n'
      fi
    done <<EOF
$(default_github_mirror_pool)
EOF
  fi

  echo "origin||origin"
}

download_mirror_state_key() {
  local label="$1"
  printf '%s' "$label" | tr '[:lower:]-./:' '[:upper:]_____'
}

read_download_mirror_state() {
  local label="$1"
  local field="$2"
  local file key

  file="$(download_mirror_state_file)"
  [ -f "$file" ] || return 1

  key="DOWNLOAD_MIRROR_$(download_mirror_state_key "$label")_${field}"

  sed -nE "s/^[[:space:]]*${key}=['\"]?([^'\"]*)['\"]?$/\1/p" "$file" | head -n 1
}

write_download_mirror_state() {
  local label="$1"
  local field="$2"
  local value="$3"
  local file key

  file="$(download_mirror_state_file)"
  mkdir -p "$(dirname "$file")"
  touch "$file"

  key="DOWNLOAD_MIRROR_$(download_mirror_state_key "$label")_${field}"

  if grep -qE "^[[:space:]]*${key}=" "$file"; then
    awk -v k="$key" -v v="$value" '
      $0 ~ "^[[:space:]]*" k "=" {
        print k "=\"" v "\""
        next
      }
      { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

record_download_mirror_success() {
  local label="$1"
  local candidate_url="${2:-}"
  local now

  now="$(download_now_epoch)"

  write_download_mirror_state "$label" "LAST_SUCCESS_AT" "$now"
  write_download_mirror_state "$label" "LAST_SUCCESS_URL" "$candidate_url"
  write_download_mirror_state "$label" "FAIL_STREAK" "0"
}

record_download_mirror_failure() {
  local label="$1"
  local candidate_url="${2:-}"
  local now fail_streak

  now="$(download_now_epoch)"
  fail_streak="$(read_download_mirror_state "$label" "FAIL_STREAK" 2>/dev/null || echo "0")"

  case "$fail_streak" in
    ''|*[!0-9]*) fail_streak="0" ;;
  esac

  fail_streak=$((fail_streak + 1))

  write_download_mirror_state "$label" "LAST_FAILURE_AT" "$now"
  write_download_mirror_state "$label" "LAST_FAILURE_URL" "$candidate_url"
  write_download_mirror_state "$label" "FAIL_STREAK" "$fail_streak"
}

download_mirror_recent_failure_active() {
  local label="$1"
  local fail_at success_at now cooldown delta

  fail_at="$(read_download_mirror_state "$label" "LAST_FAILURE_AT" 2>/dev/null || true)"
  success_at="$(read_download_mirror_state "$label" "LAST_SUCCESS_AT" 2>/dev/null || true)"
  cooldown="$(download_fail_cooldown)"
  now="$(download_now_epoch)"

  case "$fail_at" in
    ''|*[!0-9]*) return 1 ;;
  esac

  case "$success_at" in
    ''|*[!0-9]*) success_at=0 ;;
  esac

  case "$cooldown" in
    ''|*[!0-9]*) cooldown=1800 ;;
  esac

  [ "$fail_at" -gt "$success_at" ] || return 1

  delta=$((now - fail_at))
  [ "$delta" -lt "$cooldown" ]
}

download_mirror_score() {
  local entry="$1"
  local label success_at fail_at fail_streak score now

  label="${entry%%|*}"
  now="$(download_now_epoch)"
  success_at="$(read_download_mirror_state "$label" "LAST_SUCCESS_AT" 2>/dev/null || echo "0")"
  fail_at="$(read_download_mirror_state "$label" "LAST_FAILURE_AT" 2>/dev/null || echo "0")"
  fail_streak="$(read_download_mirror_state "$label" "FAIL_STREAK" 2>/dev/null || echo "0")"
  score=0

  case "$success_at" in ''|*[!0-9]*) success_at=0 ;; esac
  case "$fail_at" in ''|*[!0-9]*) fail_at=0 ;; esac
  case "$fail_streak" in ''|*[!0-9]*) fail_streak=0 ;; esac

  if [ "$label" = "origin" ]; then
    score=$((score + 5))
  fi

  if [ "$success_at" -gt 0 ]; then
    score=$((score + 200))
    score=$((score - ((now - success_at) / 3600)))
  fi

  if [ "$fail_at" -gt "$success_at" ]; then
    score=$((score - 150))
  fi

  if [ "$fail_streak" -gt 0 ]; then
    score=$((score - fail_streak * 20))
  fi

  if download_mirror_recent_failure_active "$label"; then
    score=$((score - 1000))
  fi

  echo "$score"
}

github_mirror_candidate_entries_ordered() {
  local url="$1"
  local entry

  while IFS= read -r entry; do
    [ -n "${entry:-}" ] || continue
    printf '%s|%s\n' "$(download_mirror_score "$entry")" "$entry"
  done <<EOF
$(github_mirror_candidate_entries "$url")
EOF
}

curl_env_points_to_local_proxy() {
  local value

  for value in \
    "${http_proxy:-}" "${https_proxy:-}" \
    "${HTTP_PROXY:-}" "${HTTPS_PROXY:-}" \
    "${all_proxy:-}" "${ALL_PROXY:-}"; do
    [ -n "${value:-}" ] || continue

    case "$value" in
      http://127.0.0.1:*|https://127.0.0.1:*|socks5://127.0.0.1:*|socks5h://127.0.0.1:* \
      |http://localhost:*|https://localhost:*|socks5://localhost:*|socks5h://localhost:* \
      |http://[::1]:*|https://[::1]:*|socks5://[::1]:*|socks5h://[::1]:*)
        return 0
        ;;
    esac
  done

  return 1
}

curl_download() {
  if curl_env_points_to_local_proxy; then
    env \
      -u http_proxy \
      -u https_proxy \
      -u HTTP_PROXY \
      -u HTTPS_PROXY \
      -u all_proxy \
      -u ALL_PROXY \
      curl "$@"
    return $?
  fi

  curl "$@"
}

download_candidate_probe() {
  local url="$1"

  curl_download -fsSIL \
    --location \
    --connect-timeout "$(download_probe_timeout)" \
    --max-time "$(download_probe_timeout)" \
    "$url" >/dev/null 2>&1
}

download_candidate_fetch() {
  local url="$1"
  local out="$2"
  local progress_arg="--progress-bar"

  curl_download \
    "$progress_arg" \
    --show-error \
    --fail \
    --location \
    --connect-timeout "$(download_connect_timeout)" \
    --max-time "$(download_max_time)" \
    --retry 1 \
    --output "$out" \
    "$url"
}

download_file() {
  local url="$1"
  local out="$2"
  local asset_name="${3:-$(basename "$url")}"

  local ordered_entries entry candidate_url label attempt_mode
  local probed_any="false"
  local tried_urls=""
  local fetch_tmp

  mkdir -p "$(dirname "$out")"
  rm -f "$out" 2>/dev/null || true

  fetch_tmp="$(mktemp)"
  rm -f "$fetch_tmp" 2>/dev/null || true

  if ! github_url_is_mirrorable "$url"; then
    ui_download "正在下载：${asset_name}"

    if download_candidate_fetch "$url" "$fetch_tmp" "$asset_name"; then
      mv -f "$fetch_tmp" "$out"
      download_cache_store "$url" "$out" "$url"
      return 0
    fi

    rm -f "$fetch_tmp" 2>/dev/null || true
    die_state "下载失败：${asset_name}" \
              "请检查网络连通性，或在 .env 中配置下载源后重试；也可先执行 clashctl doctor"
  fi

  ordered_entries="$(
    github_mirror_candidate_entries_ordered "$url" \
      | sort -t'|' -k1,1nr \
      | cut -d'|' -f2-
  )"

  for attempt_mode in probe blind; do
    while IFS= read -r entry; do
      [ -n "${entry:-}" ] || continue

      candidate_url="$(build_github_mirror_url "$entry" "$url")"
      [ -n "${candidate_url:-}" ] || continue

      if printf '%s\n' "$tried_urls" | grep -Fxq "$candidate_url"; then
        continue
      fi

      label="${entry%%|*}"

      if [ "$attempt_mode" = "probe" ]; then
        if download_mirror_recent_failure_active "$label"; then
          continue
        fi

        if ! download_candidate_probe "$candidate_url"; then
          continue
        fi

        probed_any="true"
      else
        [ "$probed_any" = "false" ] || continue
      fi

      if [ "$label" = "origin" ]; then
        ui_download "正在下载：${asset_name}"
      else
        ui_download "正在下载：${asset_name} [${label}]"
      fi

      if download_candidate_fetch "$candidate_url" "$fetch_tmp" "$asset_name"; then
        mv -f "$fetch_tmp" "$out"
        download_cache_store "$url" "$out" "$candidate_url"
        record_download_mirror_success "$label" "$candidate_url"
        return 0
      fi

      record_download_mirror_failure "$label" "$candidate_url"
      rm -f "$fetch_tmp" 2>/dev/null || true
      fetch_tmp="$(mktemp)"
      rm -f "$fetch_tmp" 2>/dev/null || true
      tried_urls="${tried_urls}${candidate_url}"$'\n'
    done <<EOF
$ordered_entries
EOF
  done

  rm -f "$fetch_tmp" 2>/dev/null || true
  die_state "下载失败：${asset_name}" \
            "请检查网络连通性，或在 .env 中配置下载源后重试；也可先执行 clashctl doctor"
}

download_text_tmp_file() {
  mktemp
}

download_http_user_agent() {
  echo "${1:-curl/8}"
}

download_http_fetch_to_file() {
  local url="$1"
  local out="$2"
  local ua="${3:-}"
  local connect_timeout="${4:-10}"
  local max_time="${5:-300}"
  local progress_arg="--progress-bar"

  curl_download \
    "$progress_arg" \
    --show-error \
    --fail \
    --location \
    --retry 2 \
    --connect-timeout "$connect_timeout" \
    --max-time "$max_time" \
    ${ua:+-A "$ua"} \
    --output "$out" \
    "$url"
}

download_text_file() {
  local url="$1"
  local out="$2"
  local asset_name="${3:-$(basename "$url")}"
  local ua="${4:-}"
  local connect_timeout="${5:-10}"
  local max_time="${6:-300}"

  local fetch_tmp
  local cache_url

  mkdir -p "$(dirname "$out")"
  rm -f "$out" 2>/dev/null || true

  fetch_tmp="$(download_text_tmp_file)"
  rm -f "$fetch_tmp" 2>/dev/null || true

  if github_url_is_mirrorable "$url"; then
    if download_file "$url" "$fetch_tmp" "$asset_name"; then
      mv -f "$fetch_tmp" "$out"
      return 0
    fi
    rm -f "$fetch_tmp" 2>/dev/null || true
    die "下载失败：${asset_name}"
  fi

  ui_download "正在下载：${asset_name}"
  if download_http_fetch_to_file "$url" "$fetch_tmp" "$ua" "$connect_timeout" "$max_time" "$asset_name"; then
    mv -f "$fetch_tmp" "$out"
    download_cache_store "$url" "$out" "$url"
    return 0
  fi

  rm -f "$fetch_tmp" 2>/dev/null || true
  die "下载失败：${asset_name}"
}

subscription_user_agent() {
  echo "${CLASH_SUBSCRIPTION_UA:-clash-verge/v2.4.0}"
}

openwrt_root_dir() {
  echo "${CLASH_OPENWRT_ROOT:-/}"
}

openwrt_release_file() {
  local root
  root="$(openwrt_root_dir)"
  echo "${root%/}/etc/openwrt_release"
}

openwrt_os_release_file() {
  local root
  root="$(openwrt_root_dir)"
  echo "${root%/}/etc/os-release"
}

is_openwrt() {
  local os_release

  [ -f "$(openwrt_release_file)" ] && return 0

  os_release="$(openwrt_os_release_file)"
  [ -f "$os_release" ] || return 1
  grep -Eq '(^ID="?openwrt"?$|^ID_LIKE=.*openwrt)' "$os_release" 2>/dev/null
}

openwrt_dependency_hint() {
  echo "opkg update && opkg install bash curl tar gzip coreutils-readlink unzip"
}

openwrt_project_dir_is_persistent() {
  local resolved

  resolved="$(readlink -f "$PROJECT_DIR" 2>/dev/null || echo "$PROJECT_DIR")"
  case "$resolved" in
    /tmp|/tmp/*|/run|/run/*|/var/run|/var/run/*|/dev/shm|/dev/shm/*)
      return 1
      ;;
  esac

  return 0
}

ensure_openwrt_install_supported() {
  local arch missing="" command_name

  is_openwrt || return 0

  arch="$(get_arch 2>/dev/null || echo "unsupported")"
  case "$arch" in
    amd64|arm64)
      ;;
    *)
      die_state "OpenWrt 脚本模式暂只支持 x86_64/amd64 与 aarch64/arm64，当前架构：$arch" \
                "如需 MIPS/armv7，请先确认 mihomo/clash、yq 与 subconverter 都有可用二进制"
      ;;
  esac

  for command_name in bash curl tar gzip readlink unzip; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing="${missing}${missing:+ }$command_name"
    fi
  done

  if [ -n "${missing:-}" ]; then
    die_state "OpenWrt 缺少依赖命令：$missing" \
              "请先安装依赖：$(openwrt_dependency_hint)"
  fi

  if ! openwrt_project_dir_is_persistent; then
    die_state "OpenWrt 上当前项目目录位于易失路径：$PROJECT_DIR" \
              "请将项目放到持久化目录（例如 /root/clash-for-linux 或 /opt/clash-for-linux）后重新执行 bash install.sh"
  fi
}

guard_unsafe_sudo_auto_install() {
  local requested="${1:-}"

  if [ "$(id -u)" -eq 0 ] \
    && [ -n "${SUDO_USER:-}" ] \
    && { [ -z "${requested:-}" ] || [ "$requested" = "auto" ]; }; then
    die_state "检测到未受支持的安装方式：sudo bash install.sh" \
              "普通安装请执行：bash install.sh；系统级安装请显式执行：sudo bash install.sh system"
  fi
}

detect_install_scope() {
  local requested="${1:-auto}"

  case "$requested" in
    system)
      INSTALL_SCOPE="system"
      ;;
    user)
      INSTALL_SCOPE="user"
      ;;
    auto)
      if [ "$(id -u)" -eq 0 ]; then
        INSTALL_SCOPE="system"
      else
        INSTALL_SCOPE="user"
      fi
      ;;
    *)
      die "不支持的安装模式：$requested"
      ;;
  esac

  if [ "$INSTALL_SCOPE" = "system" ]; then
    INSTALL_HOME="${CLASH_INSTALL_HOME:-/opt/clash-for-linux}"
  else
    INSTALL_HOME="${CLASH_INSTALL_HOME:-$HOME/.local/share/clash-for-linux}"
  fi

  RUNTIME_DIR="$PROJECT_DIR/runtime"
  BIN_DIR="$RUNTIME_DIR/bin"
  LOG_DIR="$RUNTIME_DIR/logs"
}

init_layout() {
  mkdir -p \
    "$CONFIG_DIR" \
    "$RESOURCE_DIR" \
    "$RESOURCE_DIR/geo" \
    "$RESOURCE_DIR/bin" \
    "$RESOURCE_DIR/dashboard" \
    "$PROJECT_DIR/scripts/core" \
    "$PROJECT_DIR/scripts/init" \
    "$RUNTIME_DIR" \
    "$RUNTIME_DIR/dashboard" \
    "$BIN_DIR" \
    "$LOG_DIR"

  touch "$RUNTIME_DIR/.gitkeep"
}

ensure_required_commands() {
  command -v curl >/dev/null 2>&1 || die "当前系统缺少 curl"
  command -v tar >/dev/null 2>&1 || die "当前系统缺少 tar"
  command -v gzip >/dev/null 2>&1 || die "当前系统缺少 gzip"
  command -v readlink >/dev/null 2>&1 || die "当前系统缺少 readlink"
}

dashboard_archive_file() {
  echo "$RESOURCE_DIR/dashboard/dist.zip"
}

dashboard_dir_file() {
  echo "$RESOURCE_DIR/dashboard/dist"
}

runtime_dashboard_dir() {
  echo "$RUNTIME_DIR/dashboard"
}

runtime_dashboard_ready() {
  [ -f "$(runtime_dashboard_dir)/index.html" ]
}

dashboard_archive_valid() {
  local archive
  archive="$(dashboard_archive_file)"
  [ -f "$archive" ] || return 1
  unzip -tq "$archive" >/dev/null 2>&1
}

dashboard_dir_valid() {
  local dir
  dir="$(dashboard_dir_file)"
  [ -d "$dir" ] || return 1
  [ -f "$dir/index.html" ]
}

dashboard_asset_source() {
  local archive
  archive="$(dashboard_archive_file)"

  if dashboard_dir_valid; then
    echo "dir"
    return 0
  fi

  if [ -f "$archive" ]; then
    echo "zip"
    return 0
  fi

  echo "none"
}

ensure_dashboard_deploy_prerequisites() {
  local archive source_type
  archive="$(dashboard_archive_file)"
  source_type="$(dashboard_asset_source)"

  case "$source_type" in
    dir)
      return 0
      ;;
    zip)
      command -v unzip >/dev/null 2>&1 || die_state \
        "检测到 Dashboard 仅可从 dist.zip 部署，但系统缺少 unzip" \
        "请安装 unzip，或提供 resources/dashboard/dist/index.html（默认策略：本地 Dashboard 资产无效将阻断 install/update）"
      dashboard_archive_valid || die_state \
        "Dashboard 压缩包不可用：$archive" \
        "请修复 dist.zip，或提供 resources/dashboard/dist/index.html（默认策略：本地 Dashboard 资产无效将阻断 install/update）"
      return 0
      ;;
    *)
      die_state "本地 Dashboard 资产不可用（dist/ 与 dist.zip 均无效）" \
                "请提供 resources/dashboard/dist/index.html 或可解压的 resources/dashboard/dist.zip（默认策略：本地 Dashboard 资产无效将阻断 install/update）"
      ;;
  esac
}

shell_proxy_persist_state_file() {
  echo "$RUNTIME_DIR/shell-proxy.env"
}

shell_proxy_persist_enabled() {
  local file enabled
  file="$(shell_proxy_persist_state_file)"
  [ -f "$file" ] || return 1

  enabled="$(sed -nE 's/^SHELL_PROXY_PERSIST_ENABLED=\"?([^\"\r\n]+)\"?$/\1/p' "$file" | head -n 1)"
  [ "${enabled:-false}" = "true" ]
}

set_shell_proxy_persist_enabled() {
  local enabled="${1:-false}"
  local file
  file="$(shell_proxy_persist_state_file)"

  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
SHELL_PROXY_PERSIST_ENABLED="${enabled}"
SHELL_PROXY_PERSIST_TIME="$(now_datetime)"
EOF
}

clear_shell_proxy_persist_state() {
  rm -f "$(shell_proxy_persist_state_file)" 2>/dev/null || true
}

install_local_dashboard_assets() {
  local archive source_dir target source_type nested_dir
  archive="$(dashboard_archive_file)"
  source_dir="$(dashboard_dir_file)"
  target="$(runtime_dashboard_dir)"
  source_type="$(dashboard_asset_source)"

  rm -rf "$target" 2>/dev/null || true
  mkdir -p "$target"

  case "$source_type" in
    dir)
      cp -a "$source_dir"/. "$target"/ 2>/dev/null || {
        write_runtime_value "DASHBOARD_ASSET_SOURCE" "dir"
        write_runtime_value "DASHBOARD_DEPLOY_READY" "false"
        die "复制 Dashboard 目录失败：$source_dir"
      }
      ;;
    zip)
      unzip -oq "$archive" -d "$target" || {
        write_runtime_value "DASHBOARD_ASSET_SOURCE" "zip"
        write_runtime_value "DASHBOARD_DEPLOY_READY" "false"
        die "解压 Dashboard 失败：$archive"
      }
      ;;
    *)
      write_runtime_value "DASHBOARD_ASSET_SOURCE" "none"
      write_runtime_value "DASHBOARD_DEPLOY_READY" "false"
      die_state "本地 Dashboard 资产不可用（dist/ 与 dist.zip 均无效）" \
                "请提供 resources/dashboard/dist/index.html 或可解压的 resources/dashboard/dist.zip"
      ;;
  esac

  if [ ! -f "$target/index.html" ]; then
    for nested_dir in dist dashboard; do
      if [ -f "$target/$nested_dir/index.html" ]; then
        cp -a "$target/$nested_dir"/. "$target"/ 2>/dev/null || {
          write_runtime_value "DASHBOARD_ASSET_SOURCE" "$source_type"
          write_runtime_value "DASHBOARD_DEPLOY_READY" "false"
          die "Dashboard 扁平化失败：$target/$nested_dir"
        }
        rm -rf "$target/$nested_dir" 2>/dev/null || true
        break
      fi
    done
  fi

  if ! runtime_dashboard_ready; then
    write_runtime_value "DASHBOARD_ASSET_SOURCE" "$source_type"
    write_runtime_value "DASHBOARD_DEPLOY_READY" "false"
    die "Dashboard 部署不完整：缺少 $target/index.html"
  fi

  write_runtime_value "DASHBOARD_ASSET_SOURCE" "$source_type"
  write_runtime_value "DASHBOARD_DEPLOY_READY" "true"
}

get_os() {
  local os
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    linux) echo "linux" ;;
    *) die "暂不支持的操作系统：$os" ;;
  esac
}

get_arch() {
  local arch
  arch="${CLASH_TEST_UNAME_M:-$(uname -m)}"
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    *) die "暂不支持的架构：$arch" ;;
  esac
}

extract_tar_gz_strip1() {
  local archive="$1"
  local target_dir="$2"
  mkdir -p "$target_dir"
  tar -xzf "$archive" -C "$target_dir" --strip-components=1
}

write_env_value() {
  local key="$1"
  local value="$2"
  local file="$PROJECT_DIR/.env"

  touch "$file"

  if grep -qE "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file"; then
    awk -v k="$key" -v v="$value" '
      $0 ~ "^[[:space:]]*(export[[:space:]]+)?" k "=" {
        print "export " k "=\"" v "\""
        next
      }
      { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  else
    printf 'export %s="%s"\n' "$key" "$value" >> "$file"
  fi
}

read_env_value() {
  local key="$1"
  local file="$PROJECT_DIR/.env"
  [ -f "$file" ] || return 1
  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?${key}=['\"]?([^'\"]*)['\"]?$/\2/p" "$file" | head -n 1
}

unset_env_value() {
  local key="$1"
  local file="$PROJECT_DIR/.env"
  [ -f "$file" ] || return 0

  awk -v k="$key" '
    $0 ~ "^[[:space:]]*(export[[:space:]]+)?" k "=" { next }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

subscription_auto_update_enabled() {
  case "${CLASH_AUTO_UPDATE_SUBSCRIPTIONS:-true}" in
    true|1|yes|on)
      return 0
      ;;
    false|0|no|off)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

subscription_auto_update_text() {
  if subscription_auto_update_enabled; then
    echo "true"
  else
    echo "false"
  fi
}

subscription_update_guard_enabled() {
  if subscription_auto_update_enabled; then
    return 1
  fi
  return 0
}

require_subscription_fetch_allowed() {
  local fetch_reason="${1:-auto}"
  local url="${2:-}"

  if ! subscription_update_guard_enabled; then
    return 0
  fi

  case "$fetch_reason" in
    explicit-add|manual-add)
      return 0
      ;;
  esac

  if [ -n "${url:-}" ]; then
    die_state "已关闭自动更新订阅，当前操作不会擅自拉取远程订阅：$url" \
              "如需允许自动拉取，请在 .env 中设置：export CLASH_AUTO_UPDATE_SUBSCRIPTIONS=\"true\""
  else
    die_state "已关闭自动更新订阅，当前操作不会擅自拉取远程订阅" \
              "如需允许自动拉取，请在 .env 中设置：export CLASH_AUTO_UPDATE_SUBSCRIPTIONS=\"true\""
  fi
}

runtime_meta_file() {
  echo "$RUNTIME_DIR/install.env"
}

write_runtime_value() {
  local key="$1"
  local value="$2"
  local file
  file="$(runtime_meta_file)"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -qE "^[[:space:]]*${key}=" "$file"; then
    awk -v k="$key" -v v="$value" '
      $0 ~ "^[[:space:]]*" k "=" {
        print k "=\"" v "\""
        next
      }
      { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

read_runtime_value() {
  local key="$1"
  local file
  file="$(runtime_meta_file)"
  [ -f "$file" ] || return 1
  sed -nE "s/^[[:space:]]*${key}=['\"]?([^'\"]*)['\"]?$/\1/p" "$file" | head -n 1
}

install_env_os() { read_runtime_value "INSTALL_ENV_OS" 2>/dev/null || true; }
install_env_os_variant() { read_runtime_value "INSTALL_ENV_OS_VARIANT" 2>/dev/null || true; }
install_env_arch() { read_runtime_value "INSTALL_ENV_ARCH" 2>/dev/null || true; }
install_env_scope() { read_runtime_value "INSTALL_ENV_SCOPE" 2>/dev/null || true; }
install_env_is_root() { read_runtime_value "INSTALL_ENV_IS_ROOT" 2>/dev/null || true; }
install_env_container() { read_runtime_value "INSTALL_ENV_CONTAINER" 2>/dev/null || true; }
install_env_systemd() { read_runtime_value "INSTALL_ENV_SYSTEMD" 2>/dev/null || true; }
install_env_systemd_user() { read_runtime_value "INSTALL_ENV_SYSTEMD_USER" 2>/dev/null || true; }
install_env_tun_safe() { read_runtime_value "INSTALL_ENV_TUN_SAFE" 2>/dev/null || true; }

install_plan_backend() { read_runtime_value "INSTALL_PLAN_BACKEND" 2>/dev/null || true; }
install_plan_tun_default() { read_runtime_value "INSTALL_PLAN_TUN_DEFAULT" 2>/dev/null || true; }
install_plan_container_mode() { read_runtime_value "INSTALL_PLAN_CONTAINER_MODE" 2>/dev/null || true; }
install_plan_port_policy() { read_runtime_value "INSTALL_PLAN_PORT_POLICY" 2>/dev/null || true; }

install_plan_mixed_port() { read_runtime_value "INSTALL_PLAN_MIXED_PORT" 2>/dev/null || true; }
install_plan_controller() { read_runtime_value "INSTALL_PLAN_CONTROLLER" 2>/dev/null || true; }
install_plan_dns_port() { read_runtime_value "INSTALL_PLAN_DNS_PORT" 2>/dev/null || true; }

install_plan_mixed_port_auto_changed() { read_runtime_value "INSTALL_PLAN_MIXED_PORT_AUTO_CHANGED" 2>/dev/null || true; }
install_plan_controller_auto_changed() { read_runtime_value "INSTALL_PLAN_CONTROLLER_AUTO_CHANGED" 2>/dev/null || true; }
install_plan_dns_port_auto_changed() { read_runtime_value "INSTALL_PLAN_DNS_PORT_AUTO_CHANGED" 2>/dev/null || true; }

install_verify_command_ready() { read_runtime_value "INSTALL_VERIFY_COMMAND_READY" 2>/dev/null || true; }
install_verify_config_ready() { read_runtime_value "INSTALL_VERIFY_CONFIG_READY" 2>/dev/null || true; }
install_verify_runtime_ready() { read_runtime_value "INSTALL_VERIFY_RUNTIME_READY" 2>/dev/null || true; }
install_verify_controller_ready() { read_runtime_value "INSTALL_VERIFY_CONTROLLER_READY" 2>/dev/null || true; }

build_meta_file() {
  echo "$RUNTIME_DIR/build.env"
}

subscription_health_file() {
  echo "$RUNTIME_DIR/sub-health.env"
}

runtime_event_file() {
  echo "$RUNTIME_DIR/runtime-events.env"
}

tun_state_file() {
  echo "$RUNTIME_DIR/tun.env"
}

write_tun_value() {
  local key="$1"
  local value="$2"
  local file

  file="$(tun_state_file)"
  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -qE "^[[:space:]]*${key}=" "$file"; then
    awk -v k="$key" -v v="$value" '
      $0 ~ "^[[:space:]]*" k "=" {
        print k "=\"" v "\""
        next
      }
      { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

read_tun_value() {
  local key="$1"
  local file

  file="$(tun_state_file)"
  [ -f "$file" ] || return 1

  sed -nE "s/^[[:space:]]*${key}=['\"]?([^'\"]*)['\"]?$/\1/p" "$file" | head -n 1
}

write_runtime_event_value() {
  local key="$1"
  local value="$2"
  local file

  file="$(runtime_event_file)"
  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -qE "^[[:space:]]*${key}=" "$file"; then
    awk -v k="$key" -v v="$value" '
      $0 ~ "^[[:space:]]*" k "=" {
        print k "=\"" v "\""
        next
      }
      { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

read_runtime_event_value() {
  local key="$1"
  local file

  file="$(runtime_event_file)"
  [ -f "$file" ] || return 1

  sed -nE "s/^[[:space:]]*${key}=['\"]?([^'\"]*)['\"]?$/\1/p" "$file" | head -n 1
}

clear_runtime_build_result_event() {
  write_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED" ""
  write_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED_TIME" ""
  write_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED_REASON" ""
}

mark_runtime_build_applied() {
  local reason="${1:-success}"
  write_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED" "true"
  write_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED_TIME" "$(now_datetime)"
  write_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED_REASON" "$reason"
}

mark_runtime_build_not_applied() {
  local reason="$1"
  write_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED" "false"
  write_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED_TIME" "$(now_datetime)"
  write_runtime_event_value "RUNTIME_LAST_BUILD_APPLIED_REASON" "$reason"
}

mark_runtime_config_source() {
  local source="$1"
  write_runtime_event_value "RUNTIME_LAST_CONFIG_SOURCE" "$source"
  write_runtime_event_value "RUNTIME_LAST_CONFIG_SOURCE_TIME" "$(now_datetime)"
}

clear_runtime_event_file() {
  rm -f "$(runtime_event_file)" 2>/dev/null || true
}

write_build_value() {
  local key="$1"
  local value="$2"
  local file
  file="$(build_meta_file)"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -qE "^[[:space:]]*${key}=" "$file"; then
    awk -v k="$key" -v v="$value" '
      $0 ~ "^[[:space:]]*" k "=" {
        print k "=\"" v "\""
        next
      }
      { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
}

read_build_value() {
  local key="$1"
  local file
  file="$(build_meta_file)"
  [ -f "$file" ] || return 1
  sed -nE "s/^[[:space:]]*${key}=['\"]?([^'\"]*)['\"]?$/\1/p" "$file" | head -n 1
}

clear_build_meta() {
  rm -f "$(build_meta_file)" 2>/dev/null || true
}

clear_build_error_meta() {
  write_build_value "BUILD_LAST_ERROR_SUMMARY" ""
  write_build_value "BUILD_LAST_ERROR_DETAIL" ""
  write_build_value "BUILD_LAST_ERROR_STAGE" ""
}

now_datetime() {
  date '+%Y-%m-%d %H:%M:%S'
}

is_port_in_use() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
    return $?
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
    return $?
  fi

  return 1
}

resolve_free_port() {
  local start="${1:-7890}"
  local end="${2:-7999}"
  local p
  for p in $(seq "$start" "$end"); do
    if ! is_port_in_use "$p"; then
      echo "$p"
      return 0
    fi
  done
  die "指定端口范围内没有可用端口：${start}-${end}"
}

runtime_config_file() {
  echo "$RUNTIME_DIR/config.yaml"
}

runtime_config_mixed_port() {
  local file
  local port
  file="$(runtime_config_file)"
  [ -s "$file" ] || return 1

  port="$("$(yq_bin)" eval '.["mixed-port"] // .port // ""' "$file" 2>/dev/null | head -n 1)"
  runtime_port_value_is_valid "$port" || return 1
  echo "$port"
}

runtime_config_controller_addr() {
  local file
  file="$(runtime_config_file)"
  [ -s "$file" ] || return 1

  "$(yq_bin)" eval '.["external-controller"] // ""' "$file" 2>/dev/null | head -n 1
}

runtime_config_controller_port() {
  local addr
  local port
  addr="$(runtime_config_controller_addr 2>/dev/null || true)"
  [ -n "${addr:-}" ] || return 1
  [ "$addr" != "null" ] || return 1

  port="${addr##*:}"
  runtime_port_value_is_valid "$port" || return 1
  echo "$port"
}

runtime_config_allow_lan() {
  local file
  local value
  file="$(runtime_config_file)"
  [ -s "$file" ] || return 1

  value="$("$(yq_bin)" eval '.["allow-lan"] // true' "$file" 2>/dev/null | head -n 1)"
  case "$value" in
    false) echo "false" ;;
    *) echo "true" ;;
  esac
}

runtime_port_value_is_valid() {
  local port="${1:-}"

  printf '%s' "$port" | grep -Eq '^[0-9]+$' || return 1
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

runtime_controller_value_is_valid() {
  local controller="${1:-}"
  local port

  [ -n "${controller:-}" ] || return 1
  [ "$controller" != "null" ] || return 1
  printf '%s' "$controller" | grep -Eq '^[^[:space:][:cntrl:]]+:[0-9]+$' || return 1

  port="${controller##*:}"
  runtime_port_value_is_valid "$port"
}

display_controller_local_addr() {
  local controller="$1"
  local host port

  [ -n "${controller:-}" ] || return 1
  [ "$controller" != "null" ] || return 1
  printf '%s' "$controller" | grep -q ':' || return 1

  host="${controller%:*}"
  port="${controller##*:}"
  printf '%s' "$host" | grep -Eq '^[^[:space:][:cntrl:]]+$' || return 1
  runtime_port_value_is_valid "$port" || return 1

  if [ "$host" = "0.0.0.0" ]; then
    host="127.0.0.1"
  fi

  echo "${host}:${port}"
}

runtime_config_dns_listen() {
  local file
  file="$(runtime_config_file)"
  [ -s "$file" ] || return 1

  "$(yq_bin)" eval '.dns.listen // ""' "$file" 2>/dev/null | head -n 1
}

runtime_config_dns_port() {
  local listen
  local port
  listen="$(runtime_config_dns_listen 2>/dev/null || true)"
  [ -n "${listen:-}" ] || return 1
  [ "$listen" != "null" ] || return 1

  port="${listen##*:}"
  runtime_port_value_is_valid "$port" || return 1
  echo "$port"
}

mark_runtime_port_repair_result() {
  local repaired="$1"
  local detail="${2:-}"

  write_runtime_event_value "RUNTIME_LAST_PORT_REPAIR" "$repaired"
  write_runtime_event_value "RUNTIME_LAST_PORT_REPAIR_TIME" "$(now_datetime)"
  write_runtime_event_value "RUNTIME_LAST_PORT_REPAIR_DETAIL" "$detail"
}

runtime_config_tun_enabled() {
  local file
  file="$(runtime_config_file)"
  [ -s "$file" ] || return 1

  "$(yq_bin)" eval '.tun.enable // false' "$file" 2>/dev/null | head -n 1
}

runtime_config_tun_stack() {
  local file
  file="$(runtime_config_file)"
  [ -s "$file" ] || return 1

  "$(yq_bin)" eval '.tun.stack // ""' "$file" 2>/dev/null | head -n 1
}

runtime_config_tun_auto_route() {
  local file
  file="$(runtime_config_file)"
  [ -s "$file" ] || return 1

  "$(yq_bin)" eval '.tun."auto-route" // false' "$file" 2>/dev/null | head -n 1
}

runtime_config_tun_auto_redirect() {
  local file
  file="$(runtime_config_file)"
  [ -s "$file" ] || return 1

  "$(yq_bin)" eval '.tun."auto-redirect" // false' "$file" 2>/dev/null | head -n 1
}

runtime_config_tun_auto_detect_interface() {
  local file
  file="$(runtime_config_file)"
  [ -s "$file" ] || return 1

  "$(yq_bin)" eval '.tun."auto-detect-interface" // false' "$file" 2>/dev/null | head -n 1
}

default_route_dev() {
  has_ip_command || return 1
  ip route show default 2>/dev/null | awk '/^default/ {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}'
}

default_route_is_tun_like() {
  local dev
  dev="$(default_route_dev 2>/dev/null || true)"
  [ -n "${dev:-}" ] || return 1

  case "$dev" in
    utun*|tun*|clash*|mihomo*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mark_tun_last_verification() {
  local result="$1"
  local reason="${2:-}"
  local now

  now="$(now_datetime)"
  write_tun_value "TUN_LAST_VERIFY_RESULT" "$result"
  write_tun_value "TUN_LAST_VERIFY_REASON" "$reason"
  write_tun_value "TUN_LAST_VERIFY_TIME" "$now"
}

mark_tun_last_action() {
  local action="$1"
  local result="$2"
  local reason="${3:-}"
  local now

  now="$(now_datetime)"
  write_tun_value "TUN_LAST_ACTION" "$action"
  write_tun_value "TUN_LAST_ACTION_RESULT" "$result"
  write_tun_value "TUN_LAST_ACTION_REASON" "$reason"
  write_tun_value "TUN_LAST_ACTION_TIME" "$now"
}

read_tun_last_verify_result() {
  read_tun_value "TUN_LAST_VERIFY_RESULT" 2>/dev/null || true
}

read_tun_last_verify_reason() {
  read_tun_value "TUN_LAST_VERIFY_REASON" 2>/dev/null || true
}

read_tun_last_verify_time() {
  read_tun_value "TUN_LAST_VERIFY_TIME" 2>/dev/null || true
}

read_tun_last_action() {
  read_tun_value "TUN_LAST_ACTION" 2>/dev/null || true
}

read_tun_last_action_result() {
  read_tun_value "TUN_LAST_ACTION_RESULT" 2>/dev/null || true
}

read_tun_last_action_reason() {
  read_tun_value "TUN_LAST_ACTION_REASON" 2>/dev/null || true
}

read_tun_last_action_time() {
  read_tun_value "TUN_LAST_ACTION_TIME" 2>/dev/null || true
}

systemd_available() {
  is_openwrt && return 1
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

systemd_user_available() {
  is_openwrt && return 1
  command -v systemctl >/dev/null 2>&1 || return 1
  # Require a real user D-Bus socket; avoids false-positives in containers
  # where systemctl exists but D-Bus is absent (XDG_RUNTIME_DIR unset or no bus socket).
  [ -n "${XDG_RUNTIME_DIR:-}" ] || return 1
  [ -S "${XDG_RUNTIME_DIR}/bus" ] || return 1
  systemctl --user daemon-reload >/dev/null 2>&1
}

is_root_user() {
  [ "$(id -u)" -eq 0 ]
}

tun_device_exists() {
  [ -c /dev/net/tun ]
}

tun_device_readable() {
  [ -r /dev/net/tun ] && [ -w /dev/net/tun ]
}

container_env_type() {
  # Docker: marker file present
  if [ -f "/.dockerenv" ]; then
    echo "docker"
    return 0
  fi

  # cgroups v1: cgroup path contains runtime keywords
  if grep -qaE '(docker|containerd|kubepods|lxc)' /proc/1/cgroup 2>/dev/null; then
    echo "container"
    return 0
  fi

  # cgroups v2 + containerd/K8s: /proc/1/cgroup is just "0::/"
  # Fall back to namespace / filesystem checks
  if [ -f /proc/1/cgroup ] && grep -q '^0::/' /proc/1/cgroup 2>/dev/null; then
    # Running as a non-init process tree (PID 1 is not systemd/sysvinit)
    local _init_comm
    _init_comm="$(cat /proc/1/comm 2>/dev/null || true)"
    case "${_init_comm:-}" in
      systemd|sysvinit|init|launchd|openrc-init)
        : ;; # real host init, continue to other checks
      *)
        # Non-standard PID 1 is a strong container signal
        echo "container"
        return 0
        ;;
    esac
  fi

  # Overlay root filesystem is typical of container environments
  if awk '$5 == "/" { print $1 }' /proc/mounts 2>/dev/null | grep -q 'overlay'; then
    echo "container"
    return 0
  fi

  # No D-Bus session and no /run/systemd/private is another container signal,
  # but this overlaps with systemd checks elsewhere; skip here to avoid false-positives.

  echo "host"
}

has_cap_net_admin() {
  if ! command -v capsh >/dev/null 2>&1; then
    return 2
  fi

  capsh --print 2>/dev/null | grep -Eq 'Current:.*cap_net_admin'
}

has_ip_command() {
  command -v ip >/dev/null 2>&1
}

kernel_binary_has_cap_net_admin() {
  local _bin
  _bin="$(runtime_kernel_bin 2>/dev/null || true)"
  [ -n "${_bin:-}" ] && [ -x "${_bin}" ] || return 1
  command -v getcap >/dev/null 2>&1 || return 1
  getcap "$_bin" 2>/dev/null | grep -q 'cap_net_admin'
}

can_manage_tun_safely() {
  if ! tun_device_exists; then
    return 1
  fi

  if is_root_user; then
    return 0
  fi

  # Current shell has CAP_NET_ADMIN
  if has_cap_net_admin; then
    return 0
  fi

  # Kernel binary has file capability cap_net_admin (setcap)
  if kernel_binary_has_cap_net_admin; then
    return 0
  fi

  return 1
}

# Guard: refuse to run a tun action as root via sudo when the installation
# was done in user scope. Writing runtime files as root corrupts their
# ownership and breaks subsequent systemctl --user operations.
guard_sudo_on_user_install() {
  local _action="${1:-on}"
  is_root_user || return 0
  [ -n "${SUDO_USER:-}" ] || return 0

  local _stored_scope
  _stored_scope="$(install_env_scope 2>/dev/null || true)"
  [ "${_stored_scope:-}" = "user" ] || return 0

  echo
  echo "❗ 操作被拒绝：user 安装模式不支持以 sudo 运行"
  echo "🚨 原因：sudo 会将 runtime 文件写成 root:root，导致 systemctl --user 无法访问"
  echo "👤 请以安装用户（${SUDO_USER}）直接执行："
  echo "   clashctl tun ${_action}"
  echo
  return 1
}

tun_container_mode() {
  local env_type
  env_type="$(container_env_type 2>/dev/null || echo unknown)"

  if [ "$env_type" = "host" ]; then
    echo "host"
    return 0
  fi

  if ! tun_device_exists 2>/dev/null; then
    echo "container-risky"
    return 0
  fi

  if ! tun_device_readable 2>/dev/null; then
    echo "container-risky"
    return 0
  fi

  case "$(has_cap_net_admin; echo $?)" in
    0)
      ;;
    *)
      echo "container-risky"
      return 0
      ;;
  esac

  if ! has_ip_command 2>/dev/null; then
    echo "container-risky"
    return 0
  fi

  echo "container-safe"
}

tun_container_mode_text() {
  case "$(tun_container_mode 2>/dev/null || echo unknown)" in
    host)
      echo "主机环境"
      ;;
    container-safe)
      echo "容器环境（可保守开启）"
      ;;
    container-risky)
      echo "容器环境（高风险，建议阻断）"
      ;;
    *)
      echo "未知"
      ;;
  esac
}

tun_container_risk_reason() {
  local env_type
  env_type="$(container_env_type 2>/dev/null || echo unknown)"

  if [ "$env_type" = "host" ]; then
    echo ""
    return 0
  fi

  if ! tun_device_exists 2>/dev/null; then
    echo "/dev/net/tun 不存在"
    return 0
  fi

  if ! tun_device_readable 2>/dev/null; then
    echo "/dev/net/tun 不可读写"
    return 0
  fi

  case "$(has_cap_net_admin; echo $?)" in
    0)
      ;;
    2)
      echo "无法确认 CAP_NET_ADMIN（缺少 capsh）"
      return 0
      ;;
    *)
      echo "缺少 CAP_NET_ADMIN"
      return 0
      ;;
  esac

  if ! has_ip_command 2>/dev/null; then
    echo "缺少 ip 命令"
    return 0
  fi

  echo ""
}

collect_install_environment() {
  local os os_variant arch is_root container_type has_systemd has_systemd_user tun_safe

  os="$(get_os 2>/dev/null || echo "unknown")"
  if is_openwrt; then
    os_variant="openwrt"
  else
    os_variant="generic"
  fi
  arch="$(get_arch 2>/dev/null || echo "unknown")"

  if is_root_user; then
    is_root="true"
  else
    is_root="false"
  fi

  container_type="$(container_env_type 2>/dev/null || echo "unknown")"

  if systemd_available; then
    has_systemd="true"
  else
    has_systemd="false"
  fi

  if systemd_user_available; then
    has_systemd_user="true"
  else
    has_systemd_user="false"
  fi

  if can_manage_tun_safely; then
    tun_safe="true"
  else
    tun_safe="false"
  fi

  cat <<EOF
INSTALL_ENV_OS=$os
INSTALL_ENV_OS_VARIANT=$os_variant
INSTALL_ENV_ARCH=$arch
INSTALL_ENV_SCOPE=$INSTALL_SCOPE
INSTALL_ENV_IS_ROOT=$is_root
INSTALL_ENV_CONTAINER=$container_type
INSTALL_ENV_SYSTEMD=$has_systemd
INSTALL_ENV_SYSTEMD_USER=$has_systemd_user
INSTALL_ENV_TUN_SAFE=$tun_safe
EOF
}

print_install_environment_exports() {
  collect_install_environment
}

mark_install_environment() {
  eval "$(collect_install_environment)"

  write_runtime_value "INSTALL_ENV_OS" "$INSTALL_ENV_OS"
  write_runtime_value "INSTALL_ENV_OS_VARIANT" "$INSTALL_ENV_OS_VARIANT"
  write_runtime_value "INSTALL_ENV_ARCH" "$INSTALL_ENV_ARCH"
  write_runtime_value "INSTALL_ENV_SCOPE" "$INSTALL_ENV_SCOPE"
  write_runtime_value "INSTALL_ENV_IS_ROOT" "$INSTALL_ENV_IS_ROOT"
  write_runtime_value "INSTALL_ENV_CONTAINER" "$INSTALL_ENV_CONTAINER"
  write_runtime_value "INSTALL_ENV_SYSTEMD" "$INSTALL_ENV_SYSTEMD"
  write_runtime_value "INSTALL_ENV_SYSTEMD_USER" "$INSTALL_ENV_SYSTEMD_USER"
  write_runtime_value "INSTALL_ENV_TUN_SAFE" "$INSTALL_ENV_TUN_SAFE"
}

decide_install_backend() {
  if is_openwrt; then
    echo "script"
    return 0
  fi

  if [ "$INSTALL_SCOPE" = "system" ] && systemd_available; then
    echo "systemd"
    return 0
  fi

  if [ "$INSTALL_SCOPE" = "user" ] && systemd_user_available; then
    echo "systemd-user"
    return 0
  fi

  echo "script"
}

decide_install_tun_default() {
  echo "false"
}

collect_install_plan() {
  local backend tun_default container_mode port_policy

  backend="$(decide_install_backend)"
  tun_default="$(decide_install_tun_default)"

  case "$(container_env_type 2>/dev/null || echo "unknown")" in
    host)
      container_mode="false"
      ;;
    *)
      container_mode="true"
      ;;
  esac

  port_policy="auto-resolve"

  cat <<EOF
INSTALL_PLAN_BACKEND=$backend
INSTALL_PLAN_TUN_DEFAULT=$tun_default
INSTALL_PLAN_CONTAINER_MODE=$container_mode
INSTALL_PLAN_PORT_POLICY=$port_policy
EOF
}

print_install_plan_exports() {
  collect_install_plan
}

mark_install_plan() {
  eval "$(collect_install_plan)"

  write_runtime_value "INSTALL_PLAN_BACKEND" "$INSTALL_PLAN_BACKEND"
  write_runtime_value "INSTALL_PLAN_TUN_DEFAULT" "$INSTALL_PLAN_TUN_DEFAULT"
  write_runtime_value "INSTALL_PLAN_CONTAINER_MODE" "$INSTALL_PLAN_CONTAINER_MODE"
  write_runtime_value "INSTALL_PLAN_PORT_POLICY" "$INSTALL_PLAN_PORT_POLICY"
}

yq_bin() {
  echo "$BIN_DIR/yq"
}

mihomo_bin() {
  echo "$BIN_DIR/mihomo"
}

clash_bin() {
  echo "$BIN_DIR/clash"
}

normalize_kernel_type() {
  case "${1:-mihomo}" in
    mihomo|clash)
      echo "${1:-mihomo}"
      ;;
    "")
      echo "mihomo"
      ;;
    *)
      die "不支持的内核类型：$1（只允许 mihomo / clash）"
      ;;
  esac
}

runtime_kernel_type() {
  local value

  value="${KERNEL_TYPE:-}"
  if [ -z "${value:-}" ]; then
    value="$(read_runtime_value "KERNEL_TYPE" 2>/dev/null || true)"
  fi
  if [ -z "${value:-}" ]; then
    value="mihomo"
  fi

  normalize_kernel_type "$value"
}

tun_kernel_support_level() {
  case "$(runtime_kernel_type 2>/dev/null || echo mihomo)" in
    mihomo)
      echo "full"
      ;;
    clash)
      echo "limited"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

tun_kernel_support_text() {
  case "$(tun_kernel_support_level 2>/dev/null || echo unknown)" in
    full)
      echo "主支持"
      ;;
    limited)
      echo "降级支持"
      ;;
    *)
      echo "未知"
      ;;
  esac
}

tun_kernel_support_reason() {
  case "$(runtime_kernel_type 2>/dev/null || echo mihomo)" in
    mihomo)
      echo "当前内核为 mihomo，Tun 作为主支持能力处理"
      ;;
    clash)
      echo "当前内核为 clash，Tun 仅按降级支持处理，稳定性可能弱于 mihomo"
      ;;
    *)
      echo "当前内核类型未知，无法确认 Tun 支持等级"
      ;;
  esac
}

tun_kernel_is_recommended() {
  [ "$(runtime_kernel_type 2>/dev/null || echo mihomo)" = "mihomo" ]
}

write_runtime_kernel_type() {
  local kernel
  kernel="$(normalize_kernel_type "$1")"

  write_env_value "KERNEL_TYPE" "$kernel"
  write_runtime_value "KERNEL_TYPE" "$kernel"
  write_runtime_value "KERNEL_TYPE_INSTALLED" "$kernel"
}

runtime_kernel_bin() {
  case "$(runtime_kernel_type)" in
    mihomo) mihomo_bin ;;
    clash) clash_bin ;;
    *) die "未知内核类型：$(runtime_kernel_type)" ;;
  esac
}

runtime_kernel_name() {
  case "$(runtime_kernel_type)" in
    mihomo) echo "mihomo" ;;
    clash) echo "clash" ;;
    *) echo "unknown" ;;
  esac
}

subconverter_home() {
  echo "$RUNTIME_DIR/subconverter"
}

subconverter_bin() {
  echo "$(subconverter_home)/subconverter"
}

clashctl_source() {
  echo "$PROJECT_DIR/scripts/core/clashctl.sh"
}

service_unit_name() {
  echo "clash-for-linux.service"
}

runtime_backend() {
  local backend

  if is_openwrt; then
    echo "script"
    return 0
  fi

  backend="$(read_runtime_value "RUNTIME_BACKEND" 2>/dev/null || true)"
  if [ -n "${backend:-}" ]; then
    echo "$backend"
    return 0
  fi

  if [ "$INSTALL_SCOPE" = "system" ] && systemd_available; then
    echo "systemd"
    return 0
  fi

  if [ "$INSTALL_SCOPE" = "user" ] && systemd_user_available; then
    echo "systemd-user"
    return 0
  fi

  echo "script"
}

shell_profile_file() {
  if [ "$INSTALL_SCOPE" = "system" ]; then
    echo "/etc/profile.d/clash-for-linux.sh"
    return 0
  fi

  echo "$HOME/.bashrc"
}

alias_source_file() {
  echo "$PROJECT_DIR/scripts/core/alias.sh"
}

fish_alias_source_file() {
  echo "$PROJECT_DIR/scripts/core/alias.fish"
}

completion_dir() {
  if [ "$INSTALL_SCOPE" = "system" ]; then
    echo "/etc/profile.d"
  else
    echo "$HOME/.config/clash-for-linux"
  fi
}

bash_completion_entry_file() {
  if [ "$INSTALL_SCOPE" = "system" ]; then
    echo "$(completion_dir)/clash-for-linux-completion.bash"
  else
    echo "$(completion_dir)/completion.bash"
  fi
}

zsh_completion_entry_file() {
  if [ "$INSTALL_SCOPE" = "system" ]; then
    echo "$(completion_dir)/clash-for-linux-completion.zsh"
  else
    echo "$(completion_dir)/completion.zsh"
  fi
}

fish_completion_entry_file() {
  if [ "$INSTALL_SCOPE" = "system" ]; then
    echo "/etc/fish/completions/clash-for-linux.fish"
  else
    echo "$(completion_dir)/completion.fish"
  fi
}

fish_completion_link_file() {
  if [ "$INSTALL_SCOPE" = "system" ]; then
    echo "/etc/fish/completions/clash-for-linux.fish"
  else
    echo "$HOME/.config/fish/completions/clash-for-linux.fish"
  fi
}

fish_completion_link_files() {
  local dir name

  if [ "$INSTALL_SCOPE" = "system" ]; then
    dir="/etc/fish/completions"
  else
    dir="$HOME/.config/fish/completions"
  fi

  for name in clashctl clashrelay clashmixin clashsecret clashupgrade clashtun; do
    echo "$dir/$name.fish"
  done

  echo "$(fish_completion_link_file)"
}

clashctl_entry_target() {
  echo "$(command_install_dir)/clashctl"
}

clashctl_bin_entry_target() {
  echo "$(command_install_dir)/clashctl-bin"
}

ensure_command_install_dir_in_shell_path() {
  local install_dir shell_rc

  install_dir="$(command_install_dir)"

  case ":$PATH:" in
    *":$install_dir:"*)
      return 0
      ;;
  esac

  for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -n "${shell_rc:-}" ] || continue
    touch "$shell_rc"
    if ! grep -Fq "$install_dir" "$shell_rc" 2>/dev/null; then
      {
        echo
        echo "# clash-for-linux PATH"
        echo "export PATH=\"$install_dir:\$PATH\""
      } >> "$shell_rc"
    fi
  done
}

install_clashctl_entry() {
  local install_dir target bin_target
  install_dir="$(command_install_dir)"
  target="$(clashctl_entry_target)"
  bin_target="$(clashctl_bin_entry_target)"

  mkdir -p "$install_dir"

  cat > "$bin_target" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec bash "$PROJECT_DIR/scripts/core/clashctl.sh" "\$@"
EOF
  chmod +x "$bin_target"

  cat > "$target" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$bin_target" "\$@"
EOF
  chmod +x "$target"

  ensure_command_install_dir_in_shell_path
}

install_alias_command_wrappers() {
  local alias_file install_dir wrapper_name

  alias_file="$(alias_source_file)"
  install_dir="$(command_install_dir)"

  [ -f "$alias_file" ] || die "未找到 alias 脚本：$alias_file"

  mkdir -p "$install_dir"

  for wrapper_name in \
    clashon \
    clashoff \
    clashproxy \
    clashls \
    clashselect \
    clashui \
    clashsecret \
    clashtun \
    clashrelay \
    clashupgrade \
    clashmixin
  do
    cat > "$install_dir/$wrapper_name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export CLASH_WRAPPER_EXEC="1"
source "$alias_file"
$wrapper_name "\$@"
EOF
    chmod +x "$install_dir/$wrapper_name"
  done
}

cleanup_legacy_shell_entries() {
  local shell_rc

  for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$shell_rc" ] || continue

    sed -i '\|/root/clashctl/scripts/cmd/clashctl.sh|d' "$shell_rc" 2>/dev/null || true
    sed -i '\|watch_proxy|d' "$shell_rc" 2>/dev/null || true
    sed -i '\|/root/clashctl|d' "$shell_rc" 2>/dev/null || true
  done
}

install_shell_alias_entry() {
  local profile_file fish_profile_file fish_conf_file alias_file fish_alias_file shell_rc bash_completion_file zsh_completion_file fish_completion_file

  cleanup_legacy_shell_entries

  profile_file="$(profile_entry_file)"
  fish_profile_file="$(fish_profile_entry_file)"
  fish_conf_file="$(fish_conf_entry_file)"
  alias_file="$(alias_source_file)"
  fish_alias_file="$(fish_alias_source_file)"
  bash_completion_file="$(bash_completion_entry_file)"
  zsh_completion_file="$(zsh_completion_entry_file)"
  fish_completion_file="$(fish_completion_entry_file)"

  mkdir -p "$(dirname "$profile_file")"
  [ -f "$alias_file" ] || die "未找到 alias 脚本：$alias_file"
  [ -f "$fish_alias_file" ] || die "未找到 fish alias 脚本：$fish_alias_file"

cat > "$profile_file" <<EOF
#!/usr/bin/env bash
# clash-for-linux shell entry
export PATH="$(command_install_dir):\$PATH"

if [ -n "\${BASH_VERSION:-}" ] && [ -z "\${CLASH_FOR_LINUX_SHELL_LOADED:-}" ]; then
  CLASH_FOR_LINUX_SHELL_LOADED="1"
  source "$alias_file"
fi

case "\$-" in
  *i*)
    if [ -n "\${BASH_VERSION:-}" ] && [ -z "\${CLASH_FOR_LINUX_BASH_COMPLETION_LOADED:-}" ] && [ -f "$bash_completion_file" ]; then
      export CLASH_FOR_LINUX_BASH_COMPLETION_LOADED="1"
      source "$bash_completion_file"
    elif [ -n "\${ZSH_VERSION:-}" ] && [ -z "\${CLASH_FOR_LINUX_ZSH_COMPLETION_LOADED:-}" ] && [ -f "$zsh_completion_file" ]; then
      export CLASH_FOR_LINUX_ZSH_COMPLETION_LOADED="1"
      source "$zsh_completion_file"
    fi
    ;;
esac
EOF
  chmod +x "$profile_file"

  mkdir -p "$(dirname "$fish_profile_file")"
cat > "$fish_profile_file" <<EOF
# clash-for-linux fish shell entry
set -g CLASH_FOR_LINUX_PROJECT_DIR "$PROJECT_DIR"
if functions -q fish_add_path
  fish_add_path "$(command_install_dir)"
else if not contains -- "$(command_install_dir)" \$PATH
  set -gx PATH "$(command_install_dir)" \$PATH
end

if test -f "$fish_alias_file"
  source "$fish_alias_file"
end

if status is-interactive; and test -f "$fish_completion_file"
  source "$fish_completion_file"
end
EOF

  if [ "$fish_conf_file" != "$fish_profile_file" ]; then
    mkdir -p "$(dirname "$fish_conf_file")"
cat > "$fish_conf_file" <<EOF
# clash-for-linux fish shell entry
if test -f "$fish_profile_file"
  source "$fish_profile_file"
end
EOF
  fi

  for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    install_rc_source_block "$shell_rc" "$profile_file"
  done

  install_alias_command_wrappers
}

install_clashctl_completion() {
  local bash_target zsh_target fish_target fish_link_target

  bash_target="$(bash_completion_entry_file)"
  zsh_target="$(zsh_completion_entry_file)"
  fish_target="$(fish_completion_entry_file)"

  mkdir -p "$(dirname "$bash_target")"
  mkdir -p "$(dirname "$zsh_target")"
  mkdir -p "$(dirname "$fish_target")"

  bash "$PROJECT_DIR/scripts/core/clashctl.sh" completion bash > "$bash_target"
  bash "$PROJECT_DIR/scripts/core/clashctl.sh" completion zsh > "$zsh_target"
  bash "$PROJECT_DIR/scripts/core/clashctl.sh" completion fish > "$fish_target"

  chmod +x "$bash_target" "$zsh_target" "$fish_target" 2>/dev/null || true

  while IFS= read -r fish_link_target; do
    [ -n "${fish_link_target:-}" ] || continue
    [ "$fish_link_target" != "$fish_target" ] || continue
    mkdir -p "$(dirname "$fish_link_target")"
    cat > "$fish_link_target" <<EOF
# clash-for-linux fish completion entry
if test -f "$fish_target"
  source "$fish_target"
end
EOF
  done < <(fish_completion_link_files)
}

remove_clashctl_entry() {
  rm -f "$(clashctl_entry_target)" "$(clashctl_bin_entry_target)" 2>/dev/null || true
  remove_alias_command_wrappers
}

remove_shell_alias_entry() {
  local profile_file fish_profile_file fish_conf_file
  profile_file="$(profile_entry_file)"
  fish_profile_file="$(fish_profile_entry_file)"
  fish_conf_file="$(fish_conf_entry_file)"
  rm -f "$profile_file" 2>/dev/null || true
  rm -f "$fish_profile_file" "$fish_conf_file" 2>/dev/null || true

  if [ "$INSTALL_SCOPE" = "user" ]; then
    local shell_rc
    for shell_rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
      [ -f "$shell_rc" ] || continue
      awk -v profile="$profile_file" '
        index($0, profile) == 0 { print }
      ' "$shell_rc" > "${shell_rc}.tmp" && mv "${shell_rc}.tmp" "$shell_rc"
    done
  fi
}

remove_clashctl_completion() {
  rm -f "$(bash_completion_entry_file)" "$(zsh_completion_entry_file)" \
    "$(fish_completion_entry_file)" "$(fish_completion_link_file)" 2>/dev/null || true
  while IFS= read -r fish_link_target; do
    [ -n "${fish_link_target:-}" ] || continue
    rm -f "$fish_link_target" 2>/dev/null || true
  done < <(fish_completion_link_files)
}

install_has_subscription() {
  [ -n "$(subscription_url 2>/dev/null || true)" ]
}

install_runtime_ready() {
  [ "$(read_runtime_event_value "RUNTIME_LAST_INSTALL_READY" 2>/dev/null || true)" = "true" ]
}

shell_rc_files() {
  if [ "$INSTALL_SCOPE" = "system" ]; then
    echo "/etc/profile.d/clash-for-linux.sh"
    return 0
  fi

  echo "$HOME/.bashrc"
  echo "$HOME/.zshrc"
  echo "$HOME/.profile"
}

user_local_bin_dir() {
  echo "$HOME/.local/bin"
}

command_install_dir() {
  if [ "$INSTALL_SCOPE" = "system" ]; then
    if is_openwrt; then
      echo "/usr/bin"
      return 0
    fi
    echo "/usr/local/bin"
  else
    echo "$HOME/.local/bin"
  fi
}

profile_entry_file() {
  if [ "$INSTALL_SCOPE" = "system" ]; then
    echo "/etc/profile.d/clash-for-linux.sh"
  else
    echo "$HOME/.config/clash-for-linux/profile.sh"
  fi
}

fish_profile_entry_file() {
  if [ "$INSTALL_SCOPE" = "system" ]; then
    echo "/etc/fish/conf.d/clash-for-linux.fish"
  else
    echo "$HOME/.config/clash-for-linux/profile.fish"
  fi
}

fish_conf_entry_file() {
  if [ "$INSTALL_SCOPE" = "system" ]; then
    echo "/etc/fish/conf.d/clash-for-linux.fish"
  else
    echo "$HOME/.config/fish/conf.d/clash-for-linux.fish"
  fi
}

install_rc_source_block() {
  local profile_file="$1"
  local source_target="$2"
  local marker_begin marker_end

  marker_begin="# >>> clash-for-linux >>>"
  marker_end="# <<< clash-for-linux <<<"

  mkdir -p "$(dirname "$profile_file")"
  touch "$profile_file"

  awk -v begin="$marker_begin" -v end="$marker_end" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$profile_file" > "${profile_file}.tmp" && mv "${profile_file}.tmp" "$profile_file"

  {
    echo "$marker_begin"
    echo "[ -f \"$source_target\" ] && source \"$source_target\""
    echo "$marker_end"
  } >> "$profile_file"
}

remove_rc_source_block() {
  local profile_file="$1"
  local marker_begin marker_end

  marker_begin="# >>> clash-for-linux >>>"
  marker_end="# <<< clash-for-linux <<<"

  [ -f "$profile_file" ] || return 0

  awk -v begin="$marker_begin" -v end="$marker_end" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$profile_file" > "${profile_file}.tmp" && mv "${profile_file}.tmp" "$profile_file"
}

install_user_local_bin_path_entry() {
  local profile_file marker_begin marker_end path_dir

  [ "$INSTALL_SCOPE" = "user" ] || return 0

  path_dir="$(user_local_bin_dir)"
  marker_begin="# >>> clash-for-linux-path >>>"
  marker_end="# <<< clash-for-linux-path <<<"

  while IFS= read -r profile_file; do
    [ -n "${profile_file:-}" ] || continue
    [ "$profile_file" = "/etc/profile.d/clash-for-linux.sh" ] && continue

    mkdir -p "$(dirname "$profile_file")"
    touch "$profile_file"

    awk -v begin="$marker_begin" -v end="$marker_end" '
      $0 == begin {skip=1; next}
      $0 == end {skip=0; next}
      !skip {print}
    ' "$profile_file" > "${profile_file}.tmp" && mv "${profile_file}.tmp" "$profile_file"

    {
      echo "$marker_begin"
      echo "case \":\$PATH:\" in"
      echo "  *\":$path_dir:\"*) ;;"
      echo "  *) export PATH=\"$path_dir:\$PATH\" ;;"
      echo "esac"
      echo "$marker_end"
    } >> "$profile_file"
  done < <(shell_rc_files)
}

remove_user_local_bin_path_entry() {
  local profile_file marker_begin marker_end

  [ "$INSTALL_SCOPE" = "user" ] || return 0

  marker_begin="# >>> clash-for-linux-path >>>"
  marker_end="# <<< clash-for-linux-path <<<"

  while IFS= read -r profile_file; do
    [ -n "${profile_file:-}" ] || continue
    [ -f "$profile_file" ] || continue

    awk -v begin="$marker_begin" -v end="$marker_end" '
      $0 == begin {skip=1; next}
      $0 == end {skip=0; next}
      !skip {print}
    ' "$profile_file" > "${profile_file}.tmp" && mv "${profile_file}.tmp" "$profile_file"
  done < <(shell_rc_files)
}

remove_alias_command_wrappers() {
  local install_dir wrapper_name

  install_dir="$(command_install_dir)"

  for wrapper_name in \
    clashon \
    clashoff \
    clashproxy \
    clashls \
    clashselect \
    clashui \
    clashsecret \
    clashtun \
    clashrelay \
    clashupgrade \
    clashmixin
  do
    rm -f "$install_dir/$wrapper_name" 2>/dev/null || true
  done
}

install_status_text() {
  local has_subscription install_ready runtime_ready controller_ready build_status bind_failure_kind
  local live_runtime="false"
  local live_controller="false"

  if install_has_subscription; then
    has_subscription="true"
  else
    has_subscription="false"
  fi

  install_ready="$(read_runtime_event_value "RUNTIME_LAST_INSTALL_READY" 2>/dev/null || true)"
  runtime_ready="$(install_verify_runtime_ready 2>/dev/null || true)"
  controller_ready="$(install_verify_controller_ready 2>/dev/null || true)"
  build_status="$(read_build_value "BUILD_LAST_STATUS" 2>/dev/null || true)"
  bind_failure_kind="$(install_mixed_port_bind_failure_kind 2>/dev/null || true)"

  if status_is_running 2>/dev/null; then
    live_runtime="true"
  fi

  if proxy_controller_reachable 2>/dev/null; then
    live_controller="true"
  fi

  if [ "${has_subscription:-false}" != "true" ]; then
    echo "stopped"
    return 0
  fi

  if [ "${build_status:-}" = "failed" ]; then
    echo "broken"
    return 0
  fi

  if [ -n "${bind_failure_kind:-}" ]; then
    echo "broken"
    return 0
  fi

  if [ "${live_runtime:-false}" = "true" ] && [ "${live_controller:-false}" = "true" ]; then
    echo "ready"
    return 0
  fi

  if [ "${install_ready:-false}" = "true" ] \
    || { [ "${runtime_ready:-false}" = "true" ] && [ "${controller_ready:-false}" = "true" ]; }; then
    echo "ready"
    return 0
  fi

  if [ "${live_runtime:-false}" = "true" ] \
    || [ "${runtime_ready:-false}" = "true" ] \
    || [ "${controller_ready:-false}" = "true" ]; then
    echo "verifying"
    return 0
  fi

  echo "verifying"
}

install_mixed_port_bind_failure_line() {
  local log_file="$LOG_DIR/mihomo.out.log"
  local mixed_port line

  [ -f "$log_file" ] || return 1
  runtime_config_exists 2>/dev/null || return 1

  mixed_port="$(runtime_config_mixed_port 2>/dev/null || true)"
  if [ -n "${mixed_port:-}" ] && [ "$mixed_port" != "null" ]; then
    line="$(grep -Ei "Start Mixed.*server error: listen tcp .*:${mixed_port}:.*(operation not permitted|permission denied|address already in use)" "$log_file" 2>/dev/null | tail -n 1 || true)"
  fi

  if [ -z "${line:-}" ]; then
    line="$(grep -Ei 'Start Mixed.*server error: listen tcp .*:.*(operation not permitted|permission denied|address already in use)' "$log_file" 2>/dev/null | tail -n 1 || true)"
  fi

  [ -n "${line:-}" ] || return 1
  printf '%s\n' "$line"
}

install_mixed_port_bind_failure_kind() {
  local line lower

  line="$(install_mixed_port_bind_failure_line 2>/dev/null || true)"
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

install_mixed_port_bind_failure_port() {
  local port line

  port="$(runtime_config_mixed_port 2>/dev/null || true)"
  if runtime_port_value_is_valid "$port"; then
    echo "$port"
    return 0
  fi

  line="$(install_mixed_port_bind_failure_line 2>/dev/null || true)"
  [ -n "${line:-}" ] || return 1
  printf '%s\n' "$line" | grep -Eo ':[0-9]+:' | tail -n 1 | tr -d ':'
}

install_mixed_port_bind_observation_line() {
  local mixed_port controller_port

  mixed_port="$(install_mixed_port_bind_failure_port 2>/dev/null || true)"
  controller_port="$(runtime_config_controller_port 2>/dev/null || true)"

  if proxy_controller_reachable 2>/dev/null \
    || { runtime_port_value_is_valid "$controller_port" && is_port_in_use "$controller_port"; }; then
    echo "配置已加载，控制器已启动，仅代理端口 ${mixed_port:-unknown} 绑定失败；这不是订阅或配置主链失败"
  fi
}

install_status_label() {
  case "$(install_status_text)" in
    ready) echo "ready" ;;
    stopped) echo "stopped" ;;
    verifying) echo "verifying" ;;
    broken) echo "broken" ;;
    *) echo "unknown" ;;
  esac
}

install_default_next_action() {
  case "$(install_status_text)" in
    ready)
      echo "clashctl select"
      ;;
    stopped)
      if install_has_subscription; then
        echo "clashon"
      else
        echo "clashctl add <订阅链接>"
      fi
      ;;
    verifying)
      if status_is_running 2>/dev/null; then
        echo "clashctl status"
      else
        echo "clashon"
      fi
      ;;
    broken)
      if install_has_subscription; then
        echo "clashctl doctor"
      else
        echo "clashctl add <订阅链接>"
      fi
      ;;
    *)
      echo "clashctl status"
      ;;
  esac
}

install_runtime_brief_line() {
  local status_text mixed_port controller controller_display bind_failure_kind

  status_text="$(install_status_text)"
  bind_failure_kind="$(install_mixed_port_bind_failure_kind 2>/dev/null || true)"
  mixed_port="$(install_plan_mixed_port 2>/dev/null || true)"
  [ -n "${mixed_port:-}" ] || mixed_port="$(read_env_value "MIXED_PORT" 2>/dev/null || echo "7890")"

  controller="$(install_plan_controller 2>/dev/null || true)"
  [ -n "${controller:-}" ] || controller="$(read_env_value "EXTERNAL_CONTROLLER" 2>/dev/null || echo "127.0.0.1:9090")"
  controller_display="$(display_controller_local_addr "$controller" 2>/dev/null || true)"

  if ! runtime_port_value_is_valid "$mixed_port" || [ -z "${controller_display:-}" ]; then
    status_text="broken"
  fi

  case "$status_text" in
    ready)
      echo "🐱 当前状态：ready"
      echo "🌐 本地代理：http://127.0.0.1:${mixed_port}"
      echo "💻 控制台：http://${controller_display:-$controller}/ui"
      ;;
    stopped)
      echo "❗ 当前状态：stopped"
      ;;
    verifying)
      echo "🟡 当前状态：verifying"
      echo "📜 正在确认运行状态，可继续观察或手动启动"
      if [ -n "${mixed_port:-}" ]; then
        echo "🌐 本地代理：http://127.0.0.1:${mixed_port}"
      fi
      if [ -n "${controller:-}" ]; then
        echo "💻 控制台：http://${controller_display:-$controller}/ui"
      fi
      ;;
    broken)
      echo "❗ 当前状态：broken"
      case "${bind_failure_kind:-}" in
        bind_denied)
          echo "🚫 代理端口绑定被系统拒绝（非端口冲突）"
          echo "📌 修改端口通常无法解决，请先排查当前环境限制"
          ;;
        address_in_use)
          echo "⚠️  代理端口存在冲突（address already in use）"
          ;;
      esac
      ;;
    *)
      echo "⚪ 当前状态：unknown"
      ;;
  esac
}

print_install_summary() {
  local clashctl_file
  local kernel_text project_path arch_text install_actor install_scope_text
  local env_mode env_mode_text os_variant backend_text subscription_text node_count runtime_file

  clashctl_file="$(clashctl_source)"
  kernel_text="$(runtime_kernel_type 2>/dev/null || echo "unknown")"
  project_path="${PROJECT_DIR:-unknown}"
  arch_text="$(install_env_arch 2>/dev/null || true)"
  [ -n "${arch_text:-}" ] || arch_text="$(get_arch 2>/dev/null || echo "unknown")"

  if [ "$(install_env_is_root 2>/dev/null || echo false)" = "true" ]; then
    install_actor="root"
  else
    install_actor="user"
  fi

  install_scope_text="$(install_env_scope 2>/dev/null || true)"
  [ -n "${install_scope_text:-}" ] || install_scope_text="${INSTALL_SCOPE:-unknown}"

  env_mode="$(install_env_container 2>/dev/null || true)"
  [ -n "${env_mode:-}" ] || env_mode="$(container_env_type 2>/dev/null || echo "unknown")"
  os_variant="$(install_env_os_variant 2>/dev/null || true)"
  case "${env_mode:-unknown}" in
    host)
      if [ "${os_variant:-}" = "openwrt" ]; then
        env_mode_text="OpenWrt 主机"
      else
        env_mode_text="主机"
      fi
      ;;
    container|docker|lxc)
      env_mode_text="容器"
      ;;
    *)
      env_mode_text="${env_mode:-unknown}"
      ;;
  esac

  backend_text="$(install_plan_backend 2>/dev/null || true)"
  [ -n "${backend_text:-}" ] || backend_text="$(runtime_backend 2>/dev/null || echo "unknown")"

  if install_has_subscription 2>/dev/null; then
    subscription_text="已配置"
  else
    subscription_text="未配置"
  fi

  runtime_file="$(runtime_config_file)"
  if [ -s "$runtime_file" ]; then
    node_count="$("$(yq_bin)" eval '(.proxies // []) | length' "$runtime_file" 2>/dev/null | head -n 1)"
    case "${node_count:-}" in
      ''|*[!0-9]*)
        node_count=""
        ;;
    esac
  fi

  echo
  echo "🎉 安装完成"
  echo
  echo "🚀 当前内核：$kernel_text"
  echo "🧬 系统架构：$arch_text"
  echo "💻 环境模式：${env_mode_text:-unknown}"
  echo "📁 安装路径：$project_path"
  echo "👤 安装方式：${install_actor} / ${install_scope_text:-unknown}"
  echo "🔧 运行后端：${backend_text:-unknown}"
  echo "📦 订阅：$subscription_text"
  [ -n "${node_count:-}" ] && echo "🔢 节点数量：$node_count"

  case "$(install_mixed_port_bind_failure_kind 2>/dev/null || true)" in
    bind_denied)
      echo "🚫 安装后验证：代理端口绑定被系统拒绝（非端口冲突）"
      echo "📌 这通常是环境限制，修改端口通常无法解决"
      install_mixed_port_bind_observation_line 2>/dev/null || true
      echo "👉 下一步：clashctl doctor"
      echo "👉 日志：clashctl logs mihomo"
      ;;
    address_in_use)
      :
      ;;
  esac

  if [ -f "$clashctl_file" ]; then
    CLASH_UI_BOX_ONLY=1 bash "$clashctl_file" ui || true
  fi

  echo
  echo "💡 clashon / clashoff 为 shell 快捷入口；新终端会自动生效"
  echo "💡 当前终端若暂不可用，请先使用 clashctl on / clashctl off"
}
