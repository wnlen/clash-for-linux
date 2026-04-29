<h1 align="center">
  🐧 Clash for Linux TUI
  <br>
</h1>

<p align="center">
  基于 <a href="https://github.com/wnlen/clash-for-linux">wnlen/clash-for-linux</a> 改进，新增交互式 TUI 仪表盘
</p>

<h3 align="center">
一个更完整、更优雅的 Linux Clash / <a href="https://github.com/MetaCubeX/mihomo">Mihomo</a> 运行平台。
</h3>

<p align="center">
  <img src="resources/shell.png" width="100%">
</p>

## 🔀 Fork 说明

本项目 Fork 自 [wnlen/clash-for-linux](https://github.com/wnlen/clash-for-linux)，在原项目基础上新增了以下改进：

- **交互式 TUI 仪表盘** — 基于 [gum](https://github.com/charmbracelet/gum) 构建的终端控制台，一条命令 `clashctl tui` 即可进入全功能可视化管理界面
- **节点延迟测速** — 支持并发测速所有节点，实时显示延迟数据并按延迟排序
- **节点名称 Unicode 兼容** — 修复了含 emoji / 中文的策略组和节点名在 API 调用中的编码问题

> 上游仓库的所有功能均完整保留，TUI 为增量功能，不影响原有命令行操作方式。

------

# ✨ 核心特性

- 🖥️ **TUI 仪表盘**：终端内全功能可视化控制台（`clashctl tui`）
- 🚀 **自动识别系统架构**：自动下载并使用对应 Clash 内核
- 🧪 **端口自动检测与分配**：避免冲突
- 🔄 **多订阅管理**：可以保存多个订阅，通过 `clashctl use` 切换当前主订阅。
- 💫 **节点选择**：使用编号交互选择策略组和节点。
- 🌐 **Tun 模式**：用于透明代理接管场景。
- 🧠 **Mixin 机制**：可按需追加/覆盖 Clash 配置
- 👤 **不同权限**：兼容 `root` 与普通用户环境。
- 🔐 **安全默认配置**：自动生成或自定义 Secret
- 🩺 **内置诊断工具（`doctor`）**：快速排障

### 适用场景

- Linux 云服务器（VPS / 远程开发环境）
- 本地开发环境（Ubuntu / Debian / WSL）
- 路由 / 轻量系统（OpenWrt / NAS / 小主机 x86 / ARM）
- 需要稳定访问 GitHub、Go / Node / Docker 生态的开发者
- 不希望手动维护 Clash 运行状态的用户

------

# 🖥️ TUI 仪表盘

通过 `clashctl tui` 进入交互式终端控制台，无需记忆命令即可管理所有功能。

### 启动方式

```bash
clashctl tui
```

### 主界面

TUI 启动后会显示状态面板和功能菜单：

<!-- TODO: 替换为真实截图 -->
<!-- <p align="center"><img src="resources/tui-main.png" width="80%"></p> -->

```
╔══════════════════════════════════════╗
║       🐱 Clash TUI 控制台            ║
╚══════════════════════════════════════╝

╭──────────────────────────────────────╮
│ ✅ 代理状态：已运行                    │
│ 📡 当前订阅：my-sub                   │
│ 🚀 当前节点：香港 IPLC 01             │
│ 🌐 可用性  ：google.com ✓            │
│ 🗺  代理模式：rule                    │
│ 🟢 风险等级：low                      │
│ 🔧 运行内核：mihomo                   │
│ ⚙️  运行后端：systemd                 │
│ 🌐 代理端口：7890                     │
│ 📜 系统代理：已设置                    │
│ 🚦 开机接管：已开启                    │
╰──────────────────────────────────────╯

> ⛔  关闭代理
  💫  切换节点
  💱  切换订阅
  🌐  代理模式
  🔌  活跃连接
  📡  订阅管理
  📋  订阅列表
  🔍  状态详情
  🩺  系统诊断
  📜  查看日志
  🧩  配置管理
  🧪  Tun 管理
  🚦  开机接管
  🔑  密钥管理
  🔄  刷新状态
  ❌  退出
```

### 功能详解

| 功能 | 说明 |
|------|------|
| **切换节点** | 浏览所有策略组，搜索过滤节点，查看延迟，支持一键并发测速所有节点 |
| **切换订阅** | 快速切换当前激活的订阅源 |
| **代理模式** | 在 Rule / Global / Direct 模式之间一键切换 |
| **活跃连接** | 查看当前活跃连接列表，分页浏览，支持一键关闭所有连接 |
| **订阅管理** | 添加 / 启用 / 禁用 / 重命名 / 删除订阅 |
| **订阅列表** | 查看所有已保存订阅的状态 |
| **状态详情** | 展示运行内核版本、端口、配置路径等详细信息 |
| **系统诊断** | 调用 `doctor` 诊断面板，快速排查问题 |
| **查看日志** | 实时查看 Clash 运行日志，支持级别过滤 |
| **配置管理** | 查看 / 编辑 / 重新生成运行配置 |
| **Tun 管理** | 启用 / 关闭 Tun 模式，查看 Tun 诊断 |
| **开机接管** | 管理开机自启和系统代理持久化 |
| **密钥管理** | 查看和修改 Web 控制台访问密钥 |

### 节点切换与测速

<!-- TODO: 替换为真实截图 -->
<!-- <p align="center"><img src="resources/tui-node-select.png" width="80%"></p> -->

```
╔══════════════════════════════════════╗
║          💫 切换节点                  ║
╚══════════════════════════════════════╝

选择策略组（ESC / 🔙 返回主菜单）
> 🔍 搜索策略组...

  节点选择       │  Selector  │  香港 IPLC 01
  自动选择       │  URLTest   │  日本 NTT 03
  故障转移       │  Fallback  │  新加坡 BGP 02

────────────────────────────────────────

  ⚡  测速所有节点
  🔙  返回策略组

  🇭🇰  香港 IPLC 01       ⚡ 58ms    ← 当前
  🇭🇰  香港 IPLC 02       ⚡ 72ms
  🇯🇵  日本 NTT 03        ⚡ 89ms
  🇸🇬  新加坡 BGP 02      ⚡ 112ms
  🇺🇸  美国 San Jose 01   ⚡ 186ms
  🇰🇷  韩国 首尔 01       ⏱ 超时
```

- 支持 **模糊搜索**：输入关键字快速定位策略组和节点
- 支持 **并发测速**：对所有节点同时发起测速请求（约 3 秒完成），结果按延迟排序显示
- 测速结果会被缓存，在当前选择会话中复用，切换节点无需重复测速

### 可选依赖

TUI 依赖 [gum](https://github.com/charmbracelet/gum)（Charm 出品的终端 UI 工具）。gum 不是主安装依赖；未安装时仅 `clashctl tui` 不可用，`clashon`、`clashoff`、`clashctl select`、`status`、`doctor` 等命令不受影响。

安装项目时会询问是否安装 gum，默认跳过；也可以安装后单独执行：

```bash
clashctl tui install-gum
```

非交互安装时可通过环境变量控制：

```bash
CLASH_INSTALL_GUM=true bash install.sh
CLASH_INSTALL_GUM=false bash install.sh
```

```bash
# macOS
brew install gum

# Arch Linux
pacman -S gum

# Ubuntu/Debian
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt update && sudo apt install gum

# Fedora/RHEL
echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo
sudo rpm --import https://repo.charm.sh/yum/gpg.key
sudo yum install gum

# Go
go install github.com/charmbracelet/gum@latest
```

> 如果未安装 gum，其他所有命令行功能仍然完全可用，仅 `clashctl tui` 不可用。

------

# 🚀 一键安装（推荐）

在终端中执行以下命令即可完成安装：

```
git clone --branch master --depth 1 https://ghfast.top/https://github.com/Babylonehy/clash-for-linux-tui.git
cd clash-for-linux-tui
bash install.sh
```

- 上述命令使用了[加速前缀](https://gh-proxy.org/)，如失效可更换其他[可用链接](https://ghproxy.link/)。
- 可通过 `.env` 文件或脚本参数自定义安装选项。
- 在 WSL 环境中，不支持放在 Windows 挂载目录**/mnt/c/**下，请安装到 Linux 原生目录。

------

## ⌨️ 命令一览

```bash
〽️ 常用命令
  clashon              🚀 开启代理
  clashoff             ⛔ 关闭代理
  clashctl tui         🖥️  TUI 控制台（新增）
  clashctl select      💫 选择节点
🕹️  控制台
  clashui              🕹️  查看 Web 控制台
📦 订阅
  clashctl add         ➕ 添加订阅
  clashctl add local   ➕ 从 runtime/subscriptions 导入本地订阅
  clashctl use         💱 切换订阅
  clashctl ls          📜 查看订阅列表
🔐 密钥管理
  clashctl secret      🔑 查看密钥
  clashctl secret 123  🔐 设置密钥
📌 高级
  clashctl lan       🏠 局域网代理管理
  clashctl tun       🧪 Tun 模式管理
  clashctl boot      🚦 开机代理接管管理
  clashctl mixin     🧩 Mixin 配置管理
  clashctl relay     🔗 多跳节点管理
  clashctl sub       🧩 订阅高级管理（启用 / 禁用 / 重命名 / 删除）
  clashctl upgrade   🚀 升级当前或指定内核
  clashctl update    🔄 更新项目代码
📜 日志
  clashctl doctor    🩺 诊断面板
  clashctl log/logs  📜 查看日志

💡 显示更多帮助命令：clashctl -h
```

------

## 🌐 Web 控制台

```bash
$ clashui
╔═══════════════════════════════════════════════╗
║                🐱 Web 控制台                  ║
║═══════════════════════════════════════════════║
║                                               ║
║     🔓 注意放行端口：9090                      ║
║     📶 状态：可访问                            ║
║     🏠 内网：http://192.168.0.1:9090/ui       ║
║     ☁️ 公共：http://board.zash.run.place      ║
║     🌏 公网：http://8.8.8.8:9090/ui           ║
║     🔑 密钥：dada289edb457b59                 ║
║                                               ║
╚═══════════════════════════════════════════════╝

$ clashsecret mysecret
🐱 密钥更新成功，已重启生效

$ clashsecret
🐱 当前密钥：mysecret
```

- 可通过浏览器打开 `Web` 控制台进行可视化操作，例如切换节点、查看日志等。
- `clashctl secret` 与 `clashsecret` 都支持无参数查看、有参数直接设置。
- 默认使用 [zashboard](https://github.com/Zephyruso/zashboard) 作为控制台前端，如需更换可自行配置。
- 若需将控制台暴露到公网，建议定期更换访问密钥，或通过 `SSH` 端口转发方式进行安全访问。

------

## 🏠 局域网代理

项目默认开启局域网代理：运行配置会写入 `allow-lan: true`，并把 `external-controller` 绑定到 `0.0.0.0`，避免订阅文件里的 `allow-lan: false` 覆盖项目默认值。

```bash
clashctl lan status
clashctl lan on
clashctl lan off
```

开启后，同一局域网设备可把 HTTP / SOCKS 代理地址设置为 `http://<本机局域网IP>:<mixed-port>`，端口默认是 `7890`；如访问不了，请检查系统防火墙是否放行该端口。

------

OpenWrt 下 root/system 安装会把 `clashctl`、`clashon`、`clashoff` 等命令入口写入 `/usr/bin`，运行状态、日志和内核二进制仍保存在项目目录的 `runtime/` 下。仅脚本模式不会注册开机自启，设备重启后需要重新执行 `clashon`。
## 🧰 常用管理命令

### 多订阅管理

```
clashctl add <订阅链接> <名称>
clashctl use
clashctl ls
clashctl sub
clashctl sub list
clashctl sub enable <名称>
clashctl sub disable <名称>
clashctl sub rename <旧名称> <新名称>
clashctl sub remove <名称>
```

WSL / 普通用户如果无权写入 `/etc/environment`，`clashon` 会自动降级：运行时照常启动，当前 Shell 代理变量生效；系统代理持久接管和开机代理保持不可用。

### 本地配置导入

推荐使用交互导入，放置目录为：`$PROJECT_DIR/runtime/subscriptions/`

```bash
clashctl add local
# 输入：clash.yaml
```

实际等价于：

```bash
clashctl add "file://$PROJECT_DIR/runtime/subscriptions/clash.yaml"
```

进阶用法：也可以直接使用 `file://` 绝对路径导入：

```bash
clashctl add "file:///绝对路径/clash.yaml" home
```

支持格式：

- Clash / Mihomo YAML
- Base64 订阅
- 分享链接（`vmess` / `vless` / `trojan` / `tuic`）

### 开机接管（内核 + 代理）

```bash
clashctl boot status
clashctl boot on
clashctl boot off
clashctl boot runtime on|off|status
clashctl boot proxy on|off|status
```

- `boot runtime`：只管理内核开机自启（systemd / systemd-user 可用，script 后端为 `unsupported`）。
- `boot proxy`：只管理 `/etc/environment` 中的代理持久块（决定开机后是否自动保持代理变量）。
- `boot`：整体接管开关，等价于同时编排 runtime + proxy 两层状态。

------

## OpenWrt 脚本模式

当前提供 OpenWrt 脚本模式兼容，适合 x86_64/amd64 与 aarch64/arm64 软路由或设备。该模式复用现有 `script` 运行后端，不包含 procd 开机自启、LuCI、UCI 或 opkg 包化支持，也不承诺 MIPS 与 armv7 设备可用。

建议先将项目放到持久化目录，避免放在 `/tmp`、`/run` 等重启会丢失的位置：

```bash
cd /root
git clone --branch master --depth 1 https://ghfast.top/https://github.com/Babylonehy/clash-for-linux-tui.git
cd clash-for-linux-tui
```

安装依赖：

```bash
opkg update
opkg install bash curl tar gzip coreutils-readlink unzip
```

安装与手动管理：

```bash
bash install.sh
clashon
clashctl status
clashoff
```

OpenWrt 下 root/system 安装会把 `clashctl`、`clashon`、`clashoff` 等命令入口写入 `/usr/bin`，运行状态、日志和内核二进制仍保存在项目目录的 `runtime/` 下。仅脚本模式不会注册开机自启，设备重启后需要重新执行 `clashon`。

## 🏗️ 架构设计架构简述

项目当前可以按三层理解：

### Control

用户入口层。

- `clashctl`
- `clashon`
- `clashoff`
- `status`
- `doctor`
- `ui`
- `select`
- `tui`（新增）

Control 层负责把常用动作收口成可理解的命令和反馈。

### Build

配置生成层。

- 多订阅保存
- 单 active 主订阅
- active-only 编译链
- 订阅下载 / 转换 / 校验
- `runtime/mixin.yaml` 运行补丁（兼容读取 `config/mixin.yaml`）
- 输出 `runtime/config.yaml`

当前规则很明确：`generate_config` 只处理当前 active 主订阅。

### Runtime 说明（重要）

`runtime/` 是运行时目录，不是配置目录。

它的作用是作为"唯一运行容器"，用于存放：

\- 运行内核（mihomo / clash）
\- 运行配置（config.yaml）
\- 订阅状态（subscriptions.yaml）
\- dashboard 前端
\- 日志（logs）
\- 构建中间文件（tmp）

这些内容都是 **install / 运行过程中动态生成的**，不会作为仓库内容长期维护。



## 配置说明

### `.env`

`.env` 用于覆盖安装和运行参数。常用项包括：

```bash
KERNEL_TYPE=mihomo
MIXED_PORT=7890
EXTERNAL_CONTROLLER=0.0.0.0:9090
CLASH_CONTROLLER_SECRET=your-secret
CLASH_SUBSCRIPTION_URL=https://example.com/sub
MIHOMO_VERSION=latest
CLASH_VERSION=latest
YQ_VERSION=v4.44.3
SUBCONVERTER_VERSION=v0.9.9
MIHOMO_DOWNLOAD_BASE=https://github.com/MetaCubeX/mihomo/releases/download
CLASH_DOWNLOAD_BASE=https://github.com/WindSpiritSR/clash/releases/download
CLASH_BUNDLED_ASSET_ENABLED=true
```

按需设置即可，不需要每项都写。

### 内置运行依赖

当前正式支持的架构为 `amd64`、`arm64`、`armv7`。超出这三种架构时会明确失败，不会伪装成已支持。

如果安装环境访问 GitHub 很慢，可以把 Mihomo、yq、subconverter 的刚需文件跟随项目一起分发。安装和 `clashctl upgrade` 会优先读取 `resources/bin` 中与当前版本、架构对应的精确文件名；本地没有对应文件时，会回退到原来的远程下载逻辑，不影响后续升级内核。

Clash 仅作为兼容内核处理，固定走远程下载，不会命中 `resources/bin` 中的本地资源。

推荐路径直接放在分类目录下：

```text
resources/bin/mihomo/mihomo-linux-amd64-compatible-v1.19.23.gz
resources/bin/mihomo/mihomo-linux-arm64-v1.19.23.gz
resources/bin/mihomo/mihomo-linux-armv7-v1.19.23.gz
resources/bin/yq/yq_linux_amd64.tar.gz
resources/bin/yq/yq_linux_arm64.tar.gz
resources/bin/yq/yq_linux_arm.tar.gz
resources/bin/subconverter/subconverter_linux64.tar.gz
resources/bin/subconverter/subconverter_aarch64.tar.gz
resources/bin/subconverter/subconverter_armv7.tar.gz
resources/geo/Country.mmdb
```

版本仍由 `.env` 中的 `MIHOMO_VERSION`、`CLASH_VERSION`、`YQ_VERSION`、`SUBCONVERTER_VERSION` 控制。脚本不会扫描目录，也不会自动选择最高版本；如果升级版本，请同步放入新版本对应文件，或让脚本回退到远程下载。

也可以设置 `CLASH_BUNDLED_ASSET_ENABLED=false` 强制跳过内置文件，或用 `CLASH_BUNDLED_ASSET_DIR=/path/to/assets` 指向项目外的资源目录。Mihomo、yq、subconverter 兼容旧路径 `resources/bin/<category>/<version>/<file>`。

### `runtime/mixin.yaml`（兼容 `config/mixin.yaml`）

用于对最终运行配置做补丁：

- `override` 覆盖字段
- `prepend` 把数组项放到原始配置前面
- `append` 把数组项放到原始配置后面

查看当前模板：

```bash
clashctl mixin
```

编辑：

```bash
clashctl mixin edit
```

查看最终运行配置：

```bash
clashctl mixin runtime
```

### 

------

## 🔄 更新

```bash
clashctl update
clashctl upgrade
clashctl upgrade mihomo
clashctl upgrade clash
```

`update` 用于更新项目代码与运行依赖。`upgrade` 用于升级当前或指定代理内核。

------

## 🧩 Mixin 配置

```bash
clashctl mixin
clashctl mixin edit
clashctl mixin raw
clashctl mixin runtime
```

Mixin 是运行配置补丁，不是订阅管理。它优先通过 `runtime/mixin.yaml`（兼容读取 `config/mixin.yaml`）对当前 active 订阅生成的运行配置执行：

- `override`
- `prepend`
- `append`

示例：

```yaml
override:
  dns:
    enable: true

prepend:
  proxies: []
  proxy-groups: []
  rules:
    - DOMAIN-SUFFIX,example.com,DIRECT

append:
  proxies: []
  proxy-groups: []
  rules:
    - MATCH,节点选择
```

编辑后执行：

```bash
clashctl mixin edit
```

它会重新生成配置；如果代理正在运行，会自动重启应用。

### 多跳节点

多跳节点会写入 `runtime/mixin.yaml`（兼容读取 `config/mixin.yaml`），通过 Mihomo/Clash 的 `relay` 策略组串联已有订阅节点。节点名称必须与订阅生成的节点名完全一致，可先通过 Web 控制台确认：

```bash
clashon
clashui
```

按域名小范围测试：

```bash
clashctl relay add 多跳-示例 节点A 节点B --domain example.com
clashctl relay list
```

也可以使用快捷入口：`clashrelay list`。

全局接管：

```bash
clashctl relay add 全局多跳 节点A 节点B --match
```

`--match` 会让所有未提前命中的流量走多跳，建议先用 `--domain` 验证链路。删除多跳配置：

```bash
clashctl relay remove 多跳-示例
```

------

## 🌐 Tun 模式

```bash
clashctl tun on
clashctl tun off
clashctl tun doctor
clashctl tun logs
```

Tun 用于透明接管链路。`tun on` 是动作反馈，展示当前关键配置和简短状态；完整证据请看：

```bash
clashctl tun doctor
```

Tun 判断不会简单把 `root` 等同于拥有 `CAP_NET_ADMIN`，也不会把 main table 默认路由未切换直接等同于 Tun 未生效。诊断会结合运行后端、容器环境、进程能力、Tun adapter、policy routing、路由表和日志证据。

------

## 🧹 卸载

```
bash uninstall.sh
```

## 设置代理
1. 开启 IP 转发

```bash
echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
sysctl -p
```

2.配置iptables
```bash
# 先清空旧规则
iptables -t nat -F

# 允许本机访问代理端口
iptables -t nat -A OUTPUT -p tcp --dport 7890 -j RETURN
iptables -t nat -A OUTPUT -p tcp --dport 7891 -j RETURN
iptables -t nat -A OUTPUT -p tcp --dport 7892 -j RETURN

# 让所有 TCP 流量通过 7892 代理
iptables -t nat -A PREROUTING -p tcp -j REDIRECT --to-ports 7892

# 保存规则
iptables-save | tee /etc/iptables.rules
```

3. 让 iptables 规则开机生效
在 `/etc/rc.local`（或 `/etc/rc.d/rc.local`）加上：

```bash
#!/bin/bash
iptables-restore < /etc/iptables.rules
exit 0
```

```bash
chmod +x /etc/rc.local
```

## 🔗 引用

- [clash-for-linux](https://github.com/wnlen/clash-for-linux) — 上游项目
- [gum](https://github.com/charmbracelet/gum) — TUI 组件库
- [clash](https://clash.wiki/)
- [mihomo](https://github.com/MetaCubeX/mihomo)
- [subconverter](https://github.com/asdlokj1qpi233/subconverter)
- [zashboard](https://github.com/Zephyruso/zashboard)

# 常见问题

1. 部分Linux系统默认的 shell `/bin/sh` 被更改为 `dash`，运行脚本会出现报错（报错内容一般会有 `-en [ OK ]`）。建议使用 `bash xxx.sh` 运行脚本。

2. 部分用户在UI界面找不到代理节点，基本上是因为厂商提供的clash配置文件是经过base64编码的，且配置文件格式不符合clash配置标准。

   目前此项目已集成自动识别和转换clash配置文件的功能。如果依然无法使用，则需要通过自建或者第三方平台（不推荐，有泄露风险）对订阅地址转换。
   
3. 程序日志中出现`error: unsupported rule type RULE-SET`报错，解决方法查看官方[WIKI](https://github.com/Dreamacro/clash/wiki/FAQ#error-unsupported-rule-type-rule-set)

## ⚠️ 特别声明



1. 编写本项目主要目的为学习和研究 `Shell` 编程，不得将本项目中任何内容用于违反国家/地区/组织等的法律法规或相关规定的其他用途。
2. 本项目保留随时对免责声明进行补充或更改的权利，直接或间接使用本项目内容的个人或组织，视为接受本项目的特别声明。
