#!/bin/bash

Server_Dir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
fish_func_path=$Server_Dir/scripts/functions.fish
bash_func_path=$Server_Dir/scripts/functions.bash

# 获取当前用户默认的shell解释器路径
default_shell=$(getent passwd "$USER" | awk -F: '{print $7}')

# 提取shell解释器的名称
shell_name=$(basename "$default_shell")

if [ "$shell_name" = "fish" ]; then
	if ! grep -q "$fish_func_path" ~/.config/fish/config.fish; then
		echo "source $fish_func_path" >> ~/.config/fish/config.fish
	fi
elif [ "$shell_name" = "bash" ]; then
	if ! grep -q "$bash_func_path" ~/.bashrc; then
		echo "source $bash_func_path" >> ~/.bashrc
	fi
elif [ "$shell_name" = "zsh" ]; then
	if ! grep -q "$bash_func_path" ~/.zshrc; then
		echo "source $bash_func_path" >> ~/.zshrc
	fi
fi

echo -e "环境变量已注入\n"
echo -e "请执行以下命令开启系统代理: proxy_on\n"
echo -e "若要临时关闭系统代理，请执行: proxy_off\n"
