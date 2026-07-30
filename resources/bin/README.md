# 内置运行依赖

如果安装时 GitHub 下载太慢，可以把 Mihomo/Clash、yq、subconverter 提前放到本目录。安装和 `clash upgrade` 会优先读取这里的文件；普通在线模式下，没有匹配文件时仍会回退到原来的下载逻辑。

默认目录结构：

```text
resources/bin/
  mihomo/
    mihomo-linux-amd64-compatible-v1.19.23.gz
    mihomo-linux-arm64-v1.19.23.gz
    mihomo-linux-armv7-v1.19.23.gz
  clash/
    clash-linux-amd64-v1.18.0.gz
    clash-linux-arm64-v1.18.0.gz
    clash-linux-armv7-v1.18.0.gz
  yq/
    yq_linux_amd64.tar.gz
    yq_linux_arm64.tar.gz
    yq_linux_arm.tar.gz
  subconverter/
    subconverter_linux64.tar.gz
    subconverter_aarch64.tar.gz
    subconverter_armv7.tar.gz
```

当前正式支持 `amd64`、`arm64`、`armv7`。版本号要和 `.env` 里的 `MIHOMO_VERSION`、`YQ_VERSION`、`SUBCONVERTER_VERSION` 对应。脚本只按当前目标文件名精确命中，不会扫描目录，也不会自动选择最高版本；如果本地没有对应文件，会继续联网下载。

Mihomo、yq、subconverter 兼容旧路径 `resources/bin/<category>/<version>/<file>`，但默认推荐直接使用 `resources/bin/<category>/<file>`。

可选开关：

```bash
export CLASH_BUNDLED_ASSET_ENABLED=false
export CLASH_BUNDLED_ASSET_DIR=/path/to/assets
```

`Country.mmdb` 仍放在 `resources/geo/Country.mmdb` 或 `resources/geo/country.mmdb`。

推荐通过项目提供的脚本生成完整资源包：

```bash
bash scripts/prefetch-assets.sh --arch amd64 --kernel mihomo
```

将生成的压缩包复制到目标主机并解压到项目根目录后，可执行 `bash install.sh --offline`。严格离线模式会在安装前检查全部资源，缺失时直接失败，不会回退联网下载。资源包只包含 `resources/`，不会包含可能带有订阅、日志或密钥的 `runtime/`。
