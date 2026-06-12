#!/bin/bash
#============================================================================
# OpenClaw Telegram Multi-Agent 一键配置脚本
#============================================================================

set -e

SCRIPT_VERSION="1.0.7"
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
BACKUP_CONFIG="$HOME/.openclaw/openclaw.json.backup-$(date +%Y%m%d_%H%M%S)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

#============================================================================
# 辅助函数
#============================================================================

usage() {
    cat << EOF
🦞 OpenClaw Telegram Multi-Agent 配置脚本 v${SCRIPT_VERSION}

用法: $0 [选项]

选项:
    --main NAME:TOKEN:@USERNAME  主 Bot 配置 (格式: 名称:Token:@Username)
    --user-id ID                 你的 Telegram User ID (必需)
    --group-id ID                群组 ID (必需, 如 -1001234567890)
    --bot NAME:TOKEN:@USERNAME   子 Bot 配置 (格式: 名称:Token:@Username)
                                 可以多次使用来添加多个 Bot
    --help                      显示此帮助信息

示例:
    # 配置 2 个子 Bot (coder 和 writer)
    $0 --main "main:xxx:@my_main_bot" --user-id "123456" --group-id "-1001234567890" \
       --bot "coder:yyy:@coder_bot" --bot "writer:zzz:@writer_bot"

    # 交互式模式 (不带参数运行)
    $0

EOF
    exit 0
}

check_openclaw() {
    if ! command -v openclaw &> /dev/null; then
        error "OpenClaw 未安装. 请先运行: npm install -g openclaw"
        exit 1
    fi
    info "OpenClaw 版本: $(openclaw -v 2>/dev/null | head -1)"
}

backup_config() {
    if [ -f "$OPENCLAW_CONFIG" ]; then
        cp "$OPENCLAW_CONFIG" "$BACKUP_CONFIG"
        success "已备份当前配置到: $BACKUP_CONFIG"
    fi
}

generate_id() {
    local name="$1"
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/^-+/-/;s/-+$//'
}

create_workspace_dirs() {
    local agent_id="$1"
    local workspace="$HOME/.openclaw/workspace-$agent_id"
    local agent_dir="$HOME/.openclaw/agents/$agent_id/agent"

    mkdir -p "$workspace"
    mkdir -p "$agent_dir"
    info "创建工作区: $workspace"
}

generate_identity_md() {
    local agent_id="$1"
    local nickname="$2"
    local username="$3"
    local purpose="$4"
    local workspace="$HOME/.openclaw/workspace-$agent_id"

    cat > "$workspace/IDENTITY.md" << EOF
# IDENTITY.md - Who Am I?

- **Name:** $nickname
- **Telegram:** $username
- **Role:** $purpose 专家
EOF
    success "创建 IDENTITY.md: $workspace/IDENTITY.md"
}

generate_soul_md() {
    local agent_id="$1"
    local is_main="$2"
    local sub_bots="$3"
    local username="$4"
    local purpose="$5"
    local sub_bots_roster="$6"
    local workspace="$HOME/.openclaw/workspace-$agent_id"

    if [ "$is_main" = "true" ]; then
        if [ -z "$sub_bots" ]; then
            cat > "$workspace/SOUL.md" << EOF
# SOUL.md - 我是谁与如何行为

## 身份
我是你的 Telegram 主助手。

## 核心能力
- 理解和分析用户需求
- 在私聊和被 @mention 的群聊中直接回复
- 根据当前对话上下文完成任务

## 行为规则
- 群聊: 仅在被 @mention 时响应
- 私聊: 随时响应
- 直接处理用户请求，不要尝试分配给子 Bot

## 单 Bot 模式 (重要!)
当前没有配置子 Bot 或子 Agent。
- 不要声称可以安排 planning、writing 或其他子 Bot
- 不要使用 sessions_send、sessions_list 或 sessions_spawn 来派单
- 如果用户要求多 Bot 协作，说明当前只配置了主 Bot，需要重新运行脚本并添加 --bot 配置
EOF
            success "创建 SOUL.md: $workspace/SOUL.md"
            return
        fi

        local silent_rules=""
        if [ -n "$sub_bots" ]; then
            for sb in $sub_bots; do
                silent_rules="${silent_rules}
- 当 $sb 被 @mention 时, 不要回复, 保持沉默"
            done
        fi

        cat > "$workspace/SOUL.md" << EOF
# SOUL.md - 我是谁与如何行为

## 身份
我是你的主助手,负责协调和管理子 Bot。

## 核心能力
- 理解和分析复杂任务
- 协调多个专业子 Bot
- 使用 sessions_list 查找子 Agent 的当前群会话
- 使用 sessions_send 工具向子 Agent 的会话发送任务

## 子 Bot 列表
可用子 Bot:
${sub_bots_roster:-无}

## Agent 与 Telegram 的关系 (重要!)
- 上面列表中的名称是给人看的，真正可派单的是 OpenClaw 内部 agent id
- 使用 sessions_send 时，目标必须是 sessions_list 查到的 sessionKey 或 sessionId
- 不要把 Telegram @用户名 当作 sessions_send 目标
- 不要在 Telegram 群里 @子 bot 来触发 bot-to-bot 协作
- 不要使用 sessions_spawn 做常规派单；这里需要的是持久 agent 会话派单

## 任务分配流程 (重要!)
当用户要我安排子 Bot 完成任务时:
1. 先判断目标 agent id，例如 planning 或 writing
2. 使用 sessions_list 查找该 agent 的可见会话
3. 优先选择与当前用户请求同一个 Telegram 群对应的 group session
4. 如果找不到同群 Telegram group session，回复用户「请先在本群 @对应子 bot 说一句 ping，让它建立群会话」
5. 找到 sessionKey 或 sessionId 后，使用 sessions_send 发送任务，timeoutSeconds 设为 0
6. 任务内容必须包含：
   - 这是主 bot 通过 sessions_send 分配的内部任务
   - 原始用户需求
   - 结果必须发回本任务来源群
   - 不要回复给主 bot
7. 任务发送后，直接回复用户「任务已安排给 @XXX」即可结束
8. **不要等待 sessions_send 的返回结果，不要处理超时状态提示**

## 重要原则
- 任务一旦安排给子 Bot，立即结束，不要介入
- 完全忽略 sessions_send 的超时或错误返回
- 让子 Bot 直接在本任务来源群里回复用户
- 不要自行编造子 bot 没注册；如果 sessions_list 找不到同群 session，就提示用户先 @子 bot 预热群会话

## 沉默规则 (重要!)
当群里有其他子 Bot 被 @mention 时:
${silent_rules}
- 不要试图回答该问题
- 等待该子 Bot 响应
- 除非被明确要求,不要介入子 Bot 的专业领域
EOF
    else
        cat > "$workspace/SOUL.md" << EOF
# SOUL.md - 我是谁与如何行为

## 身份
我是 $username, 专业 $purpose 助手。

## 核心能力
- $purpose 相关任务
- 只在被 @mention 时响应群聊消息
- 私聊随时响应
- 通过 sessions_send 收到主 Bot 分配的任务

## 行为规则
- 群聊: 仅在被 @mention 时响应
- 私聊: 随时响应

## 任务执行 (重要!)
当收到 [Inter-session message] 或 sessions_send 任务时:
1. 这表示主 Bot 分配了内部任务，不是普通闲聊
2. 读取任务中的原始用户需求和来源群说明
3. 执行任务
4. 如果该任务进入的是 Telegram 群 session，直接把最终结果正常回复到这个群
5. 如果无法判断来源群或当前不是群 session，回复主 Bot：「没有可用的来源群会话，无法直接发群里」
6. 发完后任务结束，不要等待进一步指令

## 任务完成
- 完成子任务后优先直接回复结果到主 Bot 分配任务的那个群
- 等待主 Bot 的下一步指令或继续执行
EOF
    fi
    success "创建 SOUL.md: $workspace/SOUL.md"
}

generate_openclaw_json() {
    local main_token="$1"
    local user_id="$2"
    local group_id="$3"
    local bot_configs="$4"

    python3 << PYEOF
import json
import os
import shutil
from datetime import datetime

main_token = """$main_token"""
user_id = """$user_id"""
group_id = """$group_id"""
bot_configs = """$bot_configs"""

bots = []
for bot in bot_configs.split(','):
    idx = bot.find(':')
    if idx > 0:
        name = bot[:idx].strip()
        rest = bot[idx+1:].strip()
        # 用最后一个冒号分割 token 和 username
        last_colon = rest.rfind(':')
        if last_colon > 0:
            token = rest[:last_colon].strip()
            username = rest[last_colon+1:].strip()
        else:
            token = rest
            username = f"@{name}_bot"
        bot_id = name.lower().replace(' ', '-')
        bot_id = ''.join(c if c.isalnum() or c == '-' else '-' for c in bot_id)
        bot_id = bot_id.strip('-')
        bots.append({'name': name, 'token': token, 'id': bot_id, 'username': username})

# 加载现有配置
config_path = os.path.expanduser('$OPENCLAW_CONFIG')
if os.path.exists(config_path):
    # 备份
    backup_path = config_path + f".backup-multiagent-{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    shutil.copy(config_path, backup_path)
    print(f"已备份配置到: {backup_path}")
    with open(config_path, 'r') as f:
        config = json.load(f)
else:
    config = {}

# ========== 清理旧的 telegram 相关配置 ==========

# 1. 清理 agents.list - 只保留 main，其他 telegram agents 全删
if 'agents' not in config:
    config['agents'] = {}
if 'list' not in config.get('agents', {}):
    config['agents']['list'] = []
# 始终清理 telegram agents，只保留 main（修复：每次运行都清理）
config['agents']['list'] = [a for a in config['agents']['list'] if a.get('id') == 'main']
print("已清理旧的 telegram agents")

# 2. 清理 bindings - 移除所有 telegram channel 的 binding
if 'bindings' in config:
    config['bindings'] = [b for b in config['bindings'] if b.get('match', {}).get('channel') != 'telegram']
    print("已清理旧的 telegram bindings")

# 3. 清理 channels.telegram - 完全替换
if 'channels' in config and 'telegram' in config['channels']:
    # 保留其他 channel
    other_channels = {k: v for k, v in config['channels'].items() if k != 'telegram'}
    config['channels'] = other_channels

# ========== 添加新的配置 ==========

# 更新 agents
if 'agents' not in config:
    config['agents'] = {}
if 'defaults' not in config['agents']:
    config['agents']['defaults'] = {}
config['agents']['defaults']['thinkingDefault'] = 'adaptive'
if 'workspace' not in config['agents']['defaults']:
    config['agents']['defaults']['workspace'] = os.path.expanduser('$HOME/.openclaw/workspace')

# 确保 main agent 存在
main_agent = None
for a in config['agents']['list']:
    if a.get('id') == 'main':
        main_agent = a
        break
if main_agent is None:
    main_agent = {'id': 'main'}
    config['agents']['list'].append(main_agent)

main_agent['workspace'] = os.path.expanduser('$HOME/.openclaw/workspace-main')
main_agent['agentDir'] = os.path.expanduser('$HOME/.openclaw/agents/main/agent')
main_agent['subagents'] = {'allowAgents': [b['id'] for b in bots]}

# 添加子 bots 到 agents.list
for bot in bots:
    config['agents']['list'].append({
        'id': bot['id'],
        'workspace': os.path.expanduser(f"$HOME/.openclaw/workspace-{bot['id']}"),
        'agentDir': os.path.expanduser(f"$HOME/.openclaw/agents/{bot['id']}/agent")
    })

# 添加 bindings - 先清理旧的 telegram bindings（修复：每次运行都清理）
config['bindings'] = [b for b in config.get('bindings', []) if b.get('match', {}).get('channel') != 'telegram']
config['bindings'].append({'agentId': 'main', 'match': {'channel': 'telegram', 'accountId': 'default'}})
for bot in bots:
    config['bindings'].append({'agentId': bot['id'], 'match': {'channel': 'telegram', 'accountId': bot['id']}})

# 更新 tools
config['tools'] = config.get('tools', {})
config['tools']['sessions'] = {'visibility': 'all'}
config['tools']['agentToAgent'] = {'enabled': True, 'allow': ['main'] + [b['id'] for b in bots]}

# 更新 session
config['session'] = {'dmScope': 'main'}

# 添加或更新 gateway
if 'gateway' not in config:
    config['gateway'] = {
        'mode': 'local',
        'port': 11403,
        'bind': 'loopback',
        'reload': {'mode': 'restart'}
    }

# 添加 channels.telegram
config['channels'] = config.get('channels', {})
config['channels']['telegram'] = {
    'enabled': True,
    'dmPolicy': 'pairing',
    'groupAllowFrom': [user_id],
    'streaming': {'mode': 'partial'},
    'groups': {group_id: {'requireMention': True, 'allowFrom': [user_id]}},
    'accounts': {
        'default': {
            'botToken': main_token,
            'dmPolicy': 'pairing',
            'groupPolicy': 'allowlist',
            'groupAllowFrom': [user_id],
            'allowFrom': [user_id],
            'streaming': {'mode': 'partial'}
        }
    }
}

for bot in bots:
    config['channels']['telegram']['accounts'][bot['id']] = {
        'botToken': bot['token'],
        'enabled': True,
        'commands': {'native': False, 'nativeSkills': False},
        'dmPolicy': 'allowlist',
        'allowFrom': [user_id],
        'groupPolicy': 'allowlist',
        'groupAllowFrom': [user_id],
        'streaming': {'mode': 'partial'}
    }

with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
print("配置生成成功")
PYEOF

    success "生成 openclaw.json 配置"
}

interactive_mode() {
    echo ""
    echo "============================================"
    echo "   🦞 OpenClaw Telegram Multi-Agent 配置向导"
    echo "============================================"
    echo ""

    read -p "主 Bot 配置 (名称:Token:@Username): " main_config
    read -p "你的 Telegram User ID (from @userinfobot): " user_id
    read -p "群组 ID (如 -1001234567890): " group_id

    echo ""
    echo "--- 子 Bot 配置 ---"
    echo "格式: 名称:Token:Username (如 coder:abc123:@coder_bot)"
    echo "Username 是 @BotFather 给你的 bot @用户名(包含@)"
    echo "输入空行结束子 Bot 配置"
    echo ""

    local bot_configs=""
    while true; do
        read -p "子 Bot (名称:Token:Username): " input
        if [ -z "$input" ]; then
            break
        fi
        if [ -z "$bot_configs" ]; then
            bot_configs="$input"
        else
            bot_configs="$bot_configs,$input"
        fi
        echo "  已添加: $input"
    done

    if [ -z "$bot_configs" ]; then
        warn "未添加子 Bot，将只创建主 Bot 配置"
    fi

    # 解析 main 配置
    local main_name="" main_token="" main_username=""
    if [ -n "$main_config" ]; then
        idx="${main_config%%:*}"
        rest="${main_config#*:}"
        main_name="$idx"
        last_colon="${rest##*:}"
        token_part="${rest%:*}"
        main_token="$token_part"
        main_username="$last_colon"
    fi

    echo ""
    info "收集到的配置:"
    echo "  主 Bot 配置: ${main_config}"
    echo "  User ID: $user_id"
    echo "  群组 ID: $group_id"
    echo "  子 Bots: $bot_configs"

    generate_config "$main_token" "$user_id" "$group_id" "$bot_configs" "$main_username" "$main_name"
}

generate_config() {
    local main_token="$1"
    local user_id="$2"
    local group_id="$3"
    local bot_configs="$4"
    local main_username="$5"
    local main_name="$6"

    # 让 Python 解析所有 bot 配置，Bash 只负责创建文件
    if [ -n "$bot_configs" ]; then
        python3 << PYEOF
import json

bots = []
for bot in """$bot_configs""".split(','):
    idx = bot.find(':')
    if idx > 0:
        name = bot[:idx].strip()
        rest = bot[idx+1:].strip()
        # 用最后一个冒号分割 token 和 username
        last_colon = rest.rfind(':')
        if last_colon > 0:
            token = rest[:last_colon].strip()
            username = rest[last_colon+1:].strip()
        else:
            token = rest
            username = f"@{name}_bot"
        bot_id = name.lower().replace(' ', '-')
        bot_id = ''.join(c if c.isalnum() or c == '-' else '-' for c in bot_id)
        bot_id = bot_id.strip('-')
        # 输出: bot_id|name|username|token
        print(f"{bot_id}|{name}|{username}|{token}")
PYEOF
    fi > /tmp/bot_parse_output.txt

    local sub_bots_list=""
    local sub_bots_roster=""
    local created_workspaces=""
    if [ -n "$bot_configs" ]; then
        while IFS='|' read -r bot_id name username token; do
            [ -z "$bot_id" ] && continue
            local nickname="$(printf '%s' "$name" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"

            create_workspace_dirs "$bot_id"
            generate_identity_md "$bot_id" "$nickname" "$username" "$name"
            generate_soul_md "$bot_id" "false" "" "$username" "$name" ""

            if [ -n "$sub_bots_list" ]; then
                sub_bots_list="$sub_bots_list $username"
                sub_bots_roster="$sub_bots_roster
- **$name** ($username)"
            else
                sub_bots_list="$username"
                sub_bots_roster="- **$name** ($username)"
            fi

            created_workspaces="$created_workspaces $bot_id"
        done < /tmp/bot_parse_output.txt
        rm -f /tmp/bot_parse_output.txt
    fi

    # 创建主Agent工作区（在获取sub_bots_list之后）
    create_workspace_dirs "main"
    generate_identity_md "main" "主助手" "$main_username" "协调管理"
    generate_soul_md "main" "true" "$sub_bots_list" "$main_username" "协调管理" "$sub_bots_roster"

    generate_openclaw_json "$main_token" "$user_id" "$group_id" "$bot_configs"

    success "配置完成!"
    echo ""
    echo "============================================"
    echo "   📋 创建的文件"
    echo "============================================"
    echo ""
    echo "工作区:"
    echo "  - ~/.openclaw/workspace-main/"
    for wid in $created_workspaces; do
        echo "  - ~/.openclaw/workspace-$wid/"
    done
    echo ""
    echo "配置文件:"
    echo "  - $OPENCLAW_CONFIG"
    echo ""
    echo "============================================"
    echo "   📋 下一步操作"
    echo "============================================"
    echo ""
    echo "1. 重启 OpenClaw Gateway:"
    echo "   openclaw config validate && openclaw gateway restart && openclaw channels status --probe"
    echo ""
    echo "2. 在 Telegram 中与主 Bot 私聊测试"
    echo ""
    echo "3. 在群组中 @主bot 测试"
    if [ -n "$created_workspaces" ]; then
        echo ""
        echo "4. 多 Bot 模式: 先在目标群里 @每个子 Bot 说一句 ping，预热它们的群会话"
    fi
    echo ""
    echo "注意: 本脚本会覆盖对应 workspace 的 SOUL.md 和 IDENTITY.md；旧 openclaw.json 已自动备份"
    echo ""
    echo "============================================"
}

main() {
    local main_config=""
    local user_id=""
    local group_id=""
    local bot_configs=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help) usage ;;
            --main) main_config="$2"; shift 2 ;;
            --user-id) user_id="$2"; shift 2 ;;
            --group-id) group_id="$2"; shift 2 ;;
            --bot)
                if [ -z "$bot_configs" ]; then
                    bot_configs="$2"
                else
                    bot_configs="$bot_configs,$2"
                fi
                shift 2 ;;
            *) error "未知参数: $1"; usage ;;
        esac
    done

    # 解析 main 配置: NAME:TOKEN:@USERNAME
    local main_name="" main_token="" main_username=""
    if [ -n "$main_config" ]; then
        # 用第一个冒号分割 name 和 rest
        idx="${main_config%%:*}"
        rest="${main_config#*:}"
        main_name="$idx"
        # 用最后一个冒号分割 token 和 username
        last_colon="${rest##*:}"
        token_part="${rest%:*}"
        main_token="$token_part"
        main_username="$last_colon"
    fi

    if [ -z "$main_config" ] || [ -z "$user_id" ] || [ -z "$group_id" ]; then
        if [ -t 0 ]; then
            interactive_mode
        else
            error "缺少必需参数: --main, --user-id, --group-id"
            echo ""
            usage
        fi
        exit 0
    fi

    check_openclaw
    backup_config
    generate_config "$main_token" "$user_id" "$group_id" "$bot_configs" "$main_username" "$main_name"
}

main "$@"

