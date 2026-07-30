#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../core/common.sh
source "$PROJECT_DIR/scripts/core/common.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_bin="$tmp_dir/bin"
mkdir -p "$fixture_bin"

command_install_dir() { printf '%s\n' "$fixture_bin"; }
ensure_command_install_dir_in_shell_path() { :; }
remove_alias_command_wrappers() { :; }

install_clashctl_entry

for command_name in clash clashctl clashctl-bin; do
  if [ ! -x "$fixture_bin/$command_name" ]; then
    echo "not ok - install should create $command_name" >&2
    exit 1
  fi
done

primary_help="$("$fixture_bin/clash" --help)"
compat_help="$("$fixture_bin/clashctl" --help)"

if ! printf '%s\n' "$primary_help" | grep -Fq "clash <command>"; then
  echo "not ok - clash help should use the primary command name" >&2
  exit 1
fi

if [ "$compat_help" != "$primary_help" ]; then
  echo "not ok - clashctl should remain compatible with clash" >&2
  exit 1
fi

completion_output="$(
  "$fixture_bin/clash" completion bash
)"

if ! printf '%s\n' "$completion_output" | grep -Eq '^[[:space:]]*complete -F _clash_for_linux_complete_command clash$'; then
  echo "not ok - completion should register the clash command" >&2
  exit 1
fi

primary_completion="$(
  bash --noprofile --norc -c '
    CLASH_FOR_LINUX_CLASH_ENTRY_MANAGED=true
    source "$1"
    COMP_WORDS=(clash st)
    COMP_CWORD=1
    _clash_for_linux_complete_command
    printf "%s\n" "${COMPREPLY[@]}"
  ' bash <(printf '%s\n' "$completion_output")
)"

if ! printf '%s\n' "$primary_completion" | grep -Fxq status; then
  echo "not ok - clash should complete top-level commands" >&2
  exit 1
fi

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*"' > "$fixture_bin/clashctl-bin"
chmod +x "$fixture_bin/clashctl-bin"

shell_output="$(
  PATH="$fixture_bin:/usr/bin:/bin" \
  CLASH_FOR_LINUX_CLASH_ENTRY_MANAGED=true \
  bash --noprofile --norc -c \
    'source "$1"; clash status' \
    bash "$PROJECT_DIR/scripts/core/alias.sh"
)"

if [ "$shell_output" != "status" ]; then
  echo "not ok - clash shell function should delegate to the shared command path" >&2
  printf 'actual: %s\n' "$shell_output" >&2
  exit 1
fi

remove_clashctl_entry

for command_name in clash clashctl clashctl-bin; do
  if [ -e "$fixture_bin/$command_name" ]; then
    echo "not ok - uninstall should remove managed $command_name" >&2
    exit 1
  fi
done

printf '%s\n' '#!/usr/bin/env bash' 'echo foreign-clash' > "$fixture_bin/clash"
chmod +x "$fixture_bin/clash"

install_clashctl_entry >/dev/null 2>&1

if [ "$("$fixture_bin/clash")" != "foreign-clash" ]; then
  echo "not ok - install should not overwrite an existing foreign clash command" >&2
  exit 1
fi

remove_clashctl_entry

if [ "$("$fixture_bin/clash")" != "foreign-clash" ]; then
  echo "not ok - uninstall should preserve an existing foreign clash command" >&2
  exit 1
fi

other_bin="$tmp_dir/other-bin"
foreign_bin="$tmp_dir/foreign-bin"
mkdir -p "$other_bin" "$foreign_bin"
printf '%s\n' '#!/usr/bin/env bash' 'echo foreign-path-clash' > "$foreign_bin/clash"
chmod +x "$foreign_bin/clash"

command_install_dir() { printf '%s\n' "$other_bin"; }
PATH="$foreign_bin:/usr/bin:/bin" install_clashctl_entry >/dev/null 2>&1

if [ -e "$other_bin/clash" ]; then
  echo "not ok - install should not shadow a foreign clash command elsewhere in PATH" >&2
  exit 1
fi

remove_clashctl_entry

echo "ok - clash is primary, clashctl stays compatible, and foreign commands are preserved"
