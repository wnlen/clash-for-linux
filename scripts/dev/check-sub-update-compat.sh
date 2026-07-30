#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source_clashctl_for_tests() {
  set -- ""
  # Source the real command functions; suppress the no-arg usage printed by the dispatcher.
  source "$PROJECT_DIR/scripts/core/clashctl.sh" >/dev/null
}

source_clashctl_for_tests

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

calls_file="$tmp_dir/sub-update-calls"
output_file="$tmp_dir/sub-update-output"

prepare() { :; }
regenerate_config() { printf 'regenerate:%s\n' "${1:-}" >> "$calls_file"; }
apply_runtime_change_after_config_mutation() { printf 'apply\n' >> "$calls_file"; }
print_config_regen_feedback() { printf 'regen-feedback\n' >> "$calls_file"; }
print_config_apply_feedback() { printf 'apply-feedback\n' >> "$calls_file"; }

: > "$calls_file"
if ! ( cmd_sub update ) > "$output_file" 2>&1; then
  echo "not ok - clashctl sub update should succeed" >&2
  sed 's/^/  /' "$output_file" >&2
  exit 1
fi

expected_calls="$(printf '%s\n' regenerate:manual-refresh apply regen-feedback apply-feedback)"
actual_calls="$(cat "$calls_file")"
if [ "$actual_calls" != "$expected_calls" ]; then
  echo "not ok - clashctl sub update should follow the config regen path" >&2
  printf 'expected:\n%s\nactual:\n%s\n' "$expected_calls" "$actual_calls" >&2
  exit 1
fi

echo "ok - clashctl sub update follows the config regen path"
echo "ok - clashctl sub update bypasses stale subscription cache"

# Verify both the sourced-shell compatibility function and the installed command wrapper.
# shellcheck source=../core/common.sh
source "$PROJECT_DIR/scripts/core/common.sh"

fixture_bin="$tmp_dir/bin"
mkdir -p "$fixture_bin"

PROJECT_DIR="$PROJECT_DIR"
alias_source_file() { printf '%s\n' "$PROJECT_DIR/scripts/core/alias.sh"; }
command_install_dir() { printf '%s\n' "$fixture_bin"; }

install_alias_command_wrappers

if [ ! -x "$fixture_bin/clashsub" ]; then
  echo "not ok - install should create the clashsub compatibility wrapper" >&2
  exit 1
fi

cat > "$fixture_bin/clashctl-bin" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
EOF
chmod +x "$fixture_bin/clashctl-bin"

wrapper_output="$(
  env -i \
    HOME="$tmp_dir/home" \
    PATH="$fixture_bin:/usr/bin:/bin" \
    CLASH_SHELL_AUTO_RESTORE_PROXY=false \
    "$fixture_bin/clashsub" update
)"

if [ "$wrapper_output" != "sub update" ]; then
  echo "not ok - clashsub update should delegate to clashctl sub update" >&2
  printf 'actual: %s\n' "$wrapper_output" >&2
  exit 1
fi

remove_alias_command_wrappers
if [ -e "$fixture_bin/clashsub" ]; then
  echo "not ok - uninstall should remove the clashsub compatibility wrapper" >&2
  exit 1
fi

echo "ok - clashsub update compatibility wrapper is installed and removed"

completion_file="$tmp_dir/clashctl-completion.bash"
bash "$PROJECT_DIR/scripts/core/clashctl.sh" completion bash > "$completion_file"

completion_output="$(
  bash --noprofile --norc -c '
    source "$1"
    COMP_WORDS=(clashsub u)
    COMP_CWORD=1
    _clash_for_linux_complete_command
    printf "%s\n" "${COMPREPLY[@]}"
  ' bash "$completion_file"
)"

if ! printf '%s\n' "$completion_output" | grep -Fxq update; then
  echo "not ok - clashsub should complete the update subcommand" >&2
  printf 'actual: %s\n' "$completion_output" >&2
  exit 1
fi

echo "ok - clashsub update is available in shell completion"
