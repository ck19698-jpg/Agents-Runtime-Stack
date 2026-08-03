#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEAM_SLUG="${1:-lastcore-agency}"
TEAM_BASE_DIR="${TEAM_BASE_DIR:-$HOME/teams}"
TEAM_ROOT="$TEAM_BASE_DIR/$TEAM_SLUG"
ENV_FILE="$TEAM_ROOT/.env"
ENV_TEMPLATE="$REPO_ROOT/.env.example"
COMPOSE_FILE="$REPO_ROOT/compose.yaml"

if [[ ! "$TEAM_SLUG" =~ ^[a-z0-9][a-z0-9-]{1,62}$ ]]; then
  echo "ERROR: invalid team slug: $TEAM_SLUG" >&2
  exit 1
fi

[[ -d "$TEAM_ROOT" ]] || { echo "ERROR: team directory not found: $TEAM_ROOT" >&2; exit 1; }
[[ -f "$ENV_TEMPLATE" ]] || { echo "ERROR: env template not found: $ENV_TEMPLATE" >&2; exit 1; }
[[ -f "$COMPOSE_FILE" ]] || { echo "ERROR: compose file not found: $COMPOSE_FILE" >&2; exit 1; }

# Repair and verify host/container access exactly once before onboarding.
bash "$SCRIPT_DIR/fix-team-permissions.sh" "$TEAM_SLUG"

mkdir -p "$TEAM_ROOT/backups"

BACKUP_FILE=""
if [[ -f "$ENV_FILE" ]]; then
  BACKUP_FILE="$TEAM_ROOT/backups/.env.before-prepare-$(date +%Y%m%d-%H%M%S)"
  cp -p "$ENV_FILE" "$BACKUP_FILE"
  chmod 600 "$BACKUP_FILE"
fi

declare -A OLD_VALUE=()
declare -A OLD_SEEN=()

if [[ -f "$ENV_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      OLD_VALUE["$key"]="${BASH_REMATCH[2]}"
      OLD_SEEN["$key"]=1
    fi
  done < "$ENV_FILE"
fi

existing_or_default() {
  local key="$1"
  local fallback="$2"
  if [[ -n "${OLD_SEEN[$key]+x}" ]]; then
    printf '%s' "${OLD_VALUE[$key]}"
  else
    printf '%s' "$fallback"
  fi
}

gateway_token="$(existing_or_default OPENCLAW_GATEWAY_TOKEN '')"
keyring_password="$(existing_or_default GOG_KEYRING_PASSWORD '')"
[[ -n "$gateway_token" && "$gateway_token" != "CHANGE_ME" ]] || gateway_token="$(openssl rand -hex 32)"
[[ -n "$keyring_password" && "$keyring_password" != "CHANGE_ME" ]] || keyring_password="$(openssl rand -hex 32)"

TMP_ENV="$(mktemp "$TEAM_ROOT/.env.prepare.XXXXXX")"
trap 'rm -f "$TMP_ENV"' EXIT

declare -A TEMPLATE_SEEN=()

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    template_value="${BASH_REMATCH[2]}"
    TEMPLATE_SEEN["$key"]=1

    case "$key" in
      TEAM_SLUG) value="$TEAM_SLUG" ;;
      COMPOSE_PROJECT_NAME) value="agents-$TEAM_SLUG" ;;
      TEAM_ROOT) value="$TEAM_ROOT" ;;
      TEAM_SHARED_DIR) value="$TEAM_ROOT/shared" ;;
      OPENCLAW_CONFIG_DIR) value="$TEAM_ROOT/.openclaw" ;;
      OPENCLAW_WORKSPACE_DIR) value="$TEAM_ROOT/shared" ;;
      OPENCLAW_AUTH_PROFILE_SECRET_DIR) value="$TEAM_ROOT/.openclaw-auth-profile-secrets" ;;
      PI_STATE_DIR) value="$TEAM_ROOT/.pi/agent" ;;
      HERMES_STATE_DIR) value="$TEAM_ROOT/.hermes" ;;
      OPENCLAW_GATEWAY_TOKEN) value="$gateway_token" ;;
      GOG_KEYRING_PASSWORD) value="$keyring_password" ;;
      *) value="$(existing_or_default "$key" "$template_value")" ;;
    esac

    printf '%s=%s\n' "$key" "$value" >> "$TMP_ENV"
  else
    printf '%s\n' "$line" >> "$TMP_ENV"
  fi
done < "$ENV_TEMPLATE"

# Keep custom or legacy variables that are not yet represented by the template.
mapfile -t EXTRA_KEYS < <(printf '%s\n' "${!OLD_SEEN[@]}" | sort)
EXTRA_WRITTEN=0
for key in "${EXTRA_KEYS[@]}"; do
  [[ -n "$key" ]] || continue
  if [[ -z "${TEMPLATE_SEEN[$key]+x}" ]]; then
    if (( EXTRA_WRITTEN == 0 )); then
      {
        printf '\n# -----------------------------------------------------------------------------\n'
        printf '# Preserved custom or legacy variables\n'
        printf '# Review and rename these manually when mapping old business aliases.\n'
        printf '# -----------------------------------------------------------------------------\n'
      } >> "$TMP_ENV"
      EXTRA_WRITTEN=1
    fi
    printf '%s=%s\n' "$key" "${OLD_VALUE[$key]}" >> "$TMP_ENV"
  fi
done

mv "$TMP_ENV" "$ENV_FILE"
trap - EXIT
chmod 600 "$ENV_FILE"

# Reject accidental duplicate keys. Normal dotenv readers silently keep one value,
# which is an impressively bad way to discover a channel was overwritten.
duplicates="$(awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/{count[$1]++} END{for (key in count) if (count[key] > 1) print key}' "$ENV_FILE" | sort)"
if [[ -n "$duplicates" ]]; then
  printf 'ERROR: duplicate env keys detected:\n%s\n' "$duplicates" >&2
  exit 1
fi

project="agents-$TEAM_SLUG"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "$project" config >/dev/null

printf '\nTEAM PREPARED\n'
printf 'Team: %s\n' "$TEAM_SLUG"
printf 'Environment: %s\n' "$ENV_FILE"
if [[ -n "$BACKUP_FILE" ]]; then
  printf 'Backup: %s\n' "$BACKUP_FILE"
fi
printf 'Permissions: verified with OpenClaw container UID\n'
printf 'Compose: valid\n'
printf '\nNext command:\n%s onboard\n' "$TEAM_ROOT/stack"
