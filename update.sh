#!/bin/bash

## Clash 订阅地址检测及配置文件下载
# 检查url是否有效
echo -e '\n正在检测订阅地址...'
Text1="Clash订阅地址可访问！"
Text2="Clash订阅地址不可访问！"
#curl -o /dev/null -s -m 10 --connect-timeout 10 -w %{http_code} $URL | grep '[23][0-9][0-9]' &>/dev/null
curl -o /dev/null -L -k -sS --retry 5 -m 10 --connect-timeout 10 -w "%{http_code}" $URL | grep -E '^[23][0-9]{2}$' &>/dev/null
ReturnStatus=$?
if_success $Text1 $Text2 $ReturnStatus

# 拉取更新config.yml文件
echo -e '\n正在下载Clash配置文件...'
Text3="配置文件config.yaml下载成功！"
Text4="配置文件config.yaml下载失败，退出启动！"

# 尝试使用curl进行下载
curl -L -k -sS --retry 5 -m 10 -o $Temp_Dir/clash.yaml $URL
ReturnStatus=$?
if [ $ReturnStatus -ne 0 ]; then
	# 如果使用curl下载失败，尝试使用wget进行下载
	for i in {1..10}
	do
		wget -q --no-check-certificate -O $Temp_Dir/clash.yaml $URL
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

# 合并形成新的config.yaml
cat $Temp_Dir/templete_config.yaml > $Temp_Dir/config.yaml
cat $Temp_Dir/proxy.txt >> $Temp_Dir/config.yaml
\cp $Temp_Dir/config.yaml $Conf_Dir/