#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/core/runtime.sh
source "$PROJECT_DIR/scripts/core/runtime.sh"

prefetch_usage() {
  cat <<'EOF'
用法：
  bash scripts/prefetch-assets.sh [选项]

选项：
  --arch amd64|arm64|armv7  目标主机架构；默认使用当前主机架构
  --kernel mihomo|clash     要打包的代理内核；默认读取 .env 或使用 mihomo
  --output FILE             输出文件；默认 clash-assets-<kernel>-<arch>.tar.gz
  --no-geo                  不包含安装期 GEO 资源
  --dry-run                 只显示下载计划，不下载或生成压缩包
  -h, --help                显示帮助

资源包复制到目标主机后，在项目根目录执行：
  tar -xzf clash-assets-<kernel>-<arch>.tar.gz
  bash install.sh --offline
EOF
}

normalize_prefetch_arch() {
  case "$1" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    *) die_usage "不支持的目标架构：$1" "可选值：amd64、arm64、armv7" ;;
  esac
}

prefetch_sha256_line() {
  local file="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file"
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file"
    return 0
  fi

  die "生成资源包需要 sha256sum 或 shasum"
}

prefetch_download() {
  local url="$1"
  local out="$2"
  local label="$3"

  mkdir -p "$(dirname "$out")"
  download_file "$url" "$out" "$label"
}

target_arch=""
target_kernel=""
output_file=""
include_geo="true"
dry_run="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --arch)
      [ "$#" -ge 2 ] || die_usage "--arch 缺少参数" "可选值：amd64、arm64、armv7"
      target_arch="$2"
      shift 2
      ;;
    --kernel)
      [ "$#" -ge 2 ] || die_usage "--kernel 缺少参数" "可选值：mihomo、clash"
      target_kernel="$2"
      shift 2
      ;;
    --output)
      [ "$#" -ge 2 ] || die_usage "--output 缺少文件路径" "例如：--output /tmp/clash-assets-amd64.tar.gz"
      output_file="$2"
      shift 2
      ;;
    --no-geo)
      include_geo="false"
      shift
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    -h|--help)
      prefetch_usage
      exit 0
      ;;
    *)
      die_usage "未知参数：$1" "执行 bash scripts/prefetch-assets.sh --help 查看用法"
      ;;
  esac
done

init_project_context "$PROJECT_DIR"
load_env_if_exists

target_arch="$(normalize_prefetch_arch "${target_arch:-$(get_arch)}")"
target_kernel="$(normalize_kernel_type "${target_kernel:-${KERNEL_TYPE:-mihomo}}")"

case "$target_kernel" in
  mihomo|clash) ;;
  *) die_usage "不支持的目标内核：$target_kernel" "可选值：mihomo、clash" ;;
esac

export CLASH_TEST_UNAME_M="$target_arch"
export CLASH_OFFLINE="false"

mihomo_version="${MIHOMO_VERSION:-$DEFAULT_MIHOMO_VERSION}"
clash_version="${CLASH_VERSION:-$DEFAULT_CLASH_VERSION}"
yq_version="${YQ_VERSION:-$DEFAULT_YQ_VERSION}"
subconverter_version="${SUBCONVERTER_VERSION:-$DEFAULT_SUBCONVERTER_VERSION}"

yq_file="$(yq_asset_file "$target_arch")"
subconverter_file="$(subconverter_asset_file "$target_arch")"
yq_url="https://github.com/mikefarah/yq/releases/download/${yq_version}/${yq_file}"
subconverter_url="https://github.com/asdlokj1qpi233/subconverter/releases/download/${subconverter_version}/${subconverter_file}"

case "$target_kernel" in
  mihomo)
    kernel_file="$(mihomo_asset_file "$target_arch" "$mihomo_version")"
    if [ -n "${MIHOMO_DOWNLOAD_URL:-}" ]; then
      kernel_url="$MIHOMO_DOWNLOAD_URL"
    else
      kernel_url="${MIHOMO_DOWNLOAD_BASE:-https://github.com/MetaCubeX/mihomo/releases/download}"
      kernel_url="${kernel_url%/}/${mihomo_version}/${kernel_file}"
    fi
    ;;
  clash)
    kernel_file="$(clash_asset_candidates "$target_arch" "$clash_version" | head -n 1)"
    kernel_url="${CLASH_DOWNLOAD_BASE:-https://github.com/WindSpiritSR/clash/releases/download}"
    kernel_url="${kernel_url%/}/${clash_version}/${kernel_file}"
    ;;
esac

ui_section "资源包计划"
ui_kv "🧩" "目标架构" "$target_arch"
ui_kv "🚀" "目标内核" "$target_kernel"
printf '  - %s\n' "$kernel_url"
printf '  - %s\n' "$yq_url"
printf '  - %s\n' "$subconverter_url"

if [ "$include_geo" = "true" ]; then
  for item in "${GEO_ASSET_DOWNLOADS[@]}"; do
    printf '  - %s\n' "${item#* }"
  done
fi

if [ "$dry_run" = "true" ]; then
  success "仅显示下载计划，未生成资源包"
  exit 0
fi

command -v curl >/dev/null 2>&1 || die "当前系统缺少 curl"
command -v tar >/dev/null 2>&1 || die "当前系统缺少 tar"

stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT

RESOURCE_DIR="$stage_dir/resources"
RUNTIME_DIR="$stage_dir/runtime"
BIN_DIR="$RUNTIME_DIR/bin"
LOG_DIR="$RUNTIME_DIR/logs"
mkdir -p "$RESOURCE_DIR/bin" "$RESOURCE_DIR/geo" "$RUNTIME_DIR"

prefetch_download "$kernel_url" "$RESOURCE_DIR/bin/$target_kernel/$kernel_file" "$target_kernel"
prefetch_download "$yq_url" "$RESOURCE_DIR/bin/yq/$yq_file" "yq"
prefetch_download \
  "$subconverter_url" \
  "$RESOURCE_DIR/bin/subconverter/$subconverter_file" \
  "subconverter"

if [ "$include_geo" = "true" ]; then
  for item in "${GEO_ASSET_DOWNLOADS[@]}"; do
    geo_path="${item%% *}"
    geo_url="${item#* }"
    geo_file="$(basename "$geo_path")"
    prefetch_download "$geo_url" "$RESOURCE_DIR/geo/$geo_file" "$geo_file"
  done
fi

source_commit="$(git -C "$PROJECT_DIR" rev-parse --verify HEAD 2>/dev/null || echo unknown)"
cat > "$RESOURCE_DIR/asset-manifest.env" <<EOF
BUNDLE_FORMAT="1"
BUNDLE_ARCH="$target_arch"
KERNEL_TYPE="$target_kernel"
MIHOMO_VERSION="$mihomo_version"
CLASH_VERSION="$clash_version"
YQ_VERSION="$yq_version"
SUBCONVERTER_VERSION="$subconverter_version"
GEO_INCLUDED="$include_geo"
SOURCE_COMMIT="$source_commit"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
EOF

(
  cd "$RESOURCE_DIR"
  while IFS= read -r asset_file; do
    prefetch_sha256_line "$asset_file"
  done < <(
    find bin geo -type f -print
    printf '%s\n' "asset-manifest.env"
  ) | LC_ALL=C sort -k2
) > "$RESOURCE_DIR/SHA256SUMS"

if [ -z "${output_file:-}" ]; then
  output_file="$PWD/clash-assets-${target_kernel}-${target_arch}.tar.gz"
else
  output_dir="$(dirname "$output_file")"
  output_name="$(basename "$output_file")"
  mkdir -p "$output_dir"
  output_file="$(cd "$output_dir" && pwd)/$output_name"
fi

tar -czf "$output_file" -C "$stage_dir" resources

success "资源包已生成：$output_file"
ui_next "复制到目标主机的项目目录，解压后执行：bash install.sh --offline"
