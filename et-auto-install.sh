#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
        log_warning "当前不是root用户，尝试切换到root..."
        exec su -c "$0" root
        exit 1
    fi
    log_success "已确认为root用户，继续执行..."
}

# 检查并安装必要的依赖工具
check_dependencies() {
    log_info "检查必要的依赖工具..."
    
    # 检查并安装curl
    if ! command -v curl &> /dev/null; then
        log_warning "未找到curl，正在安装..."
        if command -v apt-get &> /dev/null; then
            apt-get update -qq && apt-get install -y curl
        elif command -v yum &> /dev/null; then
            yum install -y curl
        else
            log_error "无法安装curl，请手动安装后重试"
            exit 1
        fi
        log_success "curl安装完成"
    else
        log_success "curl已安装"
    fi
    
    # 检查并安装wget
    if ! command -v wget &> /dev/null; then
        log_warning "未找到wget，正在安装..."
        if command -v apt-get &> /dev/null; then
            apt-get update -qq && apt-get install -y wget
        elif command -v yum &> /dev/null; then
            yum install -y wget
        else
            log_error "无法安装wget，请手动安装后重试"
            exit 1
        fi
        log_success "wget安装完成"
    else
        log_success "wget已安装"
    fi
}

# 检测系统架构并获取最新版本
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
    
    # 获取最新版本号
    log_info "获取最新版本信息..."
    
    # 使用临时文件存储API响应
    API_RESPONSE_FILE=$(mktemp)
    
    if command -v curl &> /dev/null; then
        curl -s -o "$API_RESPONSE_FILE" https://api.github.com/repos/EasyTier/EasyTier/releases/latest
    elif command -v wget &> /dev/null; then
        wget -q -O "$API_RESPONSE_FILE" https://api.github.com/repos/EasyTier/EasyTier/releases/latest
    else
        log_error "无法获取版本信息，curl和wget均未安装"
        rm -f "$API_RESPONSE_FILE"
        exit 1
    fi
    
    # 检查API响应是否包含404错误
    if grep -q "404: Not Found" "$API_RESPONSE_FILE" || [ ! -s "$API_RESPONSE_FILE" ]; then
        log_error "获取版本信息失败，API返回404错误或空响应"
        rm -f "$API_RESPONSE_FILE"
        exit 1
    fi
    
    # 从API响应中提取版本号
    LATEST_VERSION=$(grep -oP '"tag_name": "\K(.*)(?=")' "$API_RESPONSE_FILE")
    
    # 清理临时文件
    rm -f "$API_RESPONSE_FILE"
    
    if [ -z "$LATEST_VERSION" ];then
        log_error "无法获取最新版本信息"
        exit 1
    fi
    
    log_success "最新版本: $LATEST_VERSION"
    
    # 去掉版本号前面的v (如果有)
    VERSION=${LATEST_VERSION#v}
    
    # 构建包名
    PACKAGE_NAME="easytier-${os}-${ARCH}-${LATEST_VERSION}.zip"
    log_info "目标软件包: $PACKAGE_NAME"
}

# 从GitHub拉取对应架构的包
download_package() {
    log_info "开始从GitHub Releases拉取EasyTier软件包..."
    
    # GitHub Releases URL
    GITHUB_RELEASE_URL="https://github.com/EasyTier/EasyTier/releases/download/${LATEST_VERSION}"
    
    # 确保下载目录存在
    mkdir -p /tmp/easytier-download
    cd /tmp/easytier-download
    
    # 下载对应架构的包
    log_info "正在下载 $PACKAGE_NAME..."
    
    # 检查URL是否可访问
    if command -v curl &> /dev/null; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${GITHUB_RELEASE_URL}/${PACKAGE_NAME}")
        if [ "$HTTP_CODE" = "404" ]; then
            log_error "下载URL返回404错误，文件可能不存在: ${GITHUB_RELEASE_URL}/${PACKAGE_NAME}"
            exit 1
        fi
        
        if curl -L "${GITHUB_RELEASE_URL}/${PACKAGE_NAME}" -o "${PACKAGE_NAME}"; then
            log_success "下载包成功"
        else
            log_error "curl下载包失败，尝试使用wget..."
            if command -v wget &> /dev/null; then
                if wget --spider "${GITHUB_RELEASE_URL}/${PACKAGE_NAME}" 2>/dev/null; then
                    wget "${GITHUB_RELEASE_URL}/${PACKAGE_NAME}" -O "${PACKAGE_NAME}"
                    log_success "下载包成功"
                else
                    log_error "下载包失败，URL不可访问"
                    exit 1
                fi
            else
                log_error "下载包失败，请检查网络连接和下载链接"
                exit 1
            fi
        fi
    elif command -v wget &> /dev/null; then
        if wget --spider "${GITHUB_RELEASE_URL}/${PACKAGE_NAME}" 2>/dev/null; then
            if wget "${GITHUB_RELEASE_URL}/${PACKAGE_NAME}" -O "${PACKAGE_NAME}"; then
                log_success "下载包成功"
            else
                log_error "下载包失败，请检查网络连接"
                exit 1
            fi
        else
            log_error "下载URL不可访问: ${GITHUB_RELEASE_URL}/${PACKAGE_NAME}"
            exit 1
        fi
    else
        log_error "系统中既没有curl也没有wget，无法下载"
        exit 1
    fi
    
    # 下载服务文件
    log_info "下载service文件..."
    SERVICE_URL="https://raw.githubusercontent.com/zhugeyufeng/easytier-auto-deploy/main/resource/easytier.service"
    
    if command -v curl &> /dev/null; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${SERVICE_URL}")
        if [ "$HTTP_CODE" = "404" ]; then
            log_warning "服务文件URL返回404错误，创建默认服务文件"
            create_default_service_file
        else
            if curl -L "${SERVICE_URL}" -o "easytier.service"; then
                log_success "下载服务文件成功"
            else
                log_error "下载服务文件失败，创建默认服务文件"
                create_default_service_file
            fi
        fi
    elif command -v wget &> /dev/null; then
        if wget --spider "${SERVICE_URL}" 2>/dev/null; then
            if wget "${SERVICE_URL}" -O "easytier.service"; then
                log_success "下载服务文件成功"
            else
                log_error "下载服务文件失败，创建默认服务文件"
                create_default_service_file
            fi
        else
            log_warning "服务文件URL不可访问，创建默认服务文件"
            create_default_service_file
        fi
    else
        log_error "无法下载服务文件，创建默认服务文件"
        create_default_service_file
    fi
}

# 创建默认服务文件（当无法下载时）
create_default_service_file() {
    log_info "创建默认服务文件..."
    cat > /tmp/easytier-download/easytier.service << EOF
[Unit]
Description=EasyTier Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/root/easytier/easytier
WorkingDirectory=/root/easytier
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    log_success "默认服务文件已创建"
}

# 解压安装包
extract_package() {
    log_info "创建安装目录..."
    mkdir -p /root/easytier
    
    log_info "解压安装包到/root/easytier..."
    if [ "${PACKAGE_NAME##*.}" = "zip" ]; then
        # 安装unzip（如果需要）
        if ! command -v unzip &> /dev/null; then
            log_info "安装unzip工具..."
            apt-get update -qq && apt-get install -y unzip || yum install -y unzip
        fi
        
        if unzip -o "/tmp/easytier-download/${PACKAGE_NAME}" -d /root/easytier; then
            log_success "解压成功"
        else
            log_error "解压失败"
            exit 1
        fi
    else
        if tar -xzf "/tmp/easytier-download/${PACKAGE_NAME}" -C /root/easytier; then
            log_success "解压成功"
        else
            log_error "解压失败"
            exit 1
        fi
    fi
    
    # 设置可执行权限
    chmod +x /root/easytier/easytier
}

# 安装服务
install_service() {
    log_info "安装EasyTier服务..."
    
    # 复制服务文件到系统目录
    cp /tmp/easytier-download/easytier.service /etc/systemd/system/
    
    # 重新加载systemd配置
    log_info "重新加载systemd配置..."
    systemctl daemon-reload
    
    # 启用并启动服务
    log_info "启用EasyTier服务..."
    systemctl enable easytier.service
    
    log_info "启动EasyTier服务..."
    systemctl start easytier.service
}

# 展示服务状态
show_service_status() {
    log_info "EasyTier服务状态:"
    systemctl status easytier.service
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    rm -rf /tmp/easytier-download
    log_success "清理完成"
}

# 主函数
main() {
    echo "========== EasyTier 自动安装脚本 =========="
    
    check_root
    check_dependencies
    detect_arch_and_version
    download_package
    extract_package
    install_service
    show_service_status
    cleanup
    
    log_success "EasyTier 安装完成!"
    echo "================================================"
}

# 执行主函数
main
