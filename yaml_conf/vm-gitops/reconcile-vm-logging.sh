#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/opt/bocao-gitops}"
LOG_GENERATORS_DIR="${REPO_DIR}/yaml_conf/vm-log-generators"
FLUENT_BIT_DIR="${REPO_DIR}/yaml_conf/fluent-bit"
FLUENT_BIT_CONF="/etc/fluent-bit/fluent-bit.conf"
FLUENT_BIT_PARSERS="/etc/fluent-bit/vm-parsers.conf"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "Repository is missing at ${REPO_DIR}."
  echo "Clone it first, for example:"
  echo "  sudo git clone https://github.com/caotuandungg/BaoCao.git ${REPO_DIR}"
  exit 1
fi

cd "$REPO_DIR"
git pull --ff-only

if [ ! -f "${LOG_GENERATORS_DIR}/install-vm-log-generators.sh" ]; then
  echo "Missing ${LOG_GENERATORS_DIR}/install-vm-log-generators.sh"
  exit 1
fi

if [ ! -f "${FLUENT_BIT_DIR}/vm-fluent-bit.conf" ]; then
  echo "Missing ${FLUENT_BIT_DIR}/vm-fluent-bit.conf"
  exit 1
fi

bash "${LOG_GENERATORS_DIR}/install-vm-log-generators.sh"

install -d -m 0755 /etc/fluent-bit
install -d -m 0755 /var/lib/fluent-bit/state
install -m 0644 "${FLUENT_BIT_DIR}/vm-fluent-bit.conf" "$FLUENT_BIT_CONF"
install -m 0644 "${FLUENT_BIT_DIR}/vm-parsers.conf" "$FLUENT_BIT_PARSERS"

systemctl enable fluent-bit
systemctl restart fluent-bit

echo "VM logging stack reconciled from Git."
echo "Repo: ${REPO_DIR}"
echo "Check:"
echo "  systemctl status dung-fe-log-generator dung-be-log-generator dung-db-log-generator dung-web-log-generator"
echo "  systemctl status fluent-bit"
echo "  journalctl -u fluent-bit -f"
