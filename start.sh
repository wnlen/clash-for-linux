#!/bin/bash

# 加载系统函数库(Only for RHEL Linux)
# [ -f /etc/init.d/functions ] && source /etc/init.d/functions

#################### 脚本初始化任务 ####################

# 获取脚本工作目录绝对路径
export Server_Dir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)

# 加载.env变量文件
source $Server_Dir/.env

# 给二进制启动程序、脚本等添加可执行权限
chmod +x $Server_Dir/bin/*
chmod +x $Server_Dir/scripts/*
chmod +x $Server_Dir/tools/subconverter/subconverter



#################### 变量设置 ####################

Conf_Dir="$Server_Dir/conf"
Temp_Dir="$Server_Dir/temp"
Log_Dir="$Server_Dir/logs"

# 将 CLASH_URL 变量的值赋给 URL 变量，并检查 CLASH_URL 是否为空
URL=${CLASH_URL:?Error: CLASH_URL variable is not set or empty}

# 获取 CLASH_SECRET 值，如果不存在则生成一个随机数
Secret=${CLASH_SECRET:-$(openssl rand -hex 32)}

# 设置默认值
CLASH_HTTP_PORT=${CLASH_HTTP_PORT:-7890}
CLASH_SOCKS_PORT=${CLASH_SOCKS_PORT:-7891}
CLASH_REDIR_PORT=${CLASH_REDIR_PORT:-7892}
CLASH_LISTEN_IP=${CLASH_LISTEN_IP:-0.0.0.0}
CLASH_ALLOW_LAN=${CLASH_ALLOW_LAN:-true}
EXTERNAL_CONTROLLER_ENABLED=${EXTERNAL_CONTROLLER_ENABLED:-true}
EXTERNAL_CONTROLLER=${EXTERNAL_CONTROLLER:-0.0.0.0:9090}



#################### 函数定义 ####################

# 自定义action函数，实现通用action功能
success() {
	echo -en "\\033[60G[\\033[1;32m  OK  \\033[0;39m]\r"
	return 0
}

failure() {
	local rc=$?
	echo -en "\\033[60G[\\033[1;31mFAILED\\033[0;39m]\r"
	[ -x /bin/plymouth ] && /bin/plymouth --details
	return $rc
}

action() {
	local STRING rc

	STRING=$1
	echo -n "$STRING "
	shift
	"$@" && success $"$STRING" || failure $"$STRING"
	rc=$?
	echo
	return $rc
}

# 判断命令是否正常执行 函数
if_success() {
	local ReturnStatus=$3
	if [ $ReturnStatus -eq 0 ]; then
		action "$1" /bin/true
	else
		action "$2" /bin/false
		exit 1
	fi
}



#################### 任务执行 ####################

## 获取CPU架构信息
# Source the script to get CPU architecture
source $Server_Dir/scripts/get_cpu_arch.sh

# Check if we obtained CPU architecture
if [[ -z "$CpuArch" ]]; then
	echo "Failed to obtain CPU architecture"
	exit 1
fi


## 临时取消环境变量
unset http_proxy
unset https_proxy
unset no_proxy
unset HTTP_PROXY
unset HTTPS_PROXY
unset NO_PROXY


## Clash 订阅地址检测及配置文件下载
# 检查url是否有效
echo -e '\n正在检测订阅地址...'
Text1="Clash订阅地址可访问！"
Text2="Clash订阅地址不可访问！"

# 构建检测 curl 命令，添加自定义请求头
CHECK_CMD="curl -o /dev/null -L -k -sS --retry 5 -m 10 --connect-timeout 10 -w \"%{http_code}\""
if [ -n "$CLASH_HEADERS" ]; then
	CHECK_CMD="$CHECK_CMD -H '$CLASH_HEADERS'"
fi
CHECK_CMD="$CHECK_CMD $URL"

# 检查订阅地址
eval $CHECK_CMD | grep -E '^[23][0-9]{2}$' &>/dev/null
ReturnStatus=$?
if_success $Text1 $Text2 $ReturnStatus

# 拉取更新config.yml文件
echo -e '\n正在下载Clash配置文件...'
Text3="配置文件config.yaml下载成功！"
Text4="配置文件config.yaml下载失败，退出启动！"

# 构建 curl 命令，添加自定义请求头
CURL_CMD="curl -L -k -sS --retry 5 -m 10 -o $Temp_Dir/clash.yaml"
if [ -n "$CLASH_HEADERS" ]; then
	CURL_CMD="$CURL_CMD -H '$CLASH_HEADERS'"
fi
CURL_CMD="$CURL_CMD $URL"

# 尝试使用curl进行下载
eval $CURL_CMD
ReturnStatus=$?
if [ $ReturnStatus -ne 0 ]; then
	# 如果使用curl下载失败，尝试使用wget进行下载
	WGET_CMD="wget -q --no-check-certificate -O $Temp_Dir/clash.yaml"
	if [ -n "$CLASH_HEADERS" ]; then
		WGET_CMD="$WGET_CMD --header='$CLASH_HEADERS'"
	fi
	WGET_CMD="$WGET_CMD $URL"
	
	for i in {1..10}
	do
		eval $WGET_CMD
		ReturnStatus=$?
		if [ $ReturnStatus -eq 0 ]; then
			break
		else
			continue
		fi
	done
fi
if_success $Text3 $Text4 $ReturnStatus

# 重命名clash配置文件
\cp -a $Temp_Dir/clash.yaml $Temp_Dir/clash_config.yaml


## 判断订阅内容是否符合clash配置文件标准，尝试转换（当前不支持对 x86_64 以外的CPU架构服务器进行clash配置文件检测和转换，此功能将在后续添加）
if [[ $CpuArch =~ "x86_64" || $CpuArch =~ "amd64"  ]]; then
	echo -e '\n判断订阅内容是否符合clash配置文件标准:'
	bash $Server_Dir/scripts/clash_profile_conversion.sh
	sleep 3
fi


## Clash 配置文件重新格式化及配置
# 取出代理相关配置 
#sed -n '/^proxies:/,$p' $Temp_Dir/clash.yaml > $Temp_Dir/proxy.txt
sed -n '/^proxies:/,$p' $Temp_Dir/clash_config.yaml > $Temp_Dir/proxy.txt

# 合并形成新的config.yaml，并替换配置占位符
cat $Temp_Dir/templete_config.yaml > $Temp_Dir/config.yaml
cat $Temp_Dir/proxy.txt >> $Temp_Dir/config.yaml

# 替换配置文件中的占位符为环境变量值
sed -i "s/CLASH_HTTP_PORT_PLACEHOLDER/${CLASH_HTTP_PORT}/g" $Temp_Dir/config.yaml
sed -i "s/CLASH_SOCKS_PORT_PLACEHOLDER/${CLASH_SOCKS_PORT}/g" $Temp_Dir/config.yaml
sed -i "s/CLASH_REDIR_PORT_PLACEHOLDER/${CLASH_REDIR_PORT}/g" $Temp_Dir/config.yaml
sed -i "s/CLASH_LISTEN_IP_PLACEHOLDER/${CLASH_LISTEN_IP}/g" $Temp_Dir/config.yaml
sed -i "s/CLASH_ALLOW_LAN_PLACEHOLDER/${CLASH_ALLOW_LAN}/g" $Temp_Dir/config.yaml

# 配置 external-controller
if [ "$EXTERNAL_CONTROLLER_ENABLED" = "true" ]; then
	sed -i "s/EXTERNAL_CONTROLLER_PLACEHOLDER/${EXTERNAL_CONTROLLER}/g" $Temp_Dir/config.yaml
else
	# 如果禁用 external-controller，则注释掉该行
	sed -i "s/external-controller: 'EXTERNAL_CONTROLLER_PLACEHOLDER'/# external-controller: disabled/g" $Temp_Dir/config.yaml
fi

\cp $Temp_Dir/config.yaml $Conf_Dir/

# Configure Clash Dashboard
Work_Dir=$(cd $(dirname $0); pwd)
Dashboard_Dir="${Work_Dir}/dashboard/public"
if [ "$EXTERNAL_CONTROLLER_ENABLED" = "true" ]; then
	sed -ri "s@^# external-ui:.*@external-ui: ${Dashboard_Dir}@g" $Conf_Dir/config.yaml
fi
sed -r -i '/^secret: /s@(secret: ).*@\1'${Secret}'@g' $Conf_Dir/config.yaml


## 启动Clash服务
echo -e '\n正在启动Clash服务...'
Text5="服务启动成功！"
Text6="服务启动失败！"
if [[ $CpuArch =~ "x86_64" || $CpuArch =~ "amd64"  ]]; then
	nohup $Server_Dir/bin/clash-linux-amd64 -d $Conf_Dir &> $Log_Dir/clash.log &
	ReturnStatus=$?
	if_success $Text5 $Text6 $ReturnStatus
elif [[ $CpuArch =~ "aarch64" ||  $CpuArch =~ "arm64" ]]; then
	nohup $Server_Dir/bin/clash-linux-arm64 -d $Conf_Dir &> $Log_Dir/clash.log &
	ReturnStatus=$?
	if_success $Text5 $Text6 $ReturnStatus
elif [[ $CpuArch =~ "armv7" ]]; then
	nohup $Server_Dir/bin/clash-linux-armv7 -d $Conf_Dir &> $Log_Dir/clash.log &
	ReturnStatus=$?
	if_success $Text5 $Text6 $ReturnStatus
else
	echo -e "\033[31m\n[ERROR] Unsupported CPU Architecture！\033[0m"
	exit 1
fi

# Output Dashboard access address and Secret
echo ''
if [ "$EXTERNAL_CONTROLLER_ENABLED" = "true" ]; then
	echo -e "Clash Dashboard 访问地址: http://${EXTERNAL_CONTROLLER}/ui"
	echo -e "Secret: ${Secret}"
else
	echo -e "External Controller (Dashboard) 已禁用"
fi
echo ''

# 添加环境变量(root权限) - 使用配置的端口
cat>/etc/profile.d/clash.sh<<EOF
# 开启系统代理
function proxy_on() {
	export http_proxy=http://${CLASH_LISTEN_IP}:${CLASH_HTTP_PORT}
	export https_proxy=http://${CLASH_LISTEN_IP}:${CLASH_HTTP_PORT}
	export no_proxy=127.0.0.1,localhost
    	export HTTP_PROXY=http://${CLASH_LISTEN_IP}:${CLASH_HTTP_PORT}
    	export HTTPS_PROXY=http://${CLASH_LISTEN_IP}:${CLASH_HTTP_PORT}
 	export NO_PROXY=127.0.0.1,localhost
	echo -e "\033[32m[√] 已开启代理\033[0m"
}

# 关闭系统代理
function proxy_off(){
	unset http_proxy
	unset https_proxy
	unset no_proxy
  	unset HTTP_PROXY
	unset HTTPS_PROXY
	unset NO_PROXY
	echo -e "\033[31m[×] 已关闭代理\033[0m"
}
EOF

echo -e "请执行以下命令加载环境变量: source /etc/profile.d/clash.sh\n"
echo -e "请执行以下命令开启系统代理: proxy_on\n"
echo -e "若要临时关闭系统代理，请执行: proxy_off\n"