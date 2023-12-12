# 开启系统代理
function proxy_on
	export http_proxy=http://127.0.0.1:7890
	export https_proxy=http://127.0.0.1:7890
	export no_proxy=127.0.0.1,localhost
    export HTTP_PROXY=http://127.0.0.1:7890
    export HTTPS_PROXY=http://127.0.0.1:7890
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