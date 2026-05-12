#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${REPO_DIR:-/opt/bocao-gitops}"
LOG_GENERATORS_DIR="${REPO_DIR}/yaml_conf/vm-log-generators"
NESTJS_LOG_APP_DIR="${REPO_DIR}/yaml_conf/vm-nestjs-log-app"
FLUENT_BIT_DIR="${REPO_DIR}/yaml_conf/fluent-bit"
LOGSTASH_DIR="${REPO_DIR}/yaml_conf/vm-logstash"

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


bash "${LOG_GENERATORS_DIR}/install-vm-log-generators.sh"

if [ -f "${NESTJS_LOG_APP_DIR}/install-vm-nestjs-log-app.sh" ]; then
  bash "${NESTJS_LOG_APP_DIR}/install-vm-nestjs-log-app.sh"
fi

if [ -f "${LOGSTASH_DIR}/install-vm-logstash.sh" ]; then
  bash "${LOGSTASH_DIR}/install-vm-logstash.sh"
fi


echo "VM logging stack reconciled from Git."
echo "Repo: ${REPO_DIR}"
echo "Check:"
echo "  systemctl status dung-fe-log-generator dung-be-log-generator dung-db-log-generator dung-web-log-generator dung-nestjs-log-app logstash"
