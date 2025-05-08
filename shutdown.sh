#!/bin/bash

# 初始化跳过编辑profile标志
SKIP_EDIT_PROFILE=false

# 处理命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-edit-profile)
            SKIP_EDIT_PROFILE=true
            shift
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# 关闭clash服务
PID_NUM=`ps -ef | grep [c]lash-linux-a | wc -l`
PID=`ps -ef | grep [c]lash-linux-a | awk '{print $2}'`
if [ $PID_NUM -ne 0 ]; then
	kill -9 $PID
	# ps -ef | grep [c]lash-linux-a | awk '{print $2}' | xargs kill -9
fi

# 清除环境变量
if [ "$SKIP_EDIT_PROFILE" = false ]; then
    if [ "$(id -u)" -eq 0 ]; then
        > /etc/profile.d/clash.sh
    else
        echo "错误：需要 root 权限才能修改 /etc/profile.d/clash.sh" >&2
    fi
fi

# 检查并关闭系统托盘图标
PID_NUM=`ps -ef | grep [y]ad | grep -i clash | wc -l`
PID=`ps -ef | grep [y]ad | grep -i clash | awk '{print $2}'`
if [ $PID_NUM -ne 0 ]; then
    kill -9 $PID
    echo -e "\n[INFO] 已移除系统托盘图标"
fi

echo -e "\n服务关闭成功，请执行以下命令关闭系统代理：proxy_off\n"
