#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/dung-log-generators"
LOG_DIR="/var/log/dung-lab"
SERVICE_DIR="/etc/systemd/system"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -d -m 0755 "$APP_DIR"
install -d -m 0755 "$LOG_DIR"

install -m 0644 "$SOURCE_DIR/fe.py" "$APP_DIR/fe.py"
install -m 0644 "$SOURCE_DIR/be.py" "$APP_DIR/be.py"
install -m 0644 "$SOURCE_DIR/db.py" "$APP_DIR/db.py"
install -m 0644 "$SOURCE_DIR/web.py" "$APP_DIR/web.py"

for app in fe be db web; do
  cat > "$SERVICE_DIR/dung-${app}-log-generator.service" <<SERVICE
[Unit]
Description=Dung ${app} fake log generator
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${APP_DIR}/${app}.py
Restart=always
RestartSec=3
StandardOutput=append:${LOG_DIR}/${app}.log
StandardError=append:${LOG_DIR}/${app}.err.log

[Install]
WantedBy=multi-user.target
SERVICE
done

systemctl daemon-reload

for app in fe be db web; do
  systemctl enable "dung-${app}-log-generator.service"
  systemctl restart "dung-${app}-log-generator.service"
done

echo "Deployed dung log generators."
echo "Logs:"
echo "  ${LOG_DIR}/fe.log"
echo "  ${LOG_DIR}/be.log"
echo "  ${LOG_DIR}/db.log"
echo "  ${LOG_DIR}/web.log"
