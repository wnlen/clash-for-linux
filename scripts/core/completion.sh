#!/usr/bin/env bash

completion_emit_script_body() {
  printf '_clash_for_linux_project_dir=%q\n' "$PROJECT_DIR"
  cat <<'EOF'
_clash_for_linux_runtime_dir="${_clash_for_linux_project_dir}/runtime"
_clash_for_linux_subscription_file="${_clash_for_linux_runtime_dir}/subscriptions.yaml"
_clash_for_linux_mixin_file="${_clash_for_linux_runtime_dir}/mixin.yaml"
_clash_for_linux_local_subscription_dir="${_clash_for_linux_runtime_dir}/subscriptions"
_clash_for_linux_yq_bin="${_clash_for_linux_runtime_dir}/bin/yq"

# Hard constraints for completion:
# - local-only and offline
# - no controller or network access
# - low-latency best effort with immediate silent fallback
# - skip YAML-based dynamic completion when yq is missing or fails

_clash_for_linux_add_matches() {
  local cur="$1"
  local candidate
  shift

  for candidate in "$@"; do
    [ -n "${candidate:-}" ] || continue
    if [ -z "$cur" ] || [ "${candidate:0:${#cur}}" = "$cur" ]; then
      COMPREPLY+=("$candidate")
    fi
  done
}

_clash_for_linux_add_stream_matches() {
  local cur="$1"
  local candidate

  while IFS= read -r candidate; do
    [ -n "${candidate:-}" ] || continue
    [ "$candidate" = "null" ] && continue
    if [ -z "$cur" ] || [ "${candidate:0:${#cur}}" = "$cur" ]; then
      COMPREPLY+=("$candidate")
    fi
  done
}

_clash_for_linux_add_subscription_matches() {
  local cur="$1"

  [ -x "$_clash_for_linux_yq_bin" ] || return 0
  [ -s "$_clash_for_linux_subscription_file" ] || return 0

  _clash_for_linux_add_stream_matches "$cur" < <(
    "$_clash_for_linux_yq_bin" eval '.sources | keys | .[]' "$_clash_for_linux_subscription_file" 2>/dev/null
  )
}

_clash_for_linux_add_relay_matches() {
  local cur="$1"

  [ -x "$_clash_for_linux_yq_bin" ] || return 0
  [ -s "$_clash_for_linux_mixin_file" ] || return 0

  _clash_for_linux_add_stream_matches "$cur" < <(
    "$_clash_for_linux_yq_bin" eval '(.append["proxy-groups"] // [])[] | select(.type == "relay") | .name' "$_clash_for_linux_mixin_file" 2>/dev/null
  )
}

_clash_for_linux_add_local_subscription_matches() {
  local cur="$1"
  local path

  [ -d "$_clash_for_linux_local_subscription_dir" ] || return 0

  while IFS= read -r path; do
    [ -n "${path:-}" ] || continue
    if [ -z "$cur" ] || [ "${path:0:${#cur}}" = "$cur" ]; then
      COMPREPLY+=("$path")
    fi
  done < <(
    for path in "$_clash_for_linux_local_subscription_dir"/*; do
      [ -f "$path" ] || continue
      printf '%s\n' "${path##*/}"
    done 2>/dev/null
  )
}

_clash_for_linux_complete_add() {
  local cur="$1"
  local rel_index="$2"
  local arg1="${3:-}"

  COMPREPLY=()

  if [ "$rel_index" -eq 1 ]; then
    _clash_for_linux_add_matches "$cur" local
    return 0
  fi

  if [ "$arg1" = "local" ]; then
    _clash_for_linux_add_local_subscription_matches "$cur"
  fi
}

_clash_for_linux_complete_use() {
  local cur="$1"

  COMPREPLY=()
  _clash_for_linux_add_matches "$cur" --recommend -r --verbose -v

  case "$cur" in
    -*) return 0 ;;
  esac

  _clash_for_linux_add_subscription_matches "$cur"
}

_clash_for_linux_complete_health() {
  local cur="$1"

  COMPREPLY=()
  _clash_for_linux_add_matches "$cur" --verbose -v

  case "$cur" in
    -*) return 0 ;;
  esac

  _clash_for_linux_add_subscription_matches "$cur"
}

_clash_for_linux_complete_status() {
  local cur="$1"

  COMPREPLY=()
  _clash_for_linux_add_matches "$cur" --verbose -v
}

_clash_for_linux_complete_boot() {
  local cur="$1"
  local rel_index="$2"
  local arg1="${3:-}"

  COMPREPLY=()

  if [ "$rel_index" -eq 1 ]; then
    _clash_for_linux_add_matches "$cur" on off status runtime proxy help -h --help
    return 0
  fi

  case "$arg1" in
    runtime|proxy)
      if [ "$rel_index" -eq 2 ]; then
        _clash_for_linux_add_matches "$cur" on off status
      fi
      ;;
  esac
}

_clash_for_linux_complete_config() {
  local cur="$1"
  local rel_index="$2"
  local arg1="${3:-}"

  COMPREPLY=()

  if [ "$rel_index" -eq 1 ]; then
    _clash_for_linux_add_matches "$cur" show explain regen kernel
    return 0
  fi

  if [ "$arg1" = "kernel" ] && [ "$rel_index" -eq 2 ]; then
    _clash_for_linux_add_matches "$cur" mihomo clash
  fi
}

_clash_for_linux_complete_mixin() {
  local cur="$1"
  local rel_index="$2"

  COMPREPLY=()

  if [ "$rel_index" -eq 1 ]; then
    _clash_for_linux_add_matches "$cur" edit raw runtime help -e -c -r --edit --raw --runtime -h --help
  fi
}

_clash_for_linux_complete_relay() {
  local cur="$1"
  local rel_index="$2"
  local arg1="${3:-}"

  COMPREPLY=()

  if [ "$rel_index" -eq 1 ]; then
    _clash_for_linux_add_matches "$cur" add list ls remove rm delete help -h --help
    return 0
  fi

  case "$arg1" in
    remove|rm|delete)
      if [ "$rel_index" -eq 2 ]; then
        _clash_for_linux_add_relay_matches "$cur"
      fi
      ;;
    add)
      _clash_for_linux_add_matches "$cur" --domain --match
      ;;
  esac
}

_clash_for_linux_complete_sub() {
  local cur="$1"
  local rel_index="$2"
  local arg1="${3:-}"

  COMPREPLY=()

  if [ "$rel_index" -eq 1 ]; then
    _clash_for_linux_add_matches "$cur" list use set enable disable rename remove rm del health help -h --help
    return 0
  fi

  case "$arg1" in
    use|enable|disable|remove|rm|del)
      if [ "$rel_index" -eq 2 ]; then
        _clash_for_linux_add_subscription_matches "$cur"
      fi
      ;;
    rename)
      if [ "$rel_index" -eq 2 ]; then
        _clash_for_linux_add_subscription_matches "$cur"
      fi
      ;;
    health)
      _clash_for_linux_add_matches "$cur" --verbose -v
      if [ "$rel_index" -eq 2 ]; then
        case "$cur" in
          -*) return 0 ;;
        esac
        _clash_for_linux_add_subscription_matches "$cur"
      fi
      ;;
  esac
}

_clash_for_linux_complete_tun() {
  local cur="$1"
  local rel_index="$2"

  COMPREPLY=()

  if [ "$rel_index" -eq 1 ]; then
    _clash_for_linux_add_matches "$cur" status on off doctor
  fi
}

_clash_for_linux_complete_upgrade() {
  local cur="$1"

  COMPREPLY=()
  _clash_for_linux_add_matches "$cur" mihomo clash -v --verbose
}

_clash_for_linux_complete_update() {
  local cur="$1"

  COMPREPLY=()
  _clash_for_linux_add_matches "$cur" --force --regenerate
}

_clash_for_linux_complete_dev() {
  local cur="$1"
  local rel_index="$2"

  COMPREPLY=()

  if [ "$rel_index" -eq 1 ]; then
    _clash_for_linux_add_matches "$cur" reset
  fi
}

_clash_for_linux_complete_completion() {
  local cur="$1"
  local rel_index="$2"

  COMPREPLY=()

  if [ "$rel_index" -eq 1 ]; then
    _clash_for_linux_add_matches "$cur" bash zsh
  fi
}

_clash_for_linux_complete_help() {
  local cur="$1"
  local rel_index="$2"

  COMPREPLY=()

  if [ "$rel_index" -eq 1 ]; then
    _clash_for_linux_add_matches "$cur" advanced
  fi
}

_clash_for_linux_complete_top_level() {
  local cur="$1"

  COMPREPLY=()
  _clash_for_linux_add_matches "$cur" \
    add use ls health select on off status status-next \
    boot log logs doctor ui secret tun dev config mixin \
    relay profile sub proxy upgrade update completion help \
    -h --help
}

_clash_for_linux_complete_command() {
  local root cur canonical rel_index
  local arg1="" arg2="" arg3=""

  root="${COMP_WORDS[0]##*/}"
  cur="${COMP_WORDS[COMP_CWORD]:-}"

  case "$root" in
    clashctl)
      if [ "$COMP_CWORD" -eq 1 ]; then
        _clash_for_linux_complete_top_level "$cur"
        return 0
      fi
      canonical="${COMP_WORDS[1]:-}"
      rel_index=$((COMP_CWORD - 1))
      arg1="${COMP_WORDS[2]:-}"
      arg2="${COMP_WORDS[3]:-}"
      arg3="${COMP_WORDS[4]:-}"
      ;;
    clashrelay)
      canonical="relay"
      rel_index=$COMP_CWORD
      arg1="${COMP_WORDS[1]:-}"
      arg2="${COMP_WORDS[2]:-}"
      arg3="${COMP_WORDS[3]:-}"
      ;;
    clashmixin)
      canonical="mixin"
      rel_index=$COMP_CWORD
      arg1="${COMP_WORDS[1]:-}"
      ;;
    clashsecret)
      canonical="secret"
      rel_index=$COMP_CWORD
      arg1="${COMP_WORDS[1]:-}"
      ;;
    clashupgrade)
      canonical="upgrade"
      rel_index=$COMP_CWORD
      arg1="${COMP_WORDS[1]:-}"
      ;;
    clashtun)
      canonical="tun"
      rel_index=$COMP_CWORD
      arg1="${COMP_WORDS[1]:-}"
      ;;
    *)
      COMPREPLY=()
      return 0
      ;;
  esac

  case "$canonical" in
    add) _clash_for_linux_complete_add "$cur" "$rel_index" "$arg1" ;;
    use) _clash_for_linux_complete_use "$cur" ;;
    health) _clash_for_linux_complete_health "$cur" ;;
    status) _clash_for_linux_complete_status "$cur" ;;
    boot) _clash_for_linux_complete_boot "$cur" "$rel_index" "$arg1" ;;
    config) _clash_for_linux_complete_config "$cur" "$rel_index" "$arg1" ;;
    mixin) _clash_for_linux_complete_mixin "$cur" "$rel_index" ;;
    relay) _clash_for_linux_complete_relay "$cur" "$rel_index" "$arg1" ;;
    sub) _clash_for_linux_complete_sub "$cur" "$rel_index" "$arg1" ;;
    tun) _clash_for_linux_complete_tun "$cur" "$rel_index" ;;
    upgrade) _clash_for_linux_complete_upgrade "$cur" ;;
    update) _clash_for_linux_complete_update "$cur" ;;
    dev) _clash_for_linux_complete_dev "$cur" "$rel_index" ;;
    completion) _clash_for_linux_complete_completion "$cur" "$rel_index" ;;
    help) _clash_for_linux_complete_help "$cur" "$rel_index" ;;
    *)
      COMPREPLY=()
      ;;
  esac
}

complete -F _clash_for_linux_complete_command clashctl
complete -F _clash_for_linux_complete_command clashrelay
complete -F _clash_for_linux_complete_command clashmixin
complete -F _clash_for_linux_complete_command clashsecret
complete -F _clash_for_linux_complete_command clashupgrade
complete -F _clash_for_linux_complete_command clashtun
EOF
}

completion_emit_bash_script() {
  completion_emit_script_body
}

completion_emit_zsh_script() {
  cat <<'EOF'
autoload -Uz bashcompinit 2>/dev/null || return 0
bashcompinit >/dev/null 2>&1 || return 0
EOF
  completion_emit_script_body
}

cmd_completion() {
  case "${1:-}" in
    bash)
      completion_emit_bash_script
      ;;
    zsh)
      completion_emit_zsh_script
      ;;
    *)
      die_usage "completion 参数不合法" "clashctl completion bash|zsh"
      ;;
  esac
}
