#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/runtime/bin" "$tmp_dir/runtime/tmp" "$tmp_dir/config" "$tmp_dir/logs"
cp "$PROJECT_DIR/runtime/bin/yq" "$tmp_dir/runtime/bin/yq"

export PROJECT_DIR
export RUNTIME_DIR="$tmp_dir/runtime"
export BIN_DIR="$tmp_dir/runtime/bin"
export LOG_DIR="$tmp_dir/logs"
export CONFIG_DIR="$tmp_dir/config"

# shellcheck source=scripts/core/config.sh
source "$PROJECT_DIR/scripts/core/config.sh"
# shellcheck source=scripts/core/proxy.sh
source "$PROJECT_DIR/scripts/core/proxy.sh"

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$actual" != "$expected" ]; then
    echo "not ok - $name: got '$actual', expected '$expected'" >&2
    return 1
  fi

  echo "ok - $name"
}

mixin_add_rule prepend "DOMAIN-SUFFIX,example.com,DIRECT" >/dev/null
mixin_add_rule prepend "DOMAIN-SUFFIX,example.com,DIRECT" >/dev/null
mixin_add_rule append "MATCH,节点选择" >/dev/null

mixin_yaml="$(mixin_file)"
cat > "$RUNTIME_DIR/config.yaml" <<'YAML'
rules:
  - DOMAIN-SUFFIX,example.com,DIRECT
  - DOMAIN,base.example,节点选择
  - MATCH,节点选择
YAML

assert_eq "normalizes rule test target" "api.example.com" "$(rule_test_target_host "https://API.EXAMPLE.COM:443/path?q=1")"
assert_eq "matches suffix rule" "$(printf '0\tDOMAIN-SUFFIX,example.com,DIRECT\tDIRECT')" "$(rule_match_for_target "api.example.com")"
assert_eq "matches exact rule" "$(printf '1\tDOMAIN,base.example,节点选择\t节点选择')" "$(rule_match_for_target "base.example")"
assert_eq "matches fallback rule" "$(printf '2\tMATCH,节点选择\t节点选择')" "$(rule_match_for_target "other.test")"

assert_eq "deduplicates prepend rules" "1" "$("$BIN_DIR/yq" eval '(.prepend.rules // []) | length' "$mixin_yaml")"
assert_eq "writes prepend rule" "DOMAIN-SUFFIX,example.com,DIRECT" "$("$BIN_DIR/yq" eval '.prepend.rules[0]' "$mixin_yaml")"
assert_eq "writes append rule" "MATCH,节点选择" "$("$BIN_DIR/yq" eval '.append.rules[0]' "$mixin_yaml")"
assert_eq "lists rules" "2" "$(mixin_rules_list | wc -l | tr -d ' ')"
assert_eq "lists runtime rules" "3" "$(runtime_rules_list | wc -l | tr -d ' ')"
assert_eq "marks runtime custom rules" "$(printf 'prepend\t0\tDOMAIN-SUFFIX,example.com,DIRECT\nruntime\t-\tDOMAIN,base.example,节点选择\nappend\t0\tMATCH,节点选择')" "$(current_rules_list)"

"$BIN_DIR/yq" eval -i '.prepend.rules = [] | .append.rules = []' "$mixin_yaml"
assert_eq "lists runtime rules without custom rules" "3" "$(current_rules_list | wc -l | tr -d ' ')"

mixin_remove_rule_at append 0 >/dev/null
assert_eq "removes append rule" "0" "$("$BIN_DIR/yq" eval '(.append.rules // []) | length' "$mixin_yaml")"

cat > "$RUNTIME_DIR/config.yaml" <<'YAML'
rules:
  - DOMAIN-SUFFIX,example.com,DIRECT
  - DOMAIN,base.example,节点选择
  - MATCH,节点选择
YAML
mixin_remove_runtime_rule "DOMAIN,base.example,节点选择" >/dev/null
assert_eq "writes removed runtime rule" "DOMAIN,base.example,节点选择" "$("$BIN_DIR/yq" eval '.remove.rules[0]' "$mixin_yaml")"
apply_mixin_remove_arrays "$RUNTIME_DIR/config.yaml"
assert_eq "filters removed runtime rule" "0" "$(runtime_rules_list | awk -F '\t' '$2 == "DOMAIN,base.example,节点选择" { count++ } END { print count + 0 }')"
mixin_add_rule append "DOMAIN,base.example,节点选择" >/dev/null
assert_eq "adding removed rule clears remove marker" "0" "$("$BIN_DIR/yq" eval '(.remove.rules // []) | length' "$mixin_yaml")"
mixin_add_rule prepend "DOMAIN,base.example,节点选择" >/dev/null
assert_eq "moves rule to prepend" "DOMAIN,base.example,节点选择" "$("$BIN_DIR/yq" eval '.prepend.rules[0]' "$mixin_yaml")"
assert_eq "removes moved rule from append" "0" "$("$BIN_DIR/yq" eval '(.append.rules // []) | length' "$mixin_yaml")"

assert_eq "green delay label" "$(printf '\033[32m[80ms]\033[0m')" "$(proxy_delay_label 80)"
assert_eq "yellow delay label" "$(printf '\033[33m[180ms]\033[0m')" "$(proxy_delay_label 180)"
assert_eq "red delay label" "$(printf '\033[31m[450ms]\033[0m')" "$(proxy_delay_label 450)"
assert_eq "empty delay label" "[-]" "$(proxy_delay_label 0)"

proxy_node_test_delay() {
  case "$1" in
    node-a) echo 10 ;;
    node-b) echo 20 ;;
    *) echo 0 ;;
  esac
}
assert_eq "parallel delay map" "$(printf 'node-a\t10\nnode-b\t20')" "$(proxy_nodes_test_delay_map 2 node-a node-b | sort)"
