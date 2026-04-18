#!/bin/bash
# OpenClaw 一键安装配置脚本（小白友好版）
# 适用于 Linux / macOS，Windows 用户请使用 WSL 或 Git Bash

set -e  # 遇到错误立即退出

# -------------------- 颜色定义 --------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------------------- 打印函数 --------------------
print_step() {
    echo -e "${BLUE}➜${NC} $1"
}

print_success() {
    echo -e "${GREEN}✔${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✖${NC} $1"
}

# -------------------- 依赖检查 --------------------
check_dependencies() {
    print_step "检查系统依赖..."
    local missing=()

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi
    if ! command -v node &> /dev/null; then
        missing+=("node (Node.js)")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        print_error "缺少以下依赖：${missing[*]}"
        echo "请先安装缺失的工具，然后重新运行脚本。"
        echo ""
        echo "安装建议："
        echo "  - Ubuntu/Debian: sudo apt update && sudo apt install curl nodejs npm"
        echo "  - macOS: brew install curl node"
        echo "  - 或访问 Node.js 官网: https://nodejs.org/"
        exit 1
    fi
    print_success "依赖检查通过"
}

# -------------------- 检查/安装 OpenClaw --------------------
ensure_openclaw() {
    if command -v openclaw &> /dev/null; then
        print_success "OpenClaw 已安装 ($(openclaw --version 2>/dev/null || echo '版本未知'))"
        return
    fi

    print_warning "未检测到 openclaw 命令，正在尝试安装..."
    echo ""
    echo "OpenClaw 通常通过 npm 安装。"
    echo "如果安装失败，请手动执行："
    echo "  npm install -g openclaw"
    echo ""

    read -p "是否现在安装 openclaw？[Y/n] " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if command -v npm &> /dev/null; then
            print_step "执行 npm install -g openclaw ..."
            npm install -g openclaw
            if command -v openclaw &> /dev/null; then
                print_success "OpenClaw 安装成功！"
            else
                print_error "安装失败，请检查 npm 权限或网络。"
                exit 1
            fi
        else
            print_error "未找到 npm 命令，无法自动安装。"
            exit 1
        fi
    else
        print_error "OpenClaw 是必需的，脚本退出。"
        exit 1
    fi
}

# -------------------- 收集用户输入 --------------------
collect_config() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}    OpenClaw 配置信息收集（交互式）${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "请按提示输入以下信息（直接回车使用默认值，但 API Key / Token 必须填写）"
    echo ""

    # --- API 配置 ---
    echo -e "${BLUE}>>> API 配置（MiniMax 示例，可换成其他兼容 Anthropic 的服务）${NC}"
    read -p "API Base URL [https://api.minimaxi.com/anthropic]: " API_BASE_URL
    API_BASE_URL=${API_BASE_URL:-"https://api.minimaxi.com/anthropic"}

    read -p "Model ID [MiniMax-M2.7]: " MODEL_ID
    MODEL_ID=${MODEL_ID:-"MiniMax-M2.7"}

    read -p "API Key (必填): " API_KEY
    if [ -z "$API_KEY" ]; then
        print_error "API Key 不能为空！"
        exit 1
    fi

    # --- Telegram 配置 ---
    echo ""
    echo -e "${BLUE}>>> Telegram 机器人配置${NC}"
    read -p "Telegram Bot Token (可从 @BotFather 获取，若不需要直接回车跳过): " TG_TOKEN
    if [ -n "$TG_TOKEN" ]; then
        read -p "你的 Telegram 用户 ID (可选，用于白名单控制，可通过 @userinfobot 获取): " TG_USER_ID
    fi

    # --- WhatsApp 配置 ---
    echo ""
    echo -e "${BLUE}>>> WhatsApp 配置${NC}"
    read -p "是否启用 WhatsApp？[Y/n] " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        ENABLE_WHATSAPP=true
        read -p "允许的 WhatsApp 号码 (如 +85212345678，多个用英文逗号分隔，直接回车则仅使用配对模式): " WA_ALLOW_LIST
    else
        ENABLE_WHATSAPP=false
    fi
}

# -------------------- 执行 Onboard 和配置 --------------------
run_onboard() {
    print_step "执行 openclaw onboard（非交互式）..."
    # 构建 onboard 命令
    ONBOARD_CMD="openclaw onboard \
        --non-interactive \
        --auth-choice custom-api-key \
        --custom-base-url \"$API_BASE_URL\" \
        --custom-model-id \"$MODEL_ID\" \
        --custom-api-key \"$API_KEY\" \
        --secret-input-mode plaintext \
        --custom-compatibility anthropic \
        --accept-risk"

    echo "执行命令："
    echo "$ONBOARD_CMD"
    eval "$ONBOARD_CMD"
    print_success "Onboard 完成"
}

configure_telegram() {
    if [ -z "$TG_TOKEN" ]; then
        print_warning "未提供 Telegram Bot Token，跳过 Telegram 配置。"
        return
    fi

    print_step "配置 Telegram 渠道..."
    openclaw config set channels.telegram.botToken "$TG_TOKEN"
    openclaw config set channels.telegram.dmPolicy "pairing"

    if [ -n "$TG_USER_ID" ]; then
        # 处理允许列表（支持逗号分隔多个 ID）
        # 将输入转为 JSON 数组格式
        TG_ARRAY=$(echo "$TG_USER_ID" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | awk '{printf "\"%s\",", $0}' | sed 's/,$//')
        TG_ARRAY="[$TG_ARRAY]"
        openclaw config set channels.telegram.allowFrom "$TG_ARRAY"
        print_success "Telegram 白名单已设置为: $TG_ARRAY"
    else
        print_success "Telegram 配置完成（使用配对模式）"
    fi
    echo ""
    print_warning "⚠️  重要：请向你的 Telegram 机器人发送任意消息，然后在此终端执行以下命令完成配对："
    echo "   openclaw pairing approve telegram <你的Telegram用户ID>"
    echo "   （用户 ID 可通过 @userinfobot 获取）"
}

configure_whatsapp() {
    if [ "$ENABLE_WHATSAPP" != "true" ]; then
        return
    fi

    print_step "启用并配置 WhatsApp 渠道..."
    openclaw config set channels.whatsapp.enabled true
    openclaw config set channels.whatsapp.dmPolicy "pairing"

    if [ -n "$WA_ALLOW_LIST" ]; then
        WA_ARRAY=$(echo "$WA_ALLOW_LIST" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | awk '{printf "\"%s\",", $0}' | sed 's/,$//')
        WA_ARRAY="[$WA_ARRAY]"
        openclaw config set channels.whatsapp.allowFrom "$WA_ARRAY"
        print_success "WhatsApp 白名单已设置: $WA_ARRAY"
    else
        print_success "WhatsApp 已启用（使用配对模式）"
    fi

    echo ""
    print_step "正在启动 WhatsApp 扫码登录..."
    echo "请在打开的终端或浏览器中扫描二维码完成登录。"
    echo "执行命令：openclaw channels login --channel whatsapp"
    openclaw channels login --channel whatsapp
}

# -------------------- 主流程 --------------------
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   OpenClaw 一键安装配置助手${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    check_dependencies
    ensure_openclaw
    collect_config

    echo ""
    echo -e "${YELLOW}>>> 即将开始配置，请确认以下信息：${NC}"
    echo "API Base URL : $API_BASE_URL"
    echo "Model ID     : $MODEL_ID"
    echo "API Key      : ${API_KEY:0:8}****${API_KEY: -4}"
    echo "Telegram     : ${TG_TOKEN:-未配置}"
    echo "WhatsApp     : $([ "$ENABLE_WHATSAPP" = "true" ] && echo "启用" || echo "禁用")"
    echo ""
    read -p "确认无误并继续？[Y/n] " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "已取消。"
        exit 0
    fi

    run_onboard
    configure_telegram
    configure_whatsapp

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   🎉 配置完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "后续操作提示："
    echo "1. Telegram 配对：让机器人接收一条消息，然后运行："
    echo "   openclaw pairing approve telegram <你的Telegram用户ID>"
    echo "2. WhatsApp 已启动扫码登录，若未成功可手动运行："
    echo "   openclaw channels login --channel whatsapp"
    echo "3. 查看运行状态："
    echo "   openclaw status"
    echo "4. 启动服务："
    echo "   openclaw start"
    echo ""
}

# 运行主函数
main
