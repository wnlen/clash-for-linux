#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source_clashctl_for_tests() {
  set -- ""
  source "$PROJECT_DIR/scripts/core/clashctl.sh" >/dev/null
}

source_clashctl_for_tests

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

prepare() { :; }
status_is_running() { return 0; }
proxy_controller_reachable() { return 0; }
ui_title() { printf 'title:%s\n' "$1"; }
ui_kv() { printf '%s:%s\n' "$2" "$3"; }
ui_warn() { printf 'warn:%s\n' "$1"; }
ui_ok() { printf 'success:%s\n' "$1"; }
ui_next() { printf 'next:%s\n' "$1"; }
ui_blank() { :; }
die() {
  printf 'error:%s\n' "$1"
  exit 1
}
die_usage() {
  printf 'usage:%s\nnext:%s\n' "$1" "${2:-}"
  exit 2
}
die_state() {
  printf 'state:%s\nnext:%s\n' "$1" "${2:-}"
  exit 3
}

run_proxy_helper_case() {
  local fake_yq="$tmp_dir/yq"
  local controller_calls="$tmp_dir/controller-calls"
  local mode delay encoded_path

  cat > "$fake_yq" <<'EOF'
#!/usr/bin/env bash
payload="$(cat)"
case "$payload" in
  *'"mode"'*)
    printf '%s\n' "$payload" | sed -nE 's/.*"mode":"([^"]+)".*/\1/p'
    ;;
  *'"delay"'*)
    printf '%s\n' "$payload" | sed -nE 's/.*"delay":([0-9]+).*/\1/p'
    ;;
esac
EOF
  chmod +x "$fake_yq"

  yq_bin() { printf '%s\n' "$fake_yq"; }
  controller_curl() {
    printf '%s|%s|%s\n' "$1" "$2" "${3:-}" >> "$controller_calls"
    case "$1|$2" in
      "GET|/configs")
        printf '%s\n' '{"mode":"global"}'
        ;;
      GET\|/proxies/*/delay*)
        printf '%s\n' '{"delay":77}'
        ;;
    esac
  }

  mode="$(proxy_mode_current)"
  [ "$mode" = "global" ] || {
    echo "not ok - proxy mode helper should parse controller state" >&2
    return 1
  }

  proxy_mode_set rule
  if ! grep -Fq 'PATCH|/configs|{"mode":"rule"}' "$controller_calls"; then
    echo "not ok - proxy mode helper should PATCH /configs" >&2
    cat "$controller_calls" >&2
    return 1
  fi

  delay="$(proxy_node_test_delay "节点 A" "https://www.gstatic.com/generate_204" 8000)"
  [ "$delay" = "77" ] || {
    echo "not ok - proxy delay helper should parse delay" >&2
    return 1
  }

  encoded_path="$(tail -n 1 "$controller_calls")"
  if ! printf '%s\n' "$encoded_path" | grep -Fq '/proxies/%E8%8A%82%E7%82%B9%20A/delay?timeout=8000&url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204'; then
    echo "not ok - proxy delay helper should URL-encode node and target" >&2
    printf '%s\n' "$encoded_path" >&2
    return 1
  fi

  echo "ok - controller mode and delay helpers use the expected API requests"
}

run_mode_status_case() {
  local output

  proxy_mode_current() { echo "rule"; }
  output="$(cmd_mode)"

  if ! printf '%s\n' "$output" | grep -Fq "当前模式:规则模式（rule）"; then
    echo "not ok - mode status should show the current mode" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  echo "ok - mode status shows the current mode"
}

run_mode_switch_case() {
  local output
  local selected_file="$tmp_dir/mode-selected"

  proxy_mode_set() { printf '%s\n' "$1" > "$selected_file"; }
  proxy_mode_current() { cat "$selected_file"; }
  proxy_group_current() {
    [ "$1" = "GLOBAL" ] || return 1
    echo "节点选择"
  }

  output="$(cmd_mode GLOBAL)"

  if [ "$(cat "$selected_file")" != "global" ]; then
    echo "not ok - mode switch should normalize and set global" >&2
    return 1
  fi

  if ! printf '%s\n' "$output" | grep -Fq "GLOBAL 当前选择:节点选择"; then
    echo "not ok - global mode should show the GLOBAL selection" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  echo "ok - mode global switches and verifies controller state"
}

run_mode_bad_args_case() {
  local output rc

  set +e
  output="$(cmd_mode invalid 2>&1)"
  rc=$?
  set -e

  if [ "$rc" -ne 2 ]; then
    echo "not ok - invalid mode should fail usage" >&2
    printf 'rc=%s\n%s\n' "$rc" "$output" >&2
    return 1
  fi

  echo "ok - mode validates arguments"
}

run_test_success_case() {
  local output

  proxy_mode_current() { echo "rule"; }
  default_proxy_group_name() { echo "节点选择"; }
  proxy_group_exists() { [ "$1" = "节点选择" ]; }
  proxy_group_current() { echo "日本 01"; }
  proxy_node_test_delay() {
    case "$2" in
      *gstatic*) echo "88" ;;
      *youtube*) echo "123" ;;
      *) return 1 ;;
    esac
  }

  output="$(cmd_test)"

  if ! printf '%s\n' "$output" | grep -Fq "Google"; then
    echo "not ok - test should include Google" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
  if ! printf '%s\n' "$output" | grep -Fq "YouTube"; then
    echo "not ok - test should include YouTube" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
  if ! printf '%s\n' "$output" | grep -Fq "当前选择可访问全部测试目标"; then
    echo "not ok - successful test should print summary" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  echo "ok - test checks the current selection"
}

run_test_failure_case() {
  local output rc

  proxy_mode_current() { echo "global"; }
  proxy_group_exists() { [ "$1" = "GLOBAL" ]; }
  proxy_group_current() { echo "节点选择"; }
  proxy_node_test_delay() {
    case "$2" in
      *gstatic*) echo "66" ;;
      *) return 1 ;;
    esac
  }

  set +e
  output="$(cmd_test 2>&1)"
  rc=$?
  set -e

  if [ "$rc" -ne 1 ]; then
    echo "not ok - failed target should make test return non-zero" >&2
    printf 'rc=%s\n%s\n' "$rc" "$output" >&2
    return 1
  fi
  if ! printf '%s\n' "$output" | grep -Fq "1 个目标不可访问"; then
    echo "not ok - failed test should print failure count" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi

  echo "ok - test returns non-zero when a target is unreachable"
}

run_clashtest_wrapper_case() {
  local fixture_bin="$tmp_dir/bin"
  local output

  source "$PROJECT_DIR/scripts/core/common.sh"

  mkdir -p "$fixture_bin"
  alias_source_file() { printf '%s\n' "$PROJECT_DIR/scripts/core/alias.sh"; }
  command_install_dir() { printf '%s\n' "$fixture_bin"; }

  install_alias_command_wrappers

  if [ ! -x "$fixture_bin/clashtest" ]; then
    echo "not ok - install should create clashtest wrapper" >&2
    return 1
  fi

  cat > "$fixture_bin/clashctl-bin" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
EOF
  chmod +x "$fixture_bin/clashctl-bin"

  output="$(
    env -i \
      HOME="$tmp_dir/home" \
      PATH="$fixture_bin:/usr/bin:/bin" \
      CLASH_SHELL_AUTO_RESTORE_PROXY=false \
      "$fixture_bin/clashtest" "节点选择"
  )"

  if [ "$output" != "test 节点选择" ]; then
    echo "not ok - clashtest should delegate to clashctl test" >&2
    printf 'actual: %s\n' "$output" >&2
    return 1
  fi

  remove_alias_command_wrappers
  if [ -e "$fixture_bin/clashtest" ]; then
    echo "not ok - uninstall should remove clashtest wrapper" >&2
    return 1
  fi

  echo "ok - clashtest wrapper is installed, delegated, and removed"
}

run_completion_case() {
  local completion_file="$tmp_dir/clashctl-completion.bash"
  local mode_output test_output

  bash "$PROJECT_DIR/scripts/core/clashctl.sh" completion bash > "$completion_file"

  mode_output="$(
    bash --noprofile --norc -c '
      source "$1"
      COMP_WORDS=(clashctl mode g)
      COMP_CWORD=2
      _clash_for_linux_complete_command
      printf "%s\n" "${COMPREPLY[@]}"
    ' bash "$completion_file"
  )"
  if ! printf '%s\n' "$mode_output" | grep -Fxq global; then
    echo "not ok - mode completion should include global" >&2
    printf 'actual: %s\n' "$mode_output" >&2
    return 1
  fi

  test_output="$(
    bash --noprofile --norc -c '
      source "$1"
      COMP_WORDS=(clashtest -)
      COMP_CWORD=1
      _clash_for_linux_complete_command
      printf "%s\n" "${COMPREPLY[@]}"
    ' bash "$completion_file"
  )"
  if ! printf '%s\n' "$test_output" | grep -Fxq -- --help; then
    echo "not ok - clashtest completion should include --help" >&2
    printf 'actual: %s\n' "$test_output" >&2
    return 1
  fi

  echo "ok - mode and clashtest completions are available"
}

run_proxy_helper_case
run_mode_status_case
run_mode_switch_case
run_mode_bad_args_case
run_test_success_case
run_test_failure_case
run_clashtest_wrapper_case
run_completion_case
