#!/bin/bash

echo -e "Run this with root permission!\n"

# 添加环境变量(root权限)
cat>/etc/profile.d/clash.fish<<EOF
# 开启系统代理
function proxy_on
	export http_proxy=http://127.0.0.1:7890
	#export https_proxy=http://127.0.0.1:7890
	export no_proxy=127.0.0.1,localhost
    	export HTTP_PROXY=http://127.0.0.1:7890
    	#export HTTPS_PROXY=http://127.0.0.1:7890
 	export NO_PROXY=127.0.0.1,localhost
	echo -e "\033[32m[√] 已开启代理\033[0m"
end

# 关闭系统代理
function proxy_off
	set -e http_proxy
	set -e https_proxy
	set -e no_proxy
  	set -e HTTP_PROXY
	set -e HTTPS_PROXY
	set -e NO_PROXY
	echo -e "\033[31m[×] 已关闭代理\033[0m"
end
EOF

echo -e "请执行以下命令加载环境变量: source /etc/profile.d/clash.fish\n"
echo -e "请执行以下命令开启系统代理: proxy_on\n"
echo -e "若要临时关闭系统代理，请执行: proxy_off\n"
