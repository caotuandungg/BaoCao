#!/usr/bin/env bash
set -euo pipefail

# Resolve path cua thu muc script trong Git repo va cac duong dan runtime
# se duoc cai tren VM.
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_SRC="${SOURCE_DIR}/vm-logstash.conf"
PIPELINE_DST="/etc/logstash/conf.d/dung-vm-logstash.conf"
ENV_FILE="/etc/default/dung-vm-logstash"
SERVICE_OVERRIDE_DIR="/etc/systemd/system/logstash.service.d"
SERVICE_OVERRIDE_FILE="${SERVICE_OVERRIDE_DIR}/10-dung-vm-logstash.conf"

# Dung som neu repo thieu file pipeline, tranh cai service rong/sai.
if [ ! -f "$PIPELINE_SRC" ]; then
  echo "Missing ${PIPELINE_SRC}"
  exit 1
fi

install_logstash_package() {
  # Neu Logstash da co san tren VM thi bo qua buoc cai package.
  if command -v logstash >/dev/null 2>&1 || [ -x /usr/share/logstash/bin/logstash ]; then
    echo "Logstash is already installed."
    return
  fi

  # Cai cac dependency can thiet de them APT repo cua Elastic.
  echo "Installing Logstash from Elastic APT repository..."
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl gnupg

  # Import GPG key cua Elastic de apt co the verify package.
  install -d -m 0755 /usr/share/keyrings
  if [ ! -f /usr/share/keyrings/elastic-archive-keyring.gpg ]; then
    curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
      | gpg --dearmor -o /usr/share/keyrings/elastic-archive-keyring.gpg
  fi

  # Khai bao Elastic 8.x APT repository.
  cat > /etc/apt/sources.list.d/elastic-8.x.list <<'REPO'
deb [signed-by=/usr/share/keyrings/elastic-archive-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main
REPO

  # Cai Logstash tu repo Elastic.
  apt-get update
  apt-get install -y logstash
}

install_logstash_package

# Copy pipeline cua Git repo vao thu muc cau hinh Logstash tren VM.
install -d -m 0755 /etc/logstash/conf.d
install -m 0644 "$PIPELINE_SRC" "$PIPELINE_DST"

# Tao file bien moi truong lan dau. Cac lan reconcile sau khong ghi de file nay
# de admin VM co the sua endpoint Elasticsearch/password tai cho neu can.
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<'ENV'
# Runtime settings for dung VM Logstash.
# Set VM_LOGSTASH_ES_HOST to an Elasticsearch endpoint reachable from this VM.
VM_LOGSTASH_ES_HOST=https://elasticsearch-dung.vnpost.cloud
VM_LOGSTASH_ES_USER=elastic
VM_LOGSTASH_ES_PASSWORD=1xNIfTEXaH0MsbQN
LS_JAVA_OPTS=-Xms512m -Xmx512m
ENV
elif grep -q '^VM_LOGSTASH_ES_HOST=https://elasticsearch-master\.elk-dung\.svc\.cluster\.local:9200$' "$ENV_FILE"; then
  # Auto-migrate old default K8s-internal endpoint to the external Ingress
  # endpoint. Other custom values are preserved.
  sed -i 's#^VM_LOGSTASH_ES_HOST=.*#VM_LOGSTASH_ES_HOST=https://elasticsearch-dung.vnpost.cloud#' "$ENV_FILE"
fi

# Them systemd drop-in de service logstash nap file bien moi truong o tren.
install -d -m 0755 "$SERVICE_OVERRIDE_DIR"
cat > "$SERVICE_OVERRIDE_FILE" <<EOF
[Service]
EnvironmentFile=-${ENV_FILE}
EOF

# Reload systemd de nhan drop-in moi.
systemctl daemon-reload

# Neu package tao user logstash, gan owner cho cac file/thu muc ma service
# can doc/ghi. Loi thuong gap neu thieu buoc nay:
#   Path "/var/lib/logstash/queue" must be a writable directory.
#   Path "/var/lib/logstash/dead_letter_queue" must be a writable directory.
if id logstash >/dev/null 2>&1; then
  install -d -m 0750 -o logstash -g logstash /var/lib/logstash
  install -d -m 0750 -o logstash -g logstash /var/lib/logstash/queue
  install -d -m 0750 -o logstash -g logstash /var/lib/logstash/dead_letter_queue
  install -d -m 0750 -o logstash -g logstash /var/lib/logstash/plugins
  install -d -m 0750 -o logstash -g logstash /var/log/logstash
  chown logstash:logstash "$PIPELINE_DST"
else
  install -d -m 0755 /var/lib/logstash
  install -d -m 0755 /var/lib/logstash/queue
  install -d -m 0755 /var/lib/logstash/dead_letter_queue
  install -d -m 0755 /var/lib/logstash/plugins
  install -d -m 0755 /var/log/logstash
fi

# Validate pipeline truoc khi restart service. Chay bang user logstash neu co
# de bat dung cac loi permission giong luc systemd start.
if id logstash >/dev/null 2>&1; then
  runuser -u logstash -- /usr/share/logstash/bin/logstash --path.settings /etc/logstash --config.test_and_exit
else
  /usr/share/logstash/bin/logstash --path.settings /etc/logstash --config.test_and_exit
fi

# Bat service khoi dong cung VM va restart de apply pipeline moi.
systemctl enable logstash
systemctl restart logstash

echo "Installed dung VM Logstash pipeline."
echo "Pipeline: ${PIPELINE_DST}"
echo "Environment: ${ENV_FILE}"
echo "Check:"
echo "  systemctl status logstash"
echo "  journalctl -u logstash -f"
