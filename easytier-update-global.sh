#!/bin/bash

Green_font="\033[32m"
Yellow_font="\033[33m"
Red_font="\033[31m"
Font_suffix="\033[0m"

WORK_DIR="/root/easytier"
RELEASE_BASE_URL="https://github.com/EasyTier/EasyTier/releases"
VERSION=""
RELEASE_CHANNEL=""
PLATFORM=""
DOWNLOAD_URL=""
ZIP_FILE=""
EXTRACT_DIR=""
SHOW_HELP=0

info() {
    echo -e "${Green_font}[INFO]${Font_suffix} $1"
}

warn() {
    echo -e "${Yellow_font}[WARN]${Font_suffix} $1"
}

error() {
    echo -e "${Red_font}[ERROR]${Font_suffix} $1"
    exit 1
}

is_valid_version() {
    echo "$1" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$' >/dev/null
}

get_latest_version() {
    info "正在获取最新稳定版本号..." >&2

    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/EasyTier/EasyTier/releases/latest" \
        | grep '"tag_name":' \
        | head -n1 \
        | sed -E 's/.*"([^"]+)".*/\1/' \
        | sed 's/^v//')

    if [ -n "$latest_version" ] && is_valid_version "$latest_version"; then
        echo "$latest_version"
        return
    fi

    warn "无法从 GitHub API 获取最新稳定版本，尝试备用方法..." >&2
    latest_version=$(curl -s "$RELEASE_BASE_URL/latest" \
        | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' \
        | head -n1 \
        | sed 's/^v//')

    if [ -n "$latest_version" ] && is_valid_version "$latest_version"; then
        echo "$latest_version"
    else
        warn "无法获取最新稳定版本，使用备用版本 2.3.0" >&2
        echo "2.3.0"
    fi
}

get_latest_prerelease_version() {
    info "正在获取最新 Pre-release 版本号..." >&2

    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/EasyTier/EasyTier/releases?per_page=30" | awk '
        /"tag_name":/ {
            tag=$0
            sub(/^.*"tag_name": *"/, "", tag)
            sub(/".*$/, "", tag)
        }
        /"prerelease": true/ && tag != "" {
            print tag
            exit
        }
    ' | sed 's/^v//')

    if [ -n "$latest_version" ] && is_valid_version "$latest_version"; then
        echo "$latest_version"
        return
    fi

    warn "无法从 GitHub API 获取最新 Pre-release 版本，尝试备用方法..." >&2
    latest_version=$(curl -s "$RELEASE_BASE_URL" \
        | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+-[0-9A-Za-z][0-9A-Za-z.-]*' \
        | head -n1 \
        | sed 's/^v//')

    if [ -n "$latest_version" ] && is_valid_version "$latest_version"; then
        echo "$latest_version"
    else
        error "无法获取最新 Pre-release 版本，请使用 --stable / --prerelease 或手动指定平台后重试"
    fi
}

select_release_channel() {
    if [ -n "$RELEASE_CHANNEL" ]; then
        return
    fi

    if [ ! -t 0 ]; then
        error "未检测到交互式终端，无法选择版本类型；请使用 stable/prerelease 或 --stable/--prerelease 指定通道"
    fi

    echo ""
    echo "请选择 EasyTier 版本类型:"
    echo "  1) 稳定版 (Stable)"
    echo "  2) Pre-release 版"

    while true; do
        read -r -p "请输入选项 [1-2]: " choice
        case "$choice" in
            1)
                RELEASE_CHANNEL="stable"
                return
                ;;
            2)
                RELEASE_CHANNEL="prerelease"
                return
                ;;
            *)
                warn "无效选项，请输入 1 或 2"
                ;;
        esac
    done
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                SHOW_HELP=1
                ;;
            --stable|stable)
                RELEASE_CHANNEL="stable"
                ;;
            --prerelease|--pre-release|prerelease|pre-release)
                RELEASE_CHANNEL="prerelease"
                ;;
            -*)
                error "不支持的参数: $1"
                ;;
            *)
                if [ -z "$PLATFORM" ]; then
                    PLATFORM="$1"
                else
                    error "多余的参数: $1"
                fi
                ;;
        esac
        shift
    done
}

check_root_permission() {
    info "检查系统权限"

    if [ "$EUID" -ne 0 ]; then
        error "此脚本需要 root 权限运行，请使用 sudo 或以 root 用户身份执行"
    fi

    info "权限检查通过"
}

set_version() {
    select_release_channel

    case "$RELEASE_CHANNEL" in
        stable)
            VERSION=$(get_latest_version)
            info "使用最新稳定版本: v${VERSION}"
            ;;
        prerelease)
            VERSION=$(get_latest_prerelease_version)
            info "使用最新 Pre-release 版本: v${VERSION}"
            ;;
        *)
            error "无效的版本通道: $RELEASE_CHANNEL"
            ;;
    esac

    if ! is_valid_version "$VERSION"; then
        error "无效的版本号格式: $VERSION"
    fi
}

detect_platform() {
    info "检查系统架构"

    if [ -n "$1" ]; then
        PLATFORM="$1"
        info "使用手动指定的平台: $PLATFORM"
    else
        local arch
        arch=$(uname -m)
        case "$arch" in
            x86_64)
                PLATFORM="x86_64"
                ;;
            aarch64|arm64)
                PLATFORM="aarch64"
                ;;
            armv7l|armv7ml)
                PLATFORM="armv7"
                ;;
            i386|i686)
                PLATFORM="i386"
                ;;
            mips)
                PLATFORM="mips"
                ;;
            *)
                error "不支持的系统架构: $arch，请手动指定平台 (x86_64, aarch64, armv7, i386, mips)"
                ;;
        esac
        info "自动检测到系统架构: $PLATFORM"
    fi

    case "$PLATFORM" in
        x86_64|aarch64|armv7|i386|mips)
            ;;
        *)
            error "无效的平台参数: $PLATFORM，支持的平台: x86_64, aarch64, armv7, i386, mips"
            ;;
    esac

    build_download_url
}

build_download_url() {
    info "构建下载链接"

    DOWNLOAD_URL="${RELEASE_BASE_URL}/download/v${VERSION}/easytier-linux-${PLATFORM}-v${VERSION}.zip"
    ZIP_FILE="easytier-linux-${PLATFORM}-v${VERSION}.zip"
    EXTRACT_DIR="easytier-linux-${PLATFORM}"

    info "目标平台: $PLATFORM"
    info "目标版本: v${VERSION}"
    info "下载链接: $DOWNLOAD_URL"
}

prepare_directory() {
    info "准备工作目录: $WORK_DIR"

    if [ ! -d "$WORK_DIR" ]; then
        mkdir -p "$WORK_DIR" || error "无法创建目录 $WORK_DIR"
    fi

    cd "$WORK_DIR" || error "无法进入目录 $WORK_DIR"
}

backup_existing_files() {
    info "检查并备份现有文件"

    if [ ! -d "backup" ]; then
        mkdir backup
        info "创建备份目录"
    fi

    if compgen -G "easytier-*" >/dev/null; then
        mv easytier-* backup/
        info "已备份所有 easytier-* 文件"
    else
        info "未发现需要备份的 easytier-* 文件"
    fi
}

download_easytier() {
    info "开始下载 EasyTier v${VERSION} (${PLATFORM})"

    if [ -f "$ZIP_FILE" ]; then
        rm -f "$ZIP_FILE"
        warn "删除旧的下载文件"
    fi

    local retry_count=0
    local max_retries=3

    while [ "$retry_count" -lt "$max_retries" ]; do
        info "尝试下载 (第 $((retry_count + 1)) 次)..."

        if wget --progress=bar:force "$DOWNLOAD_URL"; then
            info "下载完成"
            return 0
        fi

        retry_count=$((retry_count + 1))
        if [ "$retry_count" -lt "$max_retries" ]; then
            warn "下载失败，将在 3 秒后重试..."
            sleep 3
        fi
    done

    error "下载失败，已重试 $max_retries 次，请检查网络连接或下载链接"
}

extract_and_deploy() {
    info "解压并部署 EasyTier"

    if ! unzip "$ZIP_FILE"; then
        error "解压失败"
    fi

    if [ ! -d "$EXTRACT_DIR" ]; then
        error "解压目录 $EXTRACT_DIR 不存在"
    fi

    mv "$EXTRACT_DIR"/* .
    info "文件已移动到工作目录"

    rm -rf "$EXTRACT_DIR"
    rm -f "$ZIP_FILE"
    info "清理临时文件完成"
}

check_permissions() {
    info "检查文件权限"

    for file in easytier-core easytier-cli easytier-web; do
        if [ -f "$file" ]; then
            ls -l "$file"
        fi
    done

    info "文件权限检查完成"
}

show_completion() {
    info "EasyTier 部署完成"
    echo ""
    info "当前目录文件列表:"
    ls -la
    echo ""
    info "工作目录: $WORK_DIR"

    if [ -f "/etc/systemd/system/easytier-web.service" ]; then
        echo ""
        info "检测到 systemd 服务配置:"
        cat /etc/systemd/system/easytier-web.service
        echo ""
        warn "如需重启服务，请运行:"
        echo "  systemctl daemon-reload"
        echo "  systemctl restart easytier-web"
    fi
}

main() {
    info "开始 EasyTier 自动部署脚本"

    parse_args "$@"
    if [ "$SHOW_HELP" -eq 1 ]; then
        cat <<'EOF'
EasyTier 自动更新脚本
下载最新稳定版或 Pre-release 版的 EasyTier 并部署到系统

使用方法:
  easytier-update-global.sh --stable [platform]     # 下载最新稳定版
  easytier-update-global.sh --prerelease [platform] # 下载最新 Pre-release 版
  easytier-update-global.sh [platform]              # 交互选择稳定版或 Pre-release

参数说明:
  platform   - 平台架构 (可选)

支持的平台:
  x86_64     - Intel/AMD 64位处理器
  aarch64    - ARM 64位处理器
  armv7      - ARM v7 处理器
  i386       - Intel/AMD 32位处理器
  mips       - MIPS 处理器

示例:
  easytier-update-global.sh --stable
  easytier-update-global.sh --prerelease
  easytier-update-global.sh --stable x86_64
  easytier-update-global.sh aarch64

数据源: https://github.com/EasyTier/EasyTier/releases
EOF
        exit 0
    fi

    check_root_permission
    set_version

    if [ -n "$PLATFORM" ]; then
        detect_platform "$PLATFORM"
    else
        detect_platform ""
    fi

    prepare_directory
    backup_existing_files
    download_easytier
    extract_and_deploy
    check_permissions
    show_completion

    info "脚本执行完成"
}

main "$@"
