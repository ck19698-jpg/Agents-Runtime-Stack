#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEAM_SLUG="${1:-}"
OPENCLAW_HOST_PORT="${2:-18789}"

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

chmod 700 \
  "$TEAM_ROOT/.openclaw" \
  "$TEAM_ROOT/.openclaw-auth-profile-secrets" \
  "$TEAM_ROOT/.pi" \
  "$TEAM_ROOT/.pi/agent"

GATEWAY_TOKEN="$(openssl rand -hex 32)"
KEYRING_PASSWORD="$(openssl rand -hex 32)"

cat > "$ENV_FILE" <<EOF
TEAM_SLUG=$TEAM_SLUG
COMPOSE_PROJECT_NAME=agents-$TEAM_SLUG
TEAM_ROOT=$TEAM_ROOT
TEAM_SHARED_DIR=$TEAM_ROOT/shared

OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:latest
OPENCLAW_HOST_PORT=$OPENCLAW_HOST_PORT
OPENCLAW_CONFIG_DIR=$TEAM_ROOT/.openclaw
OPENCLAW_WORKSPACE_DIR=$TEAM_ROOT/shared
OPENCLAW_AUTH_PROFILE_SECRET_DIR=$TEAM_ROOT/.openclaw-auth-profile-secrets
OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
GOG_KEYRING_PASSWORD=$KEYRING_PASSWORD

PI_STATE_DIR=$TEAM_ROOT/.pi/agent

TZ=Asia/Bangkok

ANTHROPIC_API_KEY=
OPENAI_API_KEY=
OPENROUTER_API_KEY=
MISTRAL_API_KEY=
NVIDIA_API_KEY=
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
