#!/bin/bash

# EasyTier 自动下载和部署脚本
# 工作目录: /root/easytier

# 颜色定义
Green_font="\033[32m"
Yellow_font="\033[33m"
Red_font="\033[31m"
Font_suffix="\033[0m"

# 配置变量
WORK_DIR="/root/easytier"
VERSION=""
PLATFORM=""
DOWNLOAD_URL=""
ZIP_FILE=""
EXTRACT_DIR=""

# 信息输出函数
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

# 检查 root 权限
check_root_permission() {
    info "检查系统权限"
    
    if [ "$EUID" -ne 0 ]; then
        error "此脚本需要 root 权限运行，请使用 sudo 或以 root 用户身份执行"
    fi
    
    info "权限检查通过"
}

# 获取最新版本信息
get_latest_version() {
    info "正在获取最新版本信息..."
    
    # 从 GitHub API 获取最新 release 信息
    local api_url="https://api.github.com/repos/EasyTier/EasyTier/releases/latest"
    local temp_file="/tmp/easytier_release_info.json"
    
    # 下载 release 信息
    if ! wget -q -O "$temp_file" "$api_url"; then
        error "无法获取版本信息，请检查网络连接"
    fi
    
    # 解析版本号 (去掉 v 前缀)
    VERSION=$(grep '"tag_name"' "$temp_file" | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | sed 's/^v//')
    
    if [ -z "$VERSION" ]; then
        error "无法解析版本号"
    fi
    
    info "获取到最新版本: v${VERSION}"
    
    # 清理临时文件
    rm -f "$temp_file"
}

# 检测系统平台架构并构建下载链接
detect_platform() {
    info "检测系统平台架构"
    
    # 如果用户手动指定了平台，直接使用
    if [ -n "$1" ]; then
        PLATFORM="$1"
        info "使用手动指定的平台: $PLATFORM"
    else
        # 自动检测系统架构
        local arch=$(uname -m)
        case $arch in
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
    
    # 验证平台参数是否有效
    case $PLATFORM in
        x86_64|aarch64|armv7|i386|mips)
            ;;
        *)
            error "无效的平台参数: $PLATFORM，支持的平台: x86_64, aarch64, armv7, i386, mips"
            ;;
    esac
    
    # 构建下载链接和文件名
    build_download_url
}

# 构建下载链接
build_download_url() {
    info "构建下载链接"
    
    # GitHub releases 下载链接格式
    DOWNLOAD_URL="https://gh-proxy.com/github.com/EasyTier/EasyTier/releases/download/v${VERSION}/easytier-linux-${PLATFORM}-v${VERSION}.zip"
    ZIP_FILE="easytier-linux-${PLATFORM}-v${VERSION}.zip"
    EXTRACT_DIR="easytier-linux-${PLATFORM}"
    
    info "目标平台: $PLATFORM"
    info "目标版本: v${VERSION}"
    info "下载链接: $DOWNLOAD_URL"
}

# 检查并创建工作目录
prepare_directory() {
    info "准备工作目录: $WORK_DIR"
    
    if [ ! -d "$WORK_DIR" ]; then
        mkdir -p "$WORK_DIR" || error "无法创建目录 $WORK_DIR"
    fi
    
    cd "$WORK_DIR" || error "无法进入目录 $WORK_DIR"
}

# 备份现有文件
backup_existing_files() {
    info "检查并备份现有文件"
    
    # 创建备份目录
    if [ ! -d "backup" ]; then
        mkdir backup
        info "创建备份目录"
    fi
    
    # 备份所有以 easytier- 开头的文件
    if ls easytier-* 1> /dev/null 2>&1; then
        mv easytier-* backup/
        info "已备份所有 easytier-* 文件"
    else
        info "未发现需要备份的 easytier-* 文件"
    fi
}

# 下载 EasyTier
download_easytier() {
    info "开始下载 EasyTier v${VERSION} (${PLATFORM})"
    
    # 删除可能存在的旧下载文件
    if [ -f "$ZIP_FILE" ]; then
        rm -f "$ZIP_FILE"
        warn "删除旧的下载文件"
    fi
    
    # 下载文件，添加重试机制
    local retry_count=0
    local max_retries=3
    
    while [ $retry_count -lt $max_retries ]; do
        info "尝试下载 (第 $((retry_count + 1)) 次)..."
        
        if wget --progress=bar:force "$DOWNLOAD_URL"; then
            info "下载完成"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                warn "下载失败，将在 3 秒后重试..."
                sleep 3
            fi
        fi
    done
    
    error "下载失败，已重试 $max_retries 次，请检查网络连接或下载链接"
}

# 解压和部署
extract_and_deploy() {
    info "解压并部署 EasyTier"
    
    # 解压文件
    if ! unzip "$ZIP_FILE"; then
        error "解压失败"
    fi
    
    # 检查解压目录是否存在
    if [ ! -d "$EXTRACT_DIR" ]; then
        error "解压目录 $EXTRACT_DIR 不存在"
    fi
    
    # 移动文件到当前目录
    mv "$EXTRACT_DIR"/* .
    info "文件已移动到工作目录"
    
    # 清理临时文件和目录
    rm -rf "$EXTRACT_DIR"
    rm -f "$ZIP_FILE"
    info "清理临时文件完成"
}

# 检查文件权限
check_permissions() {
    info "检查文件权限"
    
    # 检查可执行文件是否存在并显示权限
    for file in easytier-core easytier-cli easytier-web; do
        if [ -f "$file" ]; then
            ls -l "$file"
        fi
    done
    
    info "文件权限检查完成"
}

# 显示完成信息
show_completion() {
    info "EasyTier 部署完成！"
    echo ""
    info "当前目录文件列表:"
    ls -la
    echo ""
    info "工作目录: $WORK_DIR"
    
    # 检查 systemd 服务
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

# 主函数
main() {
    info "开始 EasyTier 自动部署脚本"
    
    # 显示使用说明
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        echo "EasyTier 自动更新脚本"
        echo "从 GitHub 自动获取最新版本并下载对应平台的文件"
        echo ""
        echo "使用方法:"
        echo "  $0                    # 自动检测系统架构并下载最新版本"
        echo "  $0 [platform]         # 手动指定平台架构并下载最新版本"
        echo ""
        echo "支持的平台:"
        echo "  x86_64     - Intel/AMD 64位处理器"
        echo "  aarch64    - ARM 64位处理器"
        echo "  armv7      - ARM v7 处理器"
        echo "  i386       - Intel/AMD 32位处理器"
        echo "  mips       - MIPS 处理器"
        echo ""
        echo "示例:"
        echo "  $0             # 自动检测并下载最新版本"
        echo "  $0 x86_64      # 下载最新版本的 x86_64 版本"
        echo "  $0 aarch64     # 下载最新版本的 aarch64 版本"
        echo ""
        echo "数据源: https://github.com/EasyTier/EasyTier/releases"
        exit 0
    fi
    
    # 首先检查权限
    check_root_permission
    
    get_latest_version
    detect_platform "$1"
    prepare_directory
    backup_existing_files
    download_easytier
    extract_and_deploy
    check_permissions
    show_completion
    
    info "脚本执行完成！"
}

# 执行主函数
main "$@"