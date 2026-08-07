#!/usr/bin/env bash
# Bootstrap Ubuntu 22.04/24.04 EC2 as public edge for lts-api.personalwork.tw
# Run as root: sudo bash bootstrap.sh
#
# Required env before NetBird install:
#   export NETBIRD_SETUP_KEY='........'
# Optional:
#   export CADDYFILE_SRC=/path/to/Caddyfile   (default: same dir as this script)

set -euo pipefail

CADDYFILE_SRC="${CADDYFILE_SRC:-$(cd "$(dirname "$0")" && pwd)/Caddyfile}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y curl ca-certificates gnupg debian-keyring debian-archive-keyring apt-transport-https

# --- Caddy ---
if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt-get update -y
  apt-get install -y caddy
fi

install -d -m 0755 /etc/caddy
install -m 0644 "$CADDYFILE_SRC" /etc/caddy/Caddyfile
systemctl enable --now caddy
systemctl reload caddy || systemctl restart caddy

# --- NetBird ---
if ! command -v netbird >/dev/null 2>&1; then
  curl -fsSL https://pkgs.netbird.io/install.sh | bash
fi

if [[ -n "${NETBIRD_SETUP_KEY:-}" ]]; then
  netbird up --setup-key "$NETBIRD_SETUP_KEY"
else
  echo "NetBird installed. Join mesh with:"
  echo "  sudo netbird up --setup-key <YOUR_SETUP_KEY>"
fi

echo
echo "After DNS A record lts-api.personalwork.tw → this EIP, check:"
echo "  curl -fsS https://lts-api.personalwork.tw/healthz"
echo "  curl -fsS -o /dev/null -w '%{http_code}\\n' https://lts-api.personalwork.tw/docs"
echo
echo "Mesh probe from this host:"
echo "  curl -fsS http://tazs-m1pro.netbird.cloud:8000/healthz"
