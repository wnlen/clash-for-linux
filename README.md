# 项目介绍 🌟

> **For English users:** Please refer to the English version of the README located at [README_en.md](./README_en.md).

本项目基于开源项目 [clash](https://github.com/Dreamacro/clash) 作为核心程序，通过脚本实现简单的代理功能。  
旨在解决服务器上下载 GitHub 等国外资源速度慢的问题。

---

# 使用须知 📌

- **权限要求**：运行此项目建议使用 `root` 用户，或通过 `sudo` 提权。
- **问题排查**：使用过程中如遇问题，请优先查阅已有的 [issues](https://github.com/wanhebin/clash-for-linux/issues)。
- **敏感信息保护**：提交 issue 前，请替换提交内容中的敏感信息（如：订阅地址）。
- **配置来源**：本项目基于 [clash](https://github.com/Dreamacro/clash) 和 [yacd](https://github.com/haishanh/yacd) 进行配置整合，详细配置请参考原项目。
- **订阅地址**：此项目不提供任何订阅信息，请自行准备 Clash 订阅地址。
- **配置文件**：运行前需手动修改 `.env` 文件中的 `CLASH_URL` 变量值，否则无法正常运行。
- **系统兼容**：当前已在 RHEL 和 Debian 系列 Linux 系统中测试，其他系统可能需适当调整脚本。
- **平台支持**：支持 x86_64 和 aarch64 平台。

> ⚠️ **注意**：遇到无法独自解决的问题，请先前往 [Issues](https://github.com/wanhebin/clash-for-linux/issues) 寻找解决方案。重复性问题将不再提供解答。

---

# 使用教程 📖

## 下载项目 ⬇️

```bash
git clone https://github.com/wanhebin/clash-for-linux.git
cd clash-for-linux
vim .env
```

在 `.env` 文件中修改变量 `CLASH_URL` 的值。  
> **注意**：变量 `CLASH_SECRET` 为自定义 Clash Secret，若留空，脚本将自动生成随机字符串。

---

## 启动程序 🚀

直接运行 `start.sh` 脚本。

```bash
cd clash-for-linux
sudo bash start.sh
```

运行后会输出以下信息：

```bash
正在检测订阅地址...
Clash订阅地址可访问！                                      [  OK  ]

正在下载Clash配置文件...
配置文件config.yaml下载成功！                              [  OK  ]

正在启动Clash服务...
服务启动成功！                                             [  OK  ]

Clash Dashboard 访问地址：http://<ip>:9090/ui
Secret：xxxxxxxxxxxxx
```

### 加载环境变量

```bash
source /etc/profile.d/clash.sh
proxy_on
```

### 验证服务

- 检查服务端口：

```bash
netstat -tln | grep -E '9090|789.'
```

- 检查环境变量：

```bash
env | grep -E 'http_proxy|https_proxy'
```

如果以上步骤正常（服务端口与环境变量检查显示非空），说明 Clash 服务已成功启动，现在即可体验高速下载 GitHub 资源。

---

## 重启程序 🔄

若需修改配置文件，请编辑 `conf/config.yaml`，然后运行：

```bash
sudo bash restart.sh
```

> ⚠️ 重启脚本 `restart.sh` 不会更新订阅信息。

---

## 停止程序 🛑

```bash
cd clash-for-linux
sudo bash shutdown.sh
proxy_off
```

检查程序端口、进程及环境变量 (`http_proxy|https_proxy`) 是否已清除，确认服务已关闭。

---

## Clash Dashboard 🌐

- **访问地址**：启动成功后会输出 Dashboard 的访问地址，例如：http://192.168.0.1:9090/ui  
- **登录管理**：  
  - `API Base URL`：输入 `http://<ip>:9090`
  - `Secret(optional)`：输入启动成功时输出的 Secret  

点击 `Add` 并选择对应的地址，即可通过浏览器进行管理。  
更多使用说明请参考 [yacd](https://github.com/haishanh/yacd) 项目。

---

# 常见问题 ❓

1. **脚本报错 `-en [ OK ]`**  
   部分Linux系统默认的 shell `/bin/sh` 被更改为`dash`，运行脚本会出现报错（报错内容一般会有`-en [ OK ]`）。建议使用`bash xxx.sh`运行脚本。

2. **UI 界面无法打开**  
   这通常是因为提供的 Clash 配置文件经过 base64 编码且不符合标准格式。  
   项目已集成自动识别和转换功能，但若仍无法使用，需自行转换订阅地址（不推荐使用第三方工具，存在泄露风险）。  
   如需排查问题，请参考 `logs/clash.log`。

3. **程序日志报错 `error: unsupported rule type RULE-SET`**  
   请查阅 Clash 官方 [WIKI](https://github.com/Dreamacro/clash/wiki/FAQ#error-unsupported-rule-type-rule-set) 获取解决方法。
