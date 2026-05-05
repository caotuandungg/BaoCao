#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/caotuandungg/BaoCao.git}"
REPO_DIR="${REPO_DIR:-/opt/bocao-gitops}"
BRANCH="${BRANCH:-main}"
INTERVAL="${INTERVAL:-60}"

apt-get update
apt-get install -y git python3

if [ ! -d "$REPO_DIR/.git" ]; then
  git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
else
  git -C "$REPO_DIR" fetch origin "$BRANCH"
  git -C "$REPO_DIR" checkout "$BRANCH"
  git -C "$REPO_DIR" pull --ff-only
fi

cat > /etc/systemd/system/bocao-vm-gitops.service <<SERVICE
[Unit]
Description=BaoCao VM logging GitOps reconcile
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
Environment=REPO_DIR=${REPO_DIR}
ExecStart=/usr/bin/bash ${REPO_DIR}/yaml_conf/vm-gitops/reconcile-vm-logging.sh
SERVICE

cat > /etc/systemd/system/bocao-vm-gitops.timer <<TIMER
[Unit]
Description=Run BaoCao VM logging GitOps reconcile every ${INTERVAL}s

[Timer]
OnBootSec=30
OnUnitActiveSec=${INTERVAL}
AccuracySec=10
Unit=bocao-vm-gitops.service

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable --now bocao-vm-gitops.timer
systemctl start bocao-vm-gitops.service || true

echo "Installed GitOps puller."
echo "Repo: ${REPO_DIR}"
echo "Timer: bocao-vm-gitops.timer"
echo "Logs:"
echo "  journalctl -u bocao-vm-gitops.service -f"
