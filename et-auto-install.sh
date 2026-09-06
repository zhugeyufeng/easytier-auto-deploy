#!/bin/bash

set -eo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 可配置项
EASYTIER_VERSION="v2.2.4"
EASYTIER_PEER="udp://103.155.202.2:10001/knet"
GH_PROXY=""  # 直连GitHub；如需走代理，填入前缀（参见 et-auto-install-cn.sh）
DOWNLOAD_DIR="/tmp/easytier-download"
INSTALL_DIR="/root/easytier"
SERVICE_NAME="easytier.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

# 输出带颜色的信息函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        # 通过管道执行时 $0 不是真实文件（如 curl ... | bash），无法重新执行自身
        if [ -f "$0" ] && command -v sudo &> /dev/null; then
            log_warning "当前不是root用户，尝试通过sudo重新执行..."
            exec sudo -E bash "$0" "$@"
        fi
        log_error "请以root用户运行本脚本，例如: sudo bash $0"
        exit 1
    fi
    log_success "已确认为root用户，继续执行..."
}

# 安装单个软件包，兼容常见发行版的包管理器
APT_UPDATED=0
install_pkg() {
    pkg="$1"
    log_warning "未找到 $pkg，正在安装..."
    if command -v apt-get &> /dev/null; then
        if [ "$APT_UPDATED" = "0" ]; then
            apt-get update -qq || true
            APT_UPDATED=1
        fi
        apt-get install -y "$pkg"
    elif command -v dnf &> /dev/null; then
        dnf install -y "$pkg"
    elif command -v yum &> /dev/null; then
        yum install -y "$pkg"
    elif command -v zypper &> /dev/null; then
        zypper install -y "$pkg"
    elif command -v pacman &> /dev/null; then
        pacman -Sy --noconfirm "$pkg"
    elif command -v apk &> /dev/null; then
        apk add --no-cache "$pkg"
    else
        log_error "无法自动安装 $pkg，请手动安装后重试"
        exit 1
    fi
    log_success "$pkg 安装完成"
}

ensure_cmd() {
    if command -v "$1" &> /dev/null; then
        log_success "$1 已安装"
    else
        install_pkg "$1"
    fi
}

# 检查并安装必要的依赖工具
check_dependencies() {
    log_info "检查必要的依赖工具..."

    if ! command -v systemctl &> /dev/null; then
        log_error "未检测到 systemd (systemctl)，本脚本仅支持 systemd 系统"
        exit 1
    fi

    ensure_cmd curl
    ensure_cmd unzip
}

# 检测系统架构并确定软件包名
detect_arch_and_version() {
    # 检测架构
    arch=$(uname -m)
    os="linux"

    if [[ $arch == "x86_64" ]]; then
        log_info "检测到x86_64架构"
        ARCH="x86_64"
    elif [[ $arch == "aarch64" || $arch == "arm64" || $arch == "armv8" ]]; then
        log_info "检测到ARM架构"
        ARCH="aarch64"
    else
        log_error "不支持的架构: $arch"
        exit 1
    fi

    # 使用固定版本，不获取最新版本
    log_info "使用指定版本: ${EASYTIER_VERSION}..."
    log_success "版本: $EASYTIER_VERSION"

    # 构建包名
    PACKAGE_NAME="easytier-${os}-${ARCH}-${EASYTIER_VERSION}.zip"
    log_info "目标软件包: $PACKAGE_NAME"
}

# 从GitHub拉取对应架构的包
download_package() {
    log_info "开始从GitHub Releases拉取EasyTier软件包..."

    GITHUB_RELEASE_URL="${GH_PROXY}https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VERSION}"

    mkdir -p "$DOWNLOAD_DIR"

    log_info "正在下载 $PACKAGE_NAME..."
    # -f 让HTTP错误码返回非0退出码，避免把错误页面当成安装包
    if ! curl -fSL --retry 3 --connect-timeout 15 \
        "${GITHUB_RELEASE_URL}/${PACKAGE_NAME}" -o "${DOWNLOAD_DIR}/${PACKAGE_NAME}"; then
        log_error "下载包失败，请检查网络连接和下载链接"
        exit 1
    fi

    if [ ! -s "${DOWNLOAD_DIR}/${PACKAGE_NAME}" ]; then
        log_error "下载的文件为空，请检查下载链接"
        exit 1
    fi

    if ! unzip -tq "${DOWNLOAD_DIR}/${PACKAGE_NAME}" &> /dev/null; then
        log_error "下载的文件不是有效的zip包，可能被网络劫持或代理返回了错误页面"
        exit 1
    fi

    log_success "下载包成功"
}

# 创建服务文件（本地生成，不依赖远程下载）
create_service_file() {
    log_info "创建服务文件..."
    cat > "$SERVICE_FILE" << EOF
[Unit]
After=network.target syslog.target
Description=Easytier Service
StartLimitIntervalSec=0

[Service]
Type=simple
WorkingDirectory=/tmp
ExecStart=${INSTALL_DIR}/easytier-core -w ${EASYTIER_PEER}
Restart=always
RestartSec=1
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    log_success "服务文件已创建: $SERVICE_FILE"
}

# 覆盖安装前先停掉正在运行的服务，避免出现 "Text file busy"
stop_existing_service() {
    if systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}"; then
        log_info "检测到已安装的EasyTier服务，先停止服务..."
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    fi
}

# 解压安装包
extract_package() {
    log_info "创建安装目录..."
    mkdir -p "$INSTALL_DIR"

    log_info "解压安装包到${INSTALL_DIR}..."
    if ! unzip -o "${DOWNLOAD_DIR}/${PACKAGE_NAME}" -d "$INSTALL_DIR"; then
        log_error "解压失败"
        exit 1
    fi
    log_success "解压成功"

    # 压缩包内可能多包一层目录（如 easytier-linux-x86_64/），
    # 且该目录名不一定带版本号，因此直接定位 easytier-core 所在目录再上提
    if [ ! -f "${INSTALL_DIR}/easytier-core" ]; then
        core_path=$(find "$INSTALL_DIR" -mindepth 2 -type f -name easytier-core | head -n 1 || true)
        if [ -n "$core_path" ]; then
            sub_dir=$(dirname "$core_path")
            log_info "检测到子目录 ${sub_dir}，移动文件到 ${INSTALL_DIR}..."
            mv "$sub_dir"/* "$INSTALL_DIR"/ 2>/dev/null || true
            rmdir "$sub_dir" 2>/dev/null || true
            log_success "文件移动完成"
        fi
    fi

    if [ ! -f "${INSTALL_DIR}/easytier-core" ]; then
        log_error "未在 ${INSTALL_DIR} 找到 easytier-core，安装包结构异常"
        exit 1
    fi

    log_info "解压的文件列表:"
    ls -la "$INSTALL_DIR"

    # 设置可执行权限
    for bin in easytier-core easytier-cli easytier-web easytier-web-embed; do
        if [ -f "${INSTALL_DIR}/${bin}" ]; then
            chmod +x "${INSTALL_DIR}/${bin}"
        fi
    done
}

# 安装服务
install_service() {
    log_info "安装EasyTier服务..."

    log_info "重新加载systemd配置..."
    systemctl daemon-reload

    log_info "启用EasyTier服务..."
    systemctl enable "$SERVICE_NAME"

    log_info "启动EasyTier服务..."
    systemctl restart "$SERVICE_NAME"
}

# 展示服务状态
show_service_status() {
    log_info "EasyTier服务状态:"
    systemctl status "$SERVICE_NAME" --no-pager || true
}

# 清理临时文件
cleanup() {
    if [ -d "$DOWNLOAD_DIR" ]; then
        log_info "清理临时文件..."
        cd /
        rm -rf "$DOWNLOAD_DIR"
        log_success "清理完成"
    fi
}

# 无论成功失败都清理临时目录
trap cleanup EXIT

# 主函数
main() {
    echo "========== EasyTier 自动安装脚本 =========="

    check_root "$@"
    check_dependencies
    detect_arch_and_version
    download_package
    stop_existing_service
    extract_package
    create_service_file
    install_service
    show_service_status
    cleanup

    log_success "EasyTier 安装完成!"
    echo "================================================"
}

# 执行主函数
main "$@"
