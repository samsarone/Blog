#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

REMOTE_HOST="${REMOTE_HOST:-api.samsar.one}"
REMOTE_USER="${REMOTE_USER:-azureuser}"
REMOTE_REPO_DIR="${REMOTE_REPO_DIR:-/home/azureuser/Blog}"
LIVE_GHOST_DIR="${LIVE_GHOST_DIR:-/var/www/ghost}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/Users/pritamroy/Documents/others/aws/azure/roy_dev_key.pem}"
BRANCH="${BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
REMOTE_NAME="${REMOTE_NAME:-origin}"

if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "SSH key not found at $SSH_KEY_PATH" >&2
    exit 1
fi

echo "Pushing ${BRANCH} to ${REMOTE_NAME}..."
git push "$REMOTE_NAME" "$BRANCH"
echo "Local commit: $(git rev-parse --short HEAD)"

echo "Deploying on ${REMOTE_USER}@${REMOTE_HOST}..."
ssh -i "$SSH_KEY_PATH" "${REMOTE_USER}@${REMOTE_HOST}" \
    "REMOTE_REPO_DIR='$REMOTE_REPO_DIR' LIVE_GHOST_DIR='$LIVE_GHOST_DIR' BRANCH='$BRANCH' REMOTE_NAME='$REMOTE_NAME' bash -s" <<'EOF'
set -euo pipefail

cd "$REMOTE_REPO_DIR"

echo "Pulling latest code..."
git fetch "$REMOTE_NAME"
git checkout "$BRANCH"
git reset --hard "$REMOTE_NAME/$BRANCH"
git clean -fd
echo "Remote commit: $(git rev-parse --short HEAD)"

echo "Ensuring pnpm workspace file exists..."
cat > pnpm-workspace.yaml <<'WORKSPACE'
packages:
  - 'ghost/core'
  - 'ghost/i18n'
  - 'ghost/parse-email-address'
WORKSPACE

echo "Syncing samsar theme into live Ghost content directory..."
sudo mkdir -p "$LIVE_GHOST_DIR/content/themes/samsar"
sudo rsync -a --delete "$REMOTE_REPO_DIR/ghost/core/content/themes/samsar/" "$LIVE_GHOST_DIR/content/themes/samsar/"
sudo chown -R ghost:ghost "$LIVE_GHOST_DIR/content/themes/samsar"

echo "Listing deployed theme files..."
sudo find "$LIVE_GHOST_DIR/content/themes/samsar" -maxdepth 2 -type f | sort | sed -n '1,80p'

echo "Setting live Ghost URL to /blog..."
sudo LIVE_GHOST_DIR="$LIVE_GHOST_DIR" python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["LIVE_GHOST_DIR"]) / "config.production.json"
with path.open() as f:
    data = json.load(f)

data["url"] = "https://www.samsar.one/blog/"

with path.open("w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

echo "Activating samsar theme in Ghost database..."
mysql -u ghost_user -pstrong_password -D ghost_prod -e "update settings set value='samsar' where \`key\`='active_theme';"

echo "Clearing stale migration lock if present..."
mysql -u ghost_user -pstrong_password -D ghost_prod -e "update migrations_lock set locked=0, acquired_at=NULL where lock_key='km01';" || true

echo "Restarting live Ghost service..."
sudo systemctl restart ghost_localhost.service
sleep 8
sudo systemctl --no-pager --full status ghost_localhost.service | sed -n '1,40p'

echo "Smoke testing public blog URL..."
curl -I https://www.samsar.one/blog/
EOF

echo "Deploy complete."
