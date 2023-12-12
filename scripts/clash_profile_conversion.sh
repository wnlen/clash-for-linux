#!/bin/bash

# 加载clash配置文件内容
raw_content=$(cat ${Server_Dir}/temp/clash.yaml)

# 判断订阅内容是否符合clash配置文件标准
#if echo "$raw_content" | jq 'has("proxies") and has("proxy-groups") and has("rules")' 2>/dev/null; then
if echo "$raw_content" | awk '/^proxies:/{p=1} /^proxy-groups:/{g=1} /^rules:/{r=1} p&&g&&r{exit} END{if(p&&g&&r) exit 0; else exit 1}'; then
  echo "订阅内容符合clash标准"
  echo "$raw_content" > ${Server_Dir}/temp/clash_config.yaml
else
  # 判断订阅内容是否为base64编码
  if echo "$raw_content" | base64 -d &>/dev/null; then
    # 订阅内容为base64编码，进行解码
    decoded_content=$(echo "$raw_content" | base64 -d)

    # 判断解码后的内容是否符合clash配置文件标准
    #if echo "$decoded_content" | jq 'has("proxies") and has("proxy-groups") and has("rules")' 2>/dev/null; then
    if echo "$decoded_content" | awk '/^proxies:/{p=1} /^proxy-groups:/{g=1} /^rules:/{r=1} p&&g&&r{exit} END{if(p&&g&&r) exit 0; else exit 1}'; then
      echo "解码后的内容符合clash标准"
      echo "$decoded_content" > ${Server_Dir}/temp/clash_config.yaml
    else
      echo "解码后的内容不符合clash标准，尝试将其转换为标准格式"
      ${Server_Dir}/tools/subconverter/subconverter -g &>> ${Server_Dir}/logs/subconverter.log
      converted_file=${Server_Dir}/temp/clash_config.yaml
      # 判断转换后的内容是否符合clash配置文件标准
      if awk '/^proxies:/{p=1} /^proxy-groups:/{g=1} /^rules:/{r=1} p&&g&&r{exit} END{if(p&&g&&r) exit 0; else exit 1}' $converted_file; then
        echo "配置文件已成功转换成clash标准格式"
      else
        echo "配置文件转换标准格式失败"
	exit 1
      fi
    fi
  else
    echo "订阅内容不符合clash标准，无法转换为配置文件"
    exit 1
  fi
fi
