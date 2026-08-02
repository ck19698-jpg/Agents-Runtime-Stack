#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/ck19698-jpg/Agents-Runtime-Stack.git"
INSTALL_DIR="${AGENTS_STACK_HOME:-$HOME/Agents-Runtime-Stack}"
TEAM_SLUG="${TEAM_SLUG:-}"
OPENCLAW_HOST_PORT="${OPENCLAW_HOST_PORT:-18789}"
SKIP_ONBOARDING="${SKIP_ONBOARDING:-0}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ "${EUID}" -eq 0 ]]; then
  die "Run this installer as the normal Ubuntu user, not root. It will use sudo only when needed."
fi

if [[ ! -r /etc/os-release ]]; then
  die "Cannot detect the operating system."
fi

# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  die "This installer currently supports Ubuntu only. Detected: ${ID:-unknown}."
fi

command -v sudo >/dev/null 2>&1 || die "sudo is required."

log "Installing base packages"
sudo apt-get update
sudo apt-get install -y ca-certificates curl git openssl

if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine and Docker Compose plugin"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker
fi

if ! docker compose version >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y docker-compose-plugin
fi

DOCKER_ACCESS_PENDING=0
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  log "Adding $USER to the docker group"
  sudo usermod -aG docker "$USER"
  DOCKER_ACCESS_PENDING=1
fi

log "Installing Agents-Runtime-Stack"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" pull --ff-only
elif [[ -d "$INSTALL_DIR" ]] && [[ -n "$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  die "$INSTALL_DIR exists and is not empty. Move it aside, then run the installer again."
else
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/install.sh" "$INSTALL_DIR/scripts/create-team.sh"

if [[ -z "$TEAM_SLUG" ]]; then
  read -r -p "Team slug [lastcore-agency]: " TEAM_SLUG
  TEAM_SLUG="${TEAM_SLUG:-lastcore-agency}"
fi

TEAM_ROOT="${TEAM_BASE_DIR:-$HOME/teams}/$TEAM_SLUG"
if [[ ! -f "$TEAM_ROOT/.env" ]]; then
  "$INSTALL_DIR/scripts/create-team.sh" "$TEAM_SLUG" "$OPENCLAW_HOST_PORT"
else
  log "Existing team configuration found at $TEAM_ROOT/.env; keeping it unchanged"
fi

if (( DOCKER_ACCESS_PENDING == 1 )); then
  cat <<EOF

Docker was installed and your user was added to the docker group.
Sign out and back in once, then continue with:

  $TEAM_ROOT/stack onboard
  $TEAM_ROOT/stack up
  $TEAM_ROOT/stack ready
EOF
  exit 0
fi

if [[ "$SKIP_ONBOARDING" != "1" ]]; then
  log "Starting OpenClaw onboarding for $TEAM_SLUG"
  "$TEAM_ROOT/stack" onboard
fi

log "Starting OpenClaw gateway"
"$TEAM_ROOT/stack" up

log "Waiting for gateway readiness"
READY=0
for _ in $(seq 1 30); do
  if "$TEAM_ROOT/stack" ready >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 2
done

if (( READY == 1 )); then
  printf '\nINSTALLATION COMPLETE\n'
  printf 'Team: %s\n' "$TEAM_SLUG"
  printf 'Control UI: http://127.0.0.1:%s/\n' "$OPENCLAW_HOST_PORT"
  printf 'Team control: %s/stack\n' "$TEAM_ROOT"
else
  printf '\nINSTALLATION FINISHED, BUT READINESS IS NOT VERIFIED\n' >&2
  printf 'Check logs with: %s/stack logs\n' "$TEAM_ROOT" >&2
  exit 2
fi
