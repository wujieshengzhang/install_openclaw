#!/bin/bash
# OpenClaw MiniMax-M2.7 Model Config Update & Restart Script

set -e

LOG_PREFIX="[openclaw-update]"
LOG() { echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') - $*"; }

ERROR() { echo "$LOG_PREFIX ERROR: $*" >&2; exit 1; }

# Config files
MODELS_JSON="$HOME/.openclaw/agents/main/agent/models.json"
OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"

# Model config values
CONTEXT_WINDOW=1000000
MAX_TOKENS=65536

LOG "Starting OpenClaw model configuration update..."

# Validate files exist
[[ -f "$MODELS_JSON" ]] || ERROR "models.json not found: $MODELS_JSON"
[[ -f "$OPENCLAW_JSON" ]] || ERROR "openclaw.json not found: $OPENCLAW_JSON"

# Update models.json
if grep -q '"id": "MiniMax-M2.7"' "$MODELS_JSON"; then
    sed -i "s/\"contextWindow\": [0-9]*/\"contextWindow\": $CONTEXT_WINDOW/g" "$MODELS_JSON"
    sed -i "s/\"maxTokens\": [0-9]*/\"maxTokens\": $MAX_TOKENS/g" "$MODELS_JSON"
    LOG "Updated models.json"
else
    ERROR "MiniMax-M2.7 model not found in models.json"
fi

# Update openclaw.json
if grep -q '"id": "MiniMax-M2.7"' "$OPENCLAW_JSON"; then
    sed -i "s/\"contextWindow\": [0-9]*/\"contextWindow\": $CONTEXT_WINDOW/g" "$OPENCLAW_JSON"
    sed -i "s/\"maxTokens\": [0-9]*/\"maxTokens\": $MAX_TOKENS/g" "$OPENCLAW_JSON"
    LOG "Updated openclaw.json"
else
    ERROR "MiniMax-M2.7 model not found in openclaw.json"
fi

openclaw gateway restart

LOG "Done! MiniMax-M2.7 contextWindow=$CONTEXT_WINDOW, maxTokens=$MAX_TOKENS"
