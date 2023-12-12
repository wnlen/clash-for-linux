#!/bin/bash
# 该脚本的作用是获取Linux操作系统上运行的CPU架构信息，并将其输出到标准输出流。

function exitWithError {
    local errorMessage="$1"
    echo -e "\033[31m[ERROR] $errorMessage\033[0m" >&2
    exit 1
}

# Function to get CPU architecture
function get_cpu_arch {
    local commands=("$@")
    for cmd in "${commands[@]}"; do
        local CpuArch
        CpuArch=$(command -v $cmd >/dev/null && $cmd 2>/dev/null || type -p $cmd 2>/dev/null)
        if [[ -n "$CpuArch" ]]; then
            echo "$CpuArch"
            return
        fi
    done
}

# Check if we are running on a supported Linux distribution
if [[ -f "/etc/os-release" ]]; then
    . /etc/os-release
    case "$ID" in
        "ubuntu"|"debian"|"linuxmint")
            # Debian-based distributions
            CpuArch=$(get_cpu_arch "dpkg-architecture -qDEB_HOST_ARCH_CPU" "dpkg-architecture -qDEB_BUILD_ARCH_CPU" "uname -m")
            ;;
        "centos"|"fedora"|"rhel")
            # Red Hat-based distributions
            CpuArch=$(get_cpu_arch "uname -m" "arch" "uname")
            ;;
        *)
            # Unsupported Linux distribution
            CpuArch=$(get_cpu_arch "uname -m" "arch" "uname")
            if [[ -z "$CpuArch" ]]; then
                exitWithError "Failed to obtain CPU architecture"
            fi
            ;;
    esac
elif [[ -f "/etc/redhat-release" ]]; then
    # Older Red Hat-based distributions
    CpuArch=$(get_cpu_arch "uname -m" "arch" "uname")
else
    exitWithError "Unsupported Linux distribution"
fi

echo "CPU architecture: $CpuArch"
