#!/bin/bash

# 关闭clash服务
PID_NUM=`ps -ef | grep [c]lash-linux-a | wc -l`
PID=`ps -ef | grep [c]lash-linux-a | awk '{print $2}'`
if [ $PID_NUM -ne 0 ]; then
	kill -9 $PID
	# ps -ef | grep [c]lash-linux-a | awk '{print $2}' | xargs kill -9
fi

# 清除环境变量
> /etc/profile.d/clash.sh

# 检查并关闭系统托盘图标
PID_NUM=`ps -ef | grep [y]ad | grep -i clash | wc -l`
PID=`ps -ef | grep [y]ad | grep -i clash | awk '{print $2}'`
if [ $PID_NUM -ne 0 ]; then
    kill -9 $PID
    echo -e "\n[INFO] 已移除系统托盘图标"
fi

echo -e "\n服务关闭成功，请执行以下命令关闭系统代理：proxy_off\n"
