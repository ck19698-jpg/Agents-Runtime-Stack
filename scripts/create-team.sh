#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEAM_SLUG="${1:-}"
OPENCLAW_HOST_PORT="${2:-18789}"
OPENCLAW_CONTAINER_UID="${OPENCLAW_CONTAINER_UID:-1000}"

if [[ -z "$TEAM_SLUG" ]]; then
  read -r -p "Team slug (example: lastcore-agency): " TEAM_SLUG
fi

TEAM_SLUG="$(printf '%s' "$TEAM_SLUG" | tr '[:upper:]' '[:lower:]')"

if [[ ! "$TEAM_SLUG" =~ ^[a-z0-9][a-z0-9-]{1,62}$ ]]; then
  echo "ERROR: team slug must use lowercase letters, numbers, and hyphens." >&2
  exit 1
fi

if [[ ! "$OPENCLAW_HOST_PORT" =~ ^[0-9]+$ ]] || (( OPENCLAW_HOST_PORT < 1024 || OPENCLAW_HOST_PORT > 65535 )); then
  echo "ERROR: port must be between 1024 and 65535." >&2
  exit 1
fi

CURRENT_USER="$(id -un)"
CURRENT_GROUP="$(id -gn)"
TEAM_BASE_DIR="${TEAM_BASE_DIR:-$HOME/teams}"
TEAM_ROOT="$TEAM_BASE_DIR/$TEAM_SLUG"
ENV_FILE="$TEAM_ROOT/.env"
STACK_WRAPPER="$TEAM_ROOT/stack"

if [[ -f "$ENV_FILE" && "${FORCE:-0}" != "1" ]]; then
  echo "ERROR: $ENV_FILE already exists. Set FORCE=1 only when intentionally replacing it." >&2
  exit 1
fi

mkdir -p \
  "$TEAM_ROOT/.openclaw" \
  "$TEAM_ROOT/.openclaw-auth-profile-secrets" \
  "$TEAM_ROOT/.pi/agent" \
  "$TEAM_ROOT/.hermes" \
  "$TEAM_ROOT/shared" \
  "$TEAM_ROOT/logs" \
  "$TEAM_ROOT/backups"

chown -R "$CURRENT_USER:$CURRENT_GROUP" "$TEAM_ROOT"
chmod 700 \
  "$TEAM_ROOT/.openclaw" \
  "$TEAM_ROOT/.openclaw-auth-profile-secrets" \
  "$TEAM_ROOT/.pi" \
  "$TEAM_ROOT/.pi/agent"

# OpenClaw runs as UID 1000 in the official image. ACLs let both the host user
# and the container user read/write without opening the directories to everyone.
if command -v setfacl >/dev/null 2>&1; then
  setfacl -Rm "u:${CURRENT_USER}:rwx,u:${OPENCLAW_CONTAINER_UID}:rwx,m::rwx,o::---" \
    "$TEAM_ROOT/.openclaw" \
    "$TEAM_ROOT/.openclaw-auth-profile-secrets"
  setfacl -Rdm "u:${CURRENT_USER}:rwx,u:${OPENCLAW_CONTAINER_UID}:rwx,m::rwx,o::---" \
    "$TEAM_ROOT/.openclaw" \
    "$TEAM_ROOT/.openclaw-auth-profile-secrets"
else
  echo "WARNING: setfacl is unavailable; OpenClaw directory permissions may need manual adjustment." >&2
fi

GATEWAY_TOKEN="$(openssl rand -hex 32)"
KEYRING_PASSWORD="$(openssl rand -hex 32)"

cat > "$ENV_FILE" <<EOF
# =============================================================================
# AGENTS RUNTIME STACK - $TEAM_SLUG
# Never commit this file.
# =============================================================================

# -----------------------------------------------------------------------------
# Team identity and paths
# -----------------------------------------------------------------------------
TEAM_SLUG=$TEAM_SLUG
COMPOSE_PROJECT_NAME=agents-$TEAM_SLUG
TEAM_ROOT=$TEAM_ROOT
TEAM_SHARED_DIR=$TEAM_ROOT/shared
TZ=Asia/Bangkok

# -----------------------------------------------------------------------------
# OpenClaw runtime
# -----------------------------------------------------------------------------
OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:latest
OPENCLAW_HOST_PORT=$OPENCLAW_HOST_PORT
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_BRIDGE_PORT=18790
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=0
OPENCLAW_CONFIG_DIR=$TEAM_ROOT/.openclaw
OPENCLAW_WORKSPACE_DIR=$TEAM_ROOT/shared
OPENCLAW_AUTH_PROFILE_SECRET_DIR=$TEAM_ROOT/.openclaw-auth-profile-secrets
OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
GOG_KEYRING_PASSWORD=$KEYRING_PASSWORD
GATEWAY_CONTROLUI_ALLOWEDORIGINS=

# -----------------------------------------------------------------------------
# Pi Operator and Hermes state
# -----------------------------------------------------------------------------
PI_STATE_DIR=$TEAM_ROOT/.pi/agent
HERMES_STATE_DIR=$TEAM_ROOT/.hermes

# -----------------------------------------------------------------------------
# Cloud model providers
# -----------------------------------------------------------------------------
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
OPENROUTER_API_KEY=
GROQ_API_KEY=
ZAI_API_KEY=
OPENCODE_API_KEY=
COPILOT_API_KEY=
GEMINI_API_KEY=
GOOGLE_API_KEY=
MISTRAL_API_KEY=
NVIDIA_API_KEY=
AI_GATEWAY_API_KEY=
SYNTHETIC_API_KEY=
MINIMAX_API_KEY=
ELEVENLABS_API_KEY=

# -----------------------------------------------------------------------------
# Local llama.cpp / LlamaBarn
# Docker reaches host services through host.docker.internal.
# -----------------------------------------------------------------------------
LLAMACPP_BASE_URL=http://host.docker.internal:8080/v1
LLAMACPP_API_KEY=dummy
LLAMACPP_MODEL_ID=
LLAMACPP_MODEL_NAME=
LLAMACPP_CONTEXT_WINDOW=32768
LLAMACPP_MAX_TOKENS=4096

# -----------------------------------------------------------------------------
# Local Ollama
# -----------------------------------------------------------------------------
OLLAMA_BASE_URL=http://host.docker.internal:11434
OLLAMA_API_KEY=ollama-local
OLLAMA_MODEL_ID=
OLLAMA_MODEL_NAME=

# -----------------------------------------------------------------------------
# ModelArk / BytePlus
# -----------------------------------------------------------------------------
MODELARK_BASE_URL=https://ark.ap-southeast.bytepluses.com/api/v3
MODELARK_API_KEY=

# -----------------------------------------------------------------------------
# Typhoon
# -----------------------------------------------------------------------------
TYPHOON_BASE_URL=https://api.opentyphoon.ai/v1
TYPHOON_API_KEY=

# -----------------------------------------------------------------------------
# Telegram command center
# -----------------------------------------------------------------------------
TELEGRAM_COMMAND_CENTER_CHAT_ID=
TELEGRAM_SIRIUS_TOKEN=
TELEGRAM_SIRIUS_TOPIC_ID=
TELEGRAM_DRACO_TOKEN=
TELEGRAM_DRACO_TOPIC_ID=
TELEGRAM_POLARIS_TOKEN=
TELEGRAM_POLARIS_TOPIC_ID=
TELEGRAM_ANTARES_TOKEN=
TELEGRAM_ANTARES_TOPIC_ID=
TELEGRAM_ALTAIR_TOKEN=
TELEGRAM_ALTAIR_TOPIC_ID=
TELEGRAM_CAPELLA_TOKEN=
TELEGRAM_CAPELLA_TOPIC_ID=
TELEGRAM_BOT_TOKEN=

# -----------------------------------------------------------------------------
# LINE channels
# Each channel needs a unique variable name. Duplicate LINE_CHANNEL_ID keys
# overwrite one another in a normal .env file.
# -----------------------------------------------------------------------------
LINE_SIRIUS_CHANNEL_ID=
LINE_SIRIUS_CHANNEL_ACCESS_TOKEN=
LINE_SIRIUS_CHANNEL_SECRET=
LINE_DRACO_CHANNEL_ID=
LINE_DRACO_CHANNEL_ACCESS_TOKEN=
LINE_DRACO_CHANNEL_SECRET=
LINE_POLARIS_CHANNEL_ID=
LINE_POLARIS_CHANNEL_ACCESS_TOKEN=
LINE_POLARIS_CHANNEL_SECRET=
LINE_ANTARES_CHANNEL_ID=
LINE_ANTARES_CHANNEL_ACCESS_TOKEN=
LINE_ANTARES_CHANNEL_SECRET=
LINE_ALTAIR_CHANNEL_ID=
LINE_ALTAIR_CHANNEL_ACCESS_TOKEN=
LINE_ALTAIR_CHANNEL_SECRET=
LINE_CAPELLA_CHANNEL_ID=
LINE_CAPELLA_CHANNEL_ACCESS_TOKEN=
LINE_CAPELLA_CHANNEL_SECRET=
EOF
chmod 600 "$ENV_FILE"

cat > "$STACK_WRAPPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
TEAM_ROOT="$TEAM_ROOT"
REPO_ROOT="$REPO_ROOT"
PROJECT="agents-$TEAM_SLUG"
COMPOSE=(docker compose --env-file "\$TEAM_ROOT/.env" -f "\$REPO_ROOT/compose.yaml" -p "\$PROJECT")

case "\${1:-status}" in
  up)
    "\${COMPOSE[@]}" up -d openclaw-gateway
    ;;
  down)
    "\${COMPOSE[@]}" down
    ;;
  restart)
    "\${COMPOSE[@]}" restart openclaw-gateway
    ;;
  status)
    "\${COMPOSE[@]}" ps
    ;;
  logs)
    "\${COMPOSE[@]}" logs -f --tail=200 openclaw-gateway
    ;;
  onboard)
    "\${COMPOSE[@]}" run --rm --no-deps --entrypoint node openclaw-gateway \
      dist/index.js onboard --mode local --no-install-daemon
    ;;
  pi)
    "\${COMPOSE[@]}" run --rm pi-operator
    ;;
  cli)
    shift
    "\${COMPOSE[@]}" run --rm openclaw-cli "\$@"
    ;;
  ready)
    curl -fsS "http://127.0.0.1:$OPENCLAW_HOST_PORT/healthz"
    printf '\n'
    curl -fsS "http://127.0.0.1:$OPENCLAW_HOST_PORT/readyz"
    printf '\n'
    ;;
  *)
    echo "Usage: \$0 {up|down|restart|status|logs|onboard|pi|cli|ready}" >&2
    exit 1
    ;;
esac
EOF
chmod 700 "$STACK_WRAPPER"

printf '\nTEAM CREATED\n'
printf 'Team: %s\n' "$TEAM_SLUG"
printf 'State: %s\n' "$TEAM_ROOT"
printf 'Port: 127.0.0.1:%s\n' "$OPENCLAW_HOST_PORT"
printf 'Control: %s\n' "$STACK_WRAPPER"
printf '\nNext command:\n%s onboard\n' "$STACK_WRAPPER"
