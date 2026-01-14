[TOC]

# 项目介绍

此项目以 Clash Meta / Mihomo 内核为核心，提供自动识别架构并下载对应二进制的能力，同时通过 systemd 统一管理服务，配合清晰的目录结构，便于维护与回滚。基于脚本实现开箱即用的代理体验，主要用于解决服务器访问 GitHub 等海外资源速度慢的问题。
<br>

**2026.01.13**持续更新。

<br>

# 使用须知

- 支持普通用户运行，涉及 systemd 安装/端口转发等系统级操作时需要 root 或 sudo。
- 使用过程中如遇到问题，请优先查已有的 [issues](https://github.com/wanhebin/clash-for-linux/issues)。
- 在进行issues提交前，请替换提交内容中是敏感信息（例如：订阅地址）。
- 本项目是基于 [clash](https://github.com/Dreamacro/clash) 、[yacd](https://github.com/haishanh/yacd) 进行的配置整合，关于clash、yacd的详细配置请去原项目查看。
- 此项目不提供任何订阅信息，请自行准备Clash订阅地址。
- 运行前请手动更改`.env`文件中的`CLASH_URL`变量值，否则无法正常运行。
- 默认将管理面板仅绑定到本机（`127.0.0.1:9090`），如需对外访问请在`.env`中自行配置并确保`CLASH_SECRET`足够复杂。
- 默认开启 TLS 证书校验，若确需跳过校验请在`.env`中设置`ALLOW_INSECURE_TLS=true`（不推荐）。
- 如从旧版本升级，若存在 `/etc/profile.d/clash.sh` 请按需清理或改用新的 `/etc/profile.d/clash-for-linux.sh`。
- 当前在RHEL系列和Debian系列Linux系统中测试过，其他系列可能需要适当修改脚本。
- 内置 Clash 二进制支持 x86_64/aarch64/armv7，其它架构可自行放置二进制并通过 `CLASH_BIN` 指定路径。

> **注意**：当你在使用此项目时，遇到任何无法独自解决的问题请优先前往 [Issues](https://github.com/wanhebin/clash-for-linux/issues) 寻找解决方法。由于空闲时间有限，后续将不再对Issues中 “已经解答”、“已有解决方案” 的问题进行重复性的回答。

<br>

# 使用教程

## 下载项目

下载项目

```bash
$ git clone https://github.com/wnlen/clash-for-linux.git
```

进入到项目目录，编辑`.env`文件，修改变量`CLASH_URL`的值。

```bash
$ cd clash-for-linux
$ vim .env
```

> **注意：** `.env` 文件中的变量 `CLASH_SECRET` 为自定义 Clash Secret，值为空时，脚本将自动生成随机字符串。
> 如需使用其它架构，请将对应 Clash 二进制放入 `bin/` 并在 `.env` 中设置 `CLASH_BIN`，或命名为 `clash-linux-<arch>`（如 `clash-linux-riscv64`）。
> 端口支持设置为 `auto`，脚本会自动检测冲突并随机分配可用端口。

<br>

## 启动程序

直接运行脚本文件`start.sh`

- 进入项目目录

```bash
$ cd clash-for-linux
```

- 运行启动脚本

```bash
$ sudo bash start.sh

正在检测订阅地址...
Clash订阅地址可访问！                                      [  OK  ]

正在下载Clash配置文件...
配置文件config.yaml下载成功！                              [  OK  ]

正在启动Clash服务...
服务启动成功！                                             [  OK  ]

Clash Dashboard 访问地址：http://<ip>:9090/ui
Secret：xxxxxxxxxxxxx

请执行以下命令加载环境变量: source /etc/profile.d/clash-for-linux.sh

请执行以下命令开启系统代理: proxy_on

若要临时关闭系统代理，请执行: proxy_off

```

```bash
$ source /etc/profile.d/clash-for-linux.sh
$ proxy_on
```

<br>

## clashctl 命令

统一管理入口，支持启动/停止/重启/状态/更新/修改订阅：

```bash
$ sudo ./clashctl status
$ sudo ./clashctl start
$ sudo ./clashctl restart
$ sudo ./clashctl update
$ sudo ./clashctl set-url "https://example.com/your-subscribe"
```

订阅管理（多订阅）：

```bash
$ sudo ./clashctl sub add office "https://example.com/office" "User-Agent: ClashforWindows/0.20.39"
$ sudo ./clashctl sub add personal "https://example.com/personal"
$ sudo ./clashctl sub list
$ sudo ./clashctl sub use personal
$ sudo ./clashctl sub update
$ sudo ./clashctl sub log
```

安装脚本会将 `clashctl` 安装到 `/usr/local/bin/clashctl`，安装后可直接使用：

```bash
$ sudo clashctl status
```

<br>

## 一键安装/卸载

🚀 **一键安装（当前项目）**

当前项目支持一键安装，在终端中执行以下命令即可完成安装：

```bash
git clone --branch master --depth 1 https://github.com/wnlen/clash-for-linux.git \
  && cd clash-for-linux \
  && bash install.sh
```

脚本会自动识别安装路径、创建低权限用户、检测端口冲突，并根据架构自动下载 Clash 内核（可通过 `CLASH_DOWNLOAD_URL_TEMPLATE` 自定义下载地址）。

```bash
$ sudo bash install.sh
```

如需调整安装路径或服务行为，可使用以下环境变量：

- `CLASH_INSTALL_DIR`：默认 `/opt/clash-for-linux`
- `CLASH_SERVICE_USER` / `CLASH_SERVICE_GROUP`：systemd 运行用户/组
- `CLASH_ENABLE_SERVICE`：是否 `systemctl enable`（默认 `true`）
- `CLASH_START_SERVICE`：是否 `systemctl start`（默认 `true`）
- `CLASH_AUTO_DOWNLOAD`：是否自动下载 Clash 内核（默认 `auto`）
- `CLASH_DOWNLOAD_URL_TEMPLATE`：自定义下载模板（默认 `https://github.com/Dreamacro/clash/releases/latest/download/clash-{arch}.gz`）

卸载：

```bash
$ sudo bash uninstall.sh
```

- 检查服务端口

```bash
$ netstat -tln | grep -E '9090|789.'
tcp        0      0 127.0.0.1:9090          0.0.0.0:*               LISTEN     
tcp6       0      0 :::7890                 :::*                    LISTEN     
tcp6       0      0 :::7891                 :::*                    LISTEN     
tcp6       0      0 :::7892                 :::*                    LISTEN
```

- 检查环境变量

```bash
$ env | grep -E 'http_proxy|https_proxy'
http_proxy=http://127.0.0.1:7890
https_proxy=http://127.0.0.1:7890
```

以上步鄹如果正常，说明服务clash程序启动成功，现在就可以体验高速下载github资源了。

<br>

## 重启程序

如果需要对Clash配置进行修改，请修改 `conf/config.yaml` 文件。然后运行 `restart.sh` 脚本进行重启。

> **注意：**
> 重启脚本 `restart.sh` 不会更新订阅信息。

如需更新订阅并重启，可执行：

```bash
$ sudo bash restart.sh --update
```

## 更新订阅

如只需更新订阅配置但不重启服务，可执行：

```bash
$ sudo bash update.sh
```

如需通过订阅管理更新，可执行：

```bash
$ sudo clashctl sub update personal
```

<br>

## Mixin 配置

可通过 mixin 追加或覆盖 Clash 配置。默认读取 `conf/mixin.d` 下的 `.yaml/.yml` 文件（按文件名排序）。也可以通过 `.env` 设置指定路径：

```bash
export CLASH_MIXIN_PATHS='conf/mixin.d/base.yaml,conf/mixin.d/rules.yaml'
export CLASH_MIXIN_DIR='conf/mixin.d'
```

<br>

## Tun 模式

Tun 模式需要 Clash Premium/Meta 支持。可在 `.env` 中启用并配置：

```bash
export CLASH_TUN_ENABLE=true
export CLASH_TUN_STACK=system
export CLASH_TUN_AUTO_ROUTE=true
export CLASH_TUN_AUTO_REDIRECT=false
export CLASH_TUN_STRICT_ROUTE=false
export CLASH_TUN_DNS_HIJACK='any:53'
```

<br>

## 停止程序

- 进入项目目录

```bash
$ cd clash-for-linux
```

- 关闭服务

```bash
$ sudo bash shutdown.sh

服务关闭成功，请执行以下命令关闭系统代理：proxy_off

```

```bash
$ proxy_off
```

然后检查程序端口、进程以及环境变量`http_proxy|https_proxy`，若都没则说明服务正常关闭。

<br>

## systemd 服务

推荐使用自动安装脚本生成 systemd 单元（自动识别安装路径、创建低权限用户并修正目录权限）：

```bash
$ sudo bash scripts/install_systemd.sh
```

启用并启动服务：

```bash
$ sudo systemctl daemon-reload
$ sudo systemctl enable --now clash-for-linux.service
```

停止服务：

```bash
$ sudo systemctl stop clash-for-linux.service
```

> 如需自定义运行用户，可在执行脚本前设置 `CLASH_SERVICE_USER`（可选 `CLASH_SERVICE_GROUP`）。
> 默认使用 `clash` 用户运行服务，systemd 环境文件输出到 `temp/clash-for-linux.sh`。

如果需要手动安装，可参考 `systemd/clash-for-linux.service` 模板，并在 `/etc/default/clash-for-linux` 中设置 `CLASH_HOME`：

```bash
sudo cp systemd/clash-for-linux.env /etc/default/clash-for-linux
sudo vim /etc/default/clash-for-linux
```
也可以创建 `/etc/default/clash-for-linux` 并设置 `CLASH_HOME`，模板会自动读取该路径。


<br>

## subconverter 多架构支持

`subconverter` 用于将订阅内容转换为标准 clash 配置。默认会尝试以下位置：

- `tools/subconverter/subconverter`
- `tools/subconverter/subconverter-<arch>`
- `tools/subconverter/bin/subconverter-<arch>`

其中 `<arch>` 取值为：

- `linux-amd64`
- `linux-arm64`
- `linux-armv7`

自动下载默认使用 `https://github.com/tindy2013/subconverter/releases/latest/download/subconverter_{arch}.tar.gz`，
如果需要自定义来源或关闭下载，可以设置：

- `SUBCONVERTER_PATH`：指定自定义 `subconverter` 可执行文件路径。
- `SUBCONVERTER_AUTO_DOWNLOAD=false`：关闭自动下载（默认会尝试自动下载，需 `curl`/`wget`）。
- `SUBCONVERTER_DOWNLOAD_URL_TEMPLATE`：下载模板，使用 `{arch}` 占位符，如：

```bash
export SUBCONVERTER_AUTO_DOWNLOAD=true
export SUBCONVERTER_DOWNLOAD_URL_TEMPLATE='https://example.com/subconverter_{arch}.tar.gz'
```

当 `subconverter` 不可用时会自动跳过转换，并提示警告。


<br>

## Clash Dashboard

- 访问 Clash Dashboard

通过浏览器访问 `start.sh` 执行成功后输出的地址，例如：http://192.168.0.1:9090/ui

- 登录管理界面

在`API Base URL`一栏中输入：http://\<ip\>:9090 ，在`Secret(optional)`一栏中输入启动成功后输出的Secret。

点击Add并选择刚刚输入的管理界面地址，之后便可在浏览器上进行一些配置。

- 更多教程

此 Clash Dashboard 使用的是[yacd](https://github.com/haishanh/yacd)项目，详细使用方法请移步到yacd上查询。


<br>

## 设置代理
1. 开启 IP 转发

```bash
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

2.配置iptables
```bash
# 先清空旧规则
sudo iptables -t nat -F

# 允许本机访问代理端口
sudo iptables -t nat -A OUTPUT -p tcp --dport 7890 -j RETURN
sudo iptables -t nat -A OUTPUT -p tcp --dport 7891 -j RETURN
sudo iptables -t nat -A OUTPUT -p tcp --dport 7892 -j RETURN

# 让所有 TCP 流量通过 7892 代理
sudo iptables -t nat -A PREROUTING -p tcp -j REDIRECT --to-ports 7892

# 保存规则
sudo iptables-save | sudo tee /etc/iptables.rules
```

3. 让 iptables 规则开机生效
在 `/etc/rc.local`（或 `/etc/rc.d/rc.local`）加上：

```bash
#!/bin/bash
iptables-restore < /etc/iptables.rules
exit 0
```

```bash
sudo chmod +x /etc/rc.local
```


# 常见问题

1. 部分Linux系统默认的 shell `/bin/sh` 被更改为 `dash`，运行脚本会出现报错（报错内容一般会有 `-en [ OK ]`）。建议使用 `bash xxx.sh` 运行脚本。

2. 部分用户在UI界面找不到代理节点，基本上是因为厂商提供的clash配置文件是经过base64编码的，且配置文件格式不符合clash配置标准。

   目前此项目已集成自动识别和转换clash配置文件的功能。如果依然无法使用，则需要通过自建或者第三方平台（不推荐，有泄露风险）对订阅地址转换。
   
3. 程序日志中出现`error: unsupported rule type RULE-SET`报错，解决方法查看官方[WIKI](https://github.com/Dreamacro/clash/wiki/FAQ#error-unsupported-rule-type-rule-set)
