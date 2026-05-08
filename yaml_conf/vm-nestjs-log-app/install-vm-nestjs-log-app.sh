#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/dung-nestjs-log-app"
LOG_DIR="/var/log/dung-lab"
SERVICE_FILE="/etc/systemd/system/dung-nestjs-log-app.service"
FINGERPRINT_FILE="${APP_DIR}/.source.sha256"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

node_major_version() {
  if ! command -v node >/dev/null 2>&1; then
    echo 0
    return
  fi

  node -v | sed -E 's/^v([0-9]+).*/\1/'
}

install_nodejs() {
  local major
  major="$(node_major_version)"

  if [ "$major" -ge 18 ]; then
    echo "Node.js $(node -v) is already installed."
    return
  fi

  echo "Installing Node.js 20 for NestJS app..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -d -m 0755 /etc/apt/keyrings
  rm -f /etc/apt/keyrings/nodesource.gpg
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update
  apt-get install -y nodejs
}

source_fingerprint() {
  (
    cd "$SOURCE_DIR"
    sha256sum package.json tsconfig.json
    find src -type f -name '*.ts' -print0 | sort -z | xargs -0 sha256sum
  ) | sha256sum | awk '{print $1}'
}

install_nodejs

install -d -m 0755 "$APP_DIR"
install -d -m 0755 "$LOG_DIR"

CURRENT_FINGERPRINT="$(source_fingerprint)"
PREVIOUS_FINGERPRINT=""
if [ -f "$FINGERPRINT_FILE" ]; then
  PREVIOUS_FINGERPRINT="$(cat "$FINGERPRINT_FILE")"
fi

APP_CHANGED="false"
if [ "$CURRENT_FINGERPRINT" != "$PREVIOUS_FINGERPRINT" ] || [ ! -f "${APP_DIR}/dist/main.js" ]; then
  APP_CHANGED="true"
  rm -rf "${APP_DIR:?}/src" "${APP_DIR}/dist"
  install -m 0644 "$SOURCE_DIR/package.json" "$APP_DIR/package.json"
  install -m 0644 "$SOURCE_DIR/tsconfig.json" "$APP_DIR/tsconfig.json"
  cp -a "$SOURCE_DIR/src" "$APP_DIR/src"

  cd "$APP_DIR"
  npm install
  npm run build
  npm prune --omit=dev
  echo "$CURRENT_FINGERPRINT" > "$FINGERPRINT_FILE"
else
  echo "NestJS source is unchanged. Skipping npm install/build."
fi

cat > "$SERVICE_FILE" <<SERVICE
[Unit]
Description=Dung NestJS raw log app
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
Environment=NODE_ENV=production
Environment=NO_COLOR=1
Environment=PORT=3000
ExecStart=/usr/bin/node ${APP_DIR}/dist/main.js
Restart=always
RestartSec=3
StandardOutput=append:${LOG_DIR}/nestjs.log
StandardError=append:${LOG_DIR}/nestjs.err.log

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable dung-nestjs-log-app.service

if [ "$APP_CHANGED" = "true" ] || ! systemctl is-active --quiet dung-nestjs-log-app.service; then
  systemctl restart dung-nestjs-log-app.service
else
  echo "dung-nestjs-log-app.service is already running."
fi

echo "Deployed Dung NestJS raw log app."
echo "Service:"
echo "  systemctl status dung-nestjs-log-app"
echo "Logs:"
echo "  ${LOG_DIR}/nestjs.log"
echo "  ${LOG_DIR}/nestjs.err.log"
echo "Test endpoints:"
echo "  curl http://localhost:3000/health"
echo "  curl http://localhost:3000/orders"
echo "  curl http://localhost:3000/slow-query"
echo "  curl http://localhost:3000/payment/error"
