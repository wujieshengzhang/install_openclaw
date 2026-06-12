#!/bin/bash
#============================================================================
# OpenClaw WhatsApp allowlist setup helper
#============================================================================

set -euo pipefail

SCRIPT_VERSION="1.1.0"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
OPENCLAW_WHATSAPP_PACKAGE_DIR="${OPENCLAW_WHATSAPP_PACKAGE_DIR:-$HOME/.openclaw/npm/node_modules/@openclaw/whatsapp}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
OpenClaw WhatsApp 白名单配置脚本 v${SCRIPT_VERSION}

用法:
  $0 [选项]

参数:
  --allow-from NUMBERS       允许发消息的手机号，多个用逗号或空格分隔
                             示例: "+86150XXXXXXX,+86189XXXXXXX"

选项:
  --login                    执行扫码登录，默认开启
  --install-plugin           安装与当前 OpenClaw 版本匹配的 npm 版 @openclaw/whatsapp 插件，默认开启
  --restart                  验证配置、重启 Gateway，并显示 channel 状态，默认开启
  --no-login                 不执行扫码登录
  --no-install-plugin        不安装插件
  --no-restart               不自动验证配置/重启 Gateway/显示状态
  --plugin-version VERSION   指定 @openclaw/whatsapp 版本，默认使用当前 OpenClaw 版本
  --plugin-spec SPEC         指定完整 npm 包，例如 @openclaw/whatsapp@2026.5.19
  --no-restart-hint          不显示重启提示
  --help                     显示帮助

示例:
  $0
  $0 --allow-from "+86150XXXXXXX,+86189XXXXXXX"
  $0 --allow-from "+852XXXXXXX"
  $0 --allow-from "+86150XXXXXXX +86189XXXXXXX" --plugin-version 2026.5.19

说明:
  - 本脚本使用 channels.whatsapp.dmPolicy="allowlist"，不会给陌生人发送配对码
  - allowFrom 应填写允许和 WhatsApp bot 对话的用户手机号，使用 +国家码 的国际格式
  - 脚本固定配置默认 WhatsApp account
  - 脚本会清理旧的 channels.whatsapp.accounts，避免误写 account id 导致登录异常
  - 如果配置里存在 plugins.allow，本脚本只会追加插件 id: whatsapp
  - 如果之前误装了不兼容的 @openclaw/whatsapp，使用 --install-plugin 会先清理后重装匹配版本
EOF
    exit 0
}

check_openclaw() {
    if ! command -v openclaw >/dev/null 2>&1; then
        error "OpenClaw 未安装。请先安装 OpenClaw。"
        exit 1
    fi
}

is_whatsapp_plugin_compatible() {
    if [ ! -d "$OPENCLAW_WHATSAPP_PACKAGE_DIR" ]; then
        return 1
    fi

    if openclaw channels status --channel whatsapp >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

detect_openclaw_version() {
    local version_line
    local version

    version_line="$(openclaw -v 2>&1 | head -1 || true)"
    version="$(printf '%s\n' "$version_line" | sed -nE 's/.*OpenClaw ([0-9]{4}\.[0-9]+\.[0-9]+).*/\1/p' | head -1)"
    if [ -n "$version" ]; then
        printf '%s\n' "$version"
        return 0
    fi

    python3 << 'PY' 2>/dev/null || true
import json
import os
import subprocess

paths = [
    "/usr/local/lib/node_modules/openclaw/package.json",
    "/opt/homebrew/lib/node_modules/openclaw/package.json",
]

try:
    npm_root = subprocess.check_output(["npm", "root", "-g"], text=True).strip()
    if npm_root:
        paths.append(os.path.join(npm_root, "openclaw", "package.json"))
except Exception:
    pass

for path in paths:
    try:
        with open(path, "r", encoding="utf-8") as f:
            version = json.load(f).get("version")
        if version:
            print(version)
            break
    except Exception:
        continue
PY
}

normalize_numbers_json() {
    local input="$1"
    python3 - "$input" << 'PY'
import json
import re
import sys

raw = sys.argv[1]
parts = [p.strip() for p in re.split(r"[,，\s]+", raw) if p.strip()]
numbers = []
seen = set()

for number in parts:
    normalized = number.replace(" ", "")
    if not normalized.startswith("+") or not normalized[1:].isdigit():
        raise SystemExit(
            f"手机号格式错误: {number}。请使用国际格式，例如 +86150XXXXXXX"
        )
    if normalized not in seen:
        seen.add(normalized)
        numbers.append(normalized)

if not numbers:
    raise SystemExit("allowFrom 不能为空")

print(json.dumps(numbers, ensure_ascii=False))
PY
}

configure_whatsapp() {
    local allow_from_raw="$1"
    local numbers_json

    numbers_json="$(normalize_numbers_json "$allow_from_raw")"

    python3 - "$OPENCLAW_CONFIG" "$numbers_json" << 'PY'
import json
import os
import shutil
import sys
from datetime import datetime

config_path = os.path.expanduser(sys.argv[1])
allow_from = json.loads(sys.argv[2])

if os.path.exists(config_path):
    backup_path = config_path + f".backup-whatsapp-{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    shutil.copy(config_path, backup_path)
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)
else:
    backup_path = None
    config = {}

plugins = config.setdefault("plugins", {})
plugins["enabled"] = True
plugin_allow = plugins.setdefault("allow", [])
plugins["allow"] = [item for item in plugin_allow if item != "@openclaw/whatsapp"]
if "whatsapp" not in plugins["allow"]:
    plugins["allow"].append("whatsapp")

plugin_entries = plugins.setdefault("entries", {})
plugin_entries.pop("@openclaw/whatsapp", None)
whatsapp_entry = plugin_entries.setdefault("whatsapp", {})
whatsapp_entry["enabled"] = True
whatsapp_entry.setdefault("config", {})

channels = config.setdefault("channels", {})
whatsapp = channels.setdefault("whatsapp", {})
removed_accounts = sorted((whatsapp.get("accounts") or {}).keys()) if isinstance(whatsapp.get("accounts"), dict) else []
whatsapp.pop("accounts", None)
whatsapp["enabled"] = True
whatsapp["dmPolicy"] = "allowlist"
whatsapp["allowFrom"] = allow_from

os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write("\n")

if backup_path:
    print(f"已备份配置到: {backup_path}")
else:
    print("未发现旧配置，已创建新配置文件")
print("WhatsApp account: default")
if removed_accounts:
    print("已清理旧 WhatsApp accounts:")
    for account in removed_accounts:
        print(f"  - {account}")
print("allowFrom:")
for number in allow_from:
    print(f"  - {number}")
print("已启用 WhatsApp channel，并设置 plugins.allow: whatsapp")
PY
}

install_plugin() {
    local plugin_spec="$1"

    if is_whatsapp_plugin_compatible; then
        info "WhatsApp 插件已可用，跳过重复安装"
        return 0
    fi

    info "准备安装 WhatsApp 插件: ${plugin_spec}"

    if openclaw plugins install "$plugin_spec"; then
        success "WhatsApp 插件安装命令已完成"
    else
        warn "插件安装失败，准备清理本地 WhatsApp 插件目录后强制重装。"
        cleanup_whatsapp_plugin_dir
        if openclaw plugins install "$plugin_spec" --force; then
            success "WhatsApp 插件已使用 --force 重新安装"
        else
            warn "插件安装命令失败。请确认 OpenClaw 版本与插件版本兼容后重试。"
            return 1
        fi
    fi
}

restart_gateway_and_status() {
    local stage="$1"

    info "${stage}: 验证配置并重启 OpenClaw Gateway"
    openclaw config validate
    openclaw gateway restart
    openclaw channels status --probe
}

cleanup_whatsapp_plugin_dir() {
    if [ -d "$OPENCLAW_WHATSAPP_PACKAGE_DIR" ]; then
        warn "发现已安装的 WhatsApp 插件目录，将先移除以避免版本不兼容: $OPENCLAW_WHATSAPP_PACKAGE_DIR"
        rm -rf "$OPENCLAW_WHATSAPP_PACKAGE_DIR"
    fi
}

main() {
    local allow_from=""
    local do_login="true"
    local do_install="true"
    local do_restart="true"
    local show_restart_hint="true"
    local plugin_version=""
    local plugin_spec=""
    local openclaw_version=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help) usage ;;
            --allow-from)
                allow_from="${2:-}"
                shift 2
                ;;
            --login)
                do_login="true"
                shift
                ;;
            --no-login)
                do_login="false"
                shift
                ;;
            --install-plugin)
                do_install="true"
                shift
                ;;
            --no-install-plugin)
                do_install="false"
                shift
                ;;
            --restart)
                do_restart="true"
                shift
                ;;
            --no-restart)
                do_restart="false"
                shift
                ;;
            --plugin-version)
                plugin_version="${2:-}"
                shift 2
                ;;
            --plugin-spec)
                plugin_spec="${2:-}"
                shift 2
                ;;
            --no-restart-hint)
                show_restart_hint="false"
                shift
                ;;
            *)
                error "未知参数: $1"
                usage
                ;;
        esac
    done

    check_openclaw
    openclaw_version="$(detect_openclaw_version | head -1 || true)"
    if [ -n "$openclaw_version" ]; then
        info "OpenClaw 版本: ${openclaw_version}"
    else
        warn "无法自动识别 OpenClaw 版本。如果要安装插件，请使用 --plugin-version 或 --plugin-spec 指定。"
    fi

    if [ -z "$allow_from" ]; then
        if [ -t 0 ]; then
            read -r -p "允许发消息的手机号(多个用逗号分隔): " allow_from
        else
            error "缺少必需参数: --allow-from"
            usage
        fi
    fi

    configure_whatsapp "$allow_from"

    if [ "$do_install" = "true" ]; then
        if [ -z "$plugin_spec" ]; then
            if [ -z "$plugin_version" ]; then
                plugin_version="$openclaw_version"
            fi
            if [ -z "$plugin_version" ]; then
                error "无法确定插件版本。请重试并加上 --plugin-version，例如 --plugin-version 2026.5.19"
                exit 1
            fi
            plugin_spec="@openclaw/whatsapp@${plugin_version}"
        fi
        install_plugin "$plugin_spec"
    fi

    success "WhatsApp 白名单配置完成"
    echo ""

    if [ "$show_restart_hint" = "true" ] && [ "$do_restart" != "true" ]; then
        echo "建议执行:"
        echo "  openclaw config validate && openclaw gateway restart"
        echo ""
    fi

    if [ "$do_restart" = "true" ]; then
        restart_gateway_and_status "登录前"
    fi

    if [ "$do_login" = "true" ]; then
        info "开始 WhatsApp 扫码登录"
        openclaw channels login --channel whatsapp --verbose
        if [ "$do_restart" = "true" ]; then
            restart_gateway_and_status "登录后"
        fi
    else
        echo "扫码登录:"
        echo "  openclaw channels login --channel whatsapp"
        echo ""
        echo "状态检查:"
        echo "  openclaw channels status --channel whatsapp"
    fi
}

main "$@"

