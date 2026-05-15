function _clash_fish_project_dir
    if set -q CLASH_FOR_LINUX_PROJECT_DIR[1]
        echo $CLASH_FOR_LINUX_PROJECT_DIR
        return 0
    end

    set -l self (status --current-filename)
    if test -n "$self"; and test "$self" != "Standard input"
        set -l resolved (realpath "$self" 2>/dev/null)
        if test -z "$resolved"
            set resolved "$self"
        end
        dirname (dirname (dirname "$resolved"))
        return 0
    end

    pwd
end

function _clashctl_real
    if command -q clashctl-bin
        clashctl-bin $argv
        return $status
    end

    command clashctl $argv
end

function _clashctl_real_on
    set -l project_dir (_clash_fish_project_dir)
    set -l clashctl_script "$project_dir/scripts/core/clashctl.sh"

    if test -f "$clashctl_script"
        bash "$clashctl_script" on $argv
        return $status
    end

    _clashctl_real on $argv
end

function _clashctl_real_off
    set -l project_dir (_clash_fish_project_dir)
    set -l clashctl_script "$project_dir/scripts/core/clashctl.sh"

    if test -f "$clashctl_script"
        bash "$clashctl_script" off $argv
        return $status
    end

    _clashctl_real off $argv
end

function _clashctl_real_on_target
    set -l project_dir (_clash_fish_project_dir)
    set -l clashctl_script "$project_dir/scripts/core/clashctl.sh"

    if test -f "$clashctl_script"
        echo "bash $clashctl_script on"
    else
        echo "_clashctl_real on"
    end
end

function _clash_fish_state_file
    set -l project_dir (_clash_fish_project_dir)
    echo "$project_dir/runtime/shell-proxy.env"
end

function _clash_fish_runtime_config_file
    set -l project_dir (_clash_fish_project_dir)
    echo "$project_dir/runtime/config.yaml"
end

function _clash_fish_yq_bin
    set -l project_dir (_clash_fish_project_dir)
    echo "$project_dir/runtime/bin/yq"
end

function _clash_fish_set_persist_enabled
    set -l enabled "$argv[1]"
    set -l state_file (_clash_fish_state_file)
    set -l now (date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)

    mkdir -p (dirname "$state_file")
    printf 'SHELL_PROXY_PERSIST_ENABLED="%s"\nSHELL_PROXY_PERSIST_TIME="%s"\n' \
        "$enabled" "$now" >"$state_file"
end

function _clash_fish_persist_enabled
    set -l state_file (_clash_fish_state_file)
    test -f "$state_file"; or return 1

    set -l enabled (sed -nE 's/^SHELL_PROXY_PERSIST_ENABLED="?([^"\r\n]+)"?$/\1/p' "$state_file" | head -n 1)
    test "$enabled" = "true"
end

function _clash_fish_system_proxy_file
    if set -q SYSTEM_PROXY_ENV_FILE[1]
        echo $SYSTEM_PROXY_ENV_FILE
        return 0
    end

    set -l project_dir (_clash_fish_project_dir)
    set -l env_file "$project_dir/.env"
    if test -f "$env_file"
        set -l value (sed -nE 's/^[[:space:]]*(export[[:space:]]+)?SYSTEM_PROXY_ENV_FILE="?([^"#]+)"?[[:space:]]*$/\2/p' "$env_file" | tail -n 1)
        if test -n "$value"
            set value (string replace -a '$PROJECT_DIR' "$project_dir" "$value")
            set value (string replace -a '${PROJECT_DIR}' "$project_dir" "$value")
            echo "$value"
            return 0
        end
    end

    echo /etc/environment
end

function _clash_fish_export_proxy_values
    set -l http_url "$argv[1]"
    set -l https_url "$argv[2]"
    set -l all_url "$argv[3]"
    set -l no_proxy_value "$argv[4]"

    set -gx http_proxy "$http_url"
    set -gx https_proxy "$https_url"
    set -gx HTTP_PROXY "$http_url"
    set -gx HTTPS_PROXY "$https_url"
    set -gx all_proxy "$all_url"
    set -gx ALL_PROXY "$all_url"
    set -gx no_proxy "$no_proxy_value"
    set -gx NO_PROXY "$no_proxy_value"
end

function _clash_fish_export_system_proxy
    set -l proxy_file (_clash_fish_system_proxy_file)
    test -f "$proxy_file"; or return 1
    grep -Fq "# >>> clash-for-linux system proxy >>>" "$proxy_file" 2>/dev/null; or return 1

    set -l http_url (sed -nE 's/^http_proxy="?([^"\r\n]+)"?$/\1/p' "$proxy_file" | tail -n 1)
    set -l https_url (sed -nE 's/^https_proxy="?([^"\r\n]+)"?$/\1/p' "$proxy_file" | tail -n 1)
    set -l all_url (sed -nE 's/^all_proxy="?([^"\r\n]+)"?$/\1/p' "$proxy_file" | tail -n 1)
    set -l no_proxy_value (sed -nE 's/^NO_PROXY="?([^"\r\n]+)"?$/\1/p' "$proxy_file" | tail -n 1)
    if test -z "$no_proxy_value"
        set no_proxy_value (sed -nE 's/^no_proxy="?([^"\r\n]+)"?$/\1/p' "$proxy_file" | tail -n 1)
    end

    test -n "$http_url"; or return 1
    if test -z "$https_url"
        set https_url "$http_url"
    end
    if test -z "$all_url"
        set all_url (string replace 'http://' 'socks5://' "$http_url")
    end
    if test -z "$no_proxy_value"
        set no_proxy_value "127.0.0.1,localhost,::1"
    end

    _clash_fish_export_proxy_values "$http_url" "$https_url" "$all_url" "$no_proxy_value"
end

function _clash_fish_runtime_proxy_port
    set -l config_file (_clash_fish_runtime_config_file)
    test -s "$config_file"; or return 1

    set -l yq_bin (_clash_fish_yq_bin)
    set -l port
    if test -x "$yq_bin"
        set port ($yq_bin eval '.["mixed-port"] // .port // ""' "$config_file" 2>/dev/null | head -n 1)
    else
        set port (sed -nE 's/^[[:space:]]*(mixed-port|port):[[:space:]]*"?([0-9]+)"?[[:space:]]*$/\2/p' "$config_file" | head -n 1)
    end

    test -n "$port"; and test "$port" != "null"; or return 1
    echo "$port"
end

function _clash_fish_export_runtime_proxy
    set -l port (_clash_fish_runtime_proxy_port); or return $status
    set -l host 127.0.0.1
    if set -q CLASH_PROXY_HOST[1]
        set host $CLASH_PROXY_HOST
    end
    set -l no_proxy_value 127.0.0.1,localhost,::1
    if set -q NO_PROXY_DEFAULT[1]
        set no_proxy_value $NO_PROXY_DEFAULT
    end

    _clash_fish_export_proxy_values "http://$host:$port" "http://$host:$port" "socks5://$host:$port" "$no_proxy_value"
end

function _clash_fish_export_proxy
    _clash_fish_export_system_proxy; or _clash_fish_export_runtime_proxy
end

function _clash_fish_unset_shell_proxy
    set -e http_proxy
    set -e https_proxy
    set -e HTTP_PROXY
    set -e HTTPS_PROXY
    set -e all_proxy
    set -e ALL_PROXY
    set -e no_proxy
    set -e NO_PROXY
end

function _clash_fish_after_on
    _clash_fish_set_persist_enabled true
    _clash_fish_export_proxy
end

function _clash_fish_run_on
    set -l on_output (mktemp "$TMPDIR/clashon.XXXXXX" 2>/dev/null)
    if test -z "$on_output"
        set on_output (mktemp "/tmp/clashon.XXXXXX" 2>/dev/null)
    end
    if test -z "$on_output"
        echo "❗ 开启代理失败：无法创建临时输出文件" >&2
        return 1
    end

    set -l on_rc
    begin
        set -lx CLASH_ALIAS_CALL 1
        _clashctl_real_on $argv >"$on_output" 2>&1
        set on_rc $status
    end

    if test "$on_rc" -ne 0
        if _clash_fish_export_system_proxy
            echo "🚨 clashctl on 返回非 0，但系统代理已写入，继续同步当前 Shell（底层返回码：$on_rc）" >&2
            if test -s "$on_output"
                sed 's/^/  /' "$on_output" >&2
            end
        else
            echo "❗ 开启代理失败（底层返回码：$on_rc）" >&2
            if test -s "$on_output"
                sed 's/^/  /' "$on_output" >&2
            else
                echo "  底层命令没有输出错误详情："(_clashctl_real_on_target) >&2
            end
            rm -f "$on_output" 2>/dev/null
            return "$on_rc"
        end
    else
        cat "$on_output"
    end

    rm -f "$on_output" 2>/dev/null

    _clash_fish_after_on
    set -l sync_rc $status
    if test "$sync_rc" -ne 0
        echo "❗ 开启代理失败：当前 Fish 代理环境同步失败（返回码：$sync_rc）" >&2
        return "$sync_rc"
    end
end

function _clash_fish_run_off
    _clash_fish_unset_shell_proxy
    _clash_fish_set_persist_enabled false
    _clashctl_real_off $argv
end

function _clash_fish_auto_restore_proxy
    _clash_fish_persist_enabled; or return 0
    _clash_fish_export_proxy; or return 0
end

function clashctl
    set -l cmd
    if set -q argv[1]
        set cmd $argv[1]
    end

    switch "$cmd"
        case on
            _clash_fish_run_on $argv[2..-1]
        case off
            _clash_fish_run_off $argv[2..-1]
        case proxy
            set -l subcmd
            if set -q argv[2]
                set subcmd $argv[2]
            end
            switch "$subcmd"
                case on
                    _clash_fish_export_proxy
                case off
                    _clash_fish_run_off $argv[3..-1]
                case '*'
                    _clashctl_real $argv
            end
        case ui
            _clashctl_real ui $argv[2..-1]
        case status
            _clashctl_real status $argv[2..-1]
        case '*'
            _clashctl_real $argv
    end
end

function clashon
    clashctl on $argv
end

function clashoff
    clashctl off $argv
end

function clashproxy
    set -l subcmd show
    if set -q argv[1]
        set subcmd $argv[1]
    end

    switch "$subcmd"
        case on
            clashctl proxy on
        case off
            clashctl off
        case show status
            clashctl proxy show
        case groups
            clashctl proxy groups
        case current nodes select
            clashctl proxy $argv
        case '*'
            echo "📜 用法：clashproxy [show|on|off|groups|current|nodes|select]"
            echo "💡 主路径切节点请使用：clashselect 或 clashctl select"
            return 2
    end
end

function clashls
    clashctl ls $argv
end

function clashselect
    clashctl select $argv
end

function clashui
    clashctl ui $argv
end

function clashsecret
    clashctl secret $argv
end

function clashtun
    clashctl tun $argv
end

function clashrelay
    clashctl relay $argv
end

function clashupgrade
    clashctl upgrade $argv
end

function clashmixin
    set -l subcmd
    if set -q argv[1]
        set subcmd $argv[1]
    end

    switch "$subcmd"
        case -e --edit
            clashctl mixin edit
        case -c --raw
            clashctl mixin raw
        case -r --runtime
            clashctl mixin runtime
        case ''
            clashctl mixin
        case '*'
            clashctl mixin $argv
    end
end

_clash_fish_auto_restore_proxy
