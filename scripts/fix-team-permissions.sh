#!/usr/bin/env bash
set -Eeuo pipefail

TEAM_SLUG="${1:-lastcore-agency}"
TEAM_BASE_DIR="${TEAM_BASE_DIR:-$HOME/teams}"
TEAM_ROOT="$TEAM_BASE_DIR/$TEAM_SLUG"
OPENCLAW_CONTAINER_UID="${OPENCLAW_CONTAINER_UID:-1000}"
CURRENT_USER="$(id -un)"
CURRENT_GROUP="$(id -gn)"
CURRENT_UID="$(id -u)"

if [[ ! "$TEAM_SLUG" =~ ^[a-z0-9][a-z0-9-]{1,62}$ ]]; then
  echo "ERROR: invalid team slug: $TEAM_SLUG" >&2
  exit 1
fi

if [[ ! -d "$TEAM_ROOT" ]]; then
  echo "ERROR: team directory not found: $TEAM_ROOT" >&2
  exit 1
fi

if ! command -v setfacl >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y acl
fi

TARGETS=(
  "$TEAM_ROOT/.openclaw"
  "$TEAM_ROOT/.openclaw-auth-profile-secrets"
  "$TEAM_ROOT/shared"
)

sudo mkdir -p "${TARGETS[@]}"
sudo chown -R "$CURRENT_USER:$CURRENT_GROUP" "${TARGETS[@]}"
sudo chmod 700 "$TEAM_ROOT/.openclaw" "$TEAM_ROOT/.openclaw-auth-profile-secrets"
sudo chmod 770 "$TEAM_ROOT/shared"

ACL_SPEC="u:${CURRENT_USER}:rwx,m::rwx,o::---"
if [[ "$CURRENT_UID" != "$OPENCLAW_CONTAINER_UID" ]]; then
  ACL_SPEC="u:${CURRENT_USER}:rwx,u:${OPENCLAW_CONTAINER_UID}:rwx,m::rwx,o::---"
fi

sudo setfacl -Rm "$ACL_SPEC" "${TARGETS[@]}"
sudo setfacl -Rdm "$ACL_SPEC" "${TARGETS[@]}"

if [[ -f "$TEAM_ROOT/.env" ]]; then
  sudo chown "$CURRENT_USER:$CURRENT_GROUP" "$TEAM_ROOT/.env"
  sudo chmod 600 "$TEAM_ROOT/.env"
fi

if [[ -f "$TEAM_ROOT/stack" ]]; then
  sudo chown "$CURRENT_USER:$CURRENT_GROUP" "$TEAM_ROOT/stack"
  sudo chmod 700 "$TEAM_ROOT/stack"
fi

OPENCLAW_IMAGE="ghcr.io/openclaw/openclaw:latest"
if [[ -f "$TEAM_ROOT/.env" ]]; then
  ENV_IMAGE="$(sed -n 's/^OPENCLAW_IMAGE=//p' "$TEAM_ROOT/.env" | tail -n 1)"
  OPENCLAW_IMAGE="${ENV_IMAGE:-$OPENCLAW_IMAGE}"
fi

docker run --rm --user "${OPENCLAW_CONTAINER_UID}:${OPENCLAW_CONTAINER_UID}" \
  -v "$TEAM_ROOT/.openclaw:/check-openclaw" \
  -v "$TEAM_ROOT/.openclaw-auth-profile-secrets:/check-auth" \
  -v "$TEAM_ROOT/shared:/check-shared" \
  --entrypoint sh "$OPENCLAW_IMAGE" \
  -c 'set -eu; touch /check-openclaw/.permission-check /check-auth/.permission-check /check-shared/.permission-check; rm -f /check-openclaw/.permission-check /check-auth/.permission-check /check-shared/.permission-check'

printf 'PERMISSIONS READY\nTeam: %s\nHost user: %s (%s)\nOpenClaw UID: %s\n' \
  "$TEAM_SLUG" "$CURRENT_USER" "$CURRENT_UID" "$OPENCLAW_CONTAINER_UID"
