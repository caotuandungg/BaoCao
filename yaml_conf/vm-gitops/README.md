# VM GitOps

This folder makes the VM reconcile its local logging stack from Git:

```text
GitHub repo
  -> VM clone at /opt/bocao-gitops
  -> 4 Python log generators as systemd services
  -> Fluent Bit config under /etc/fluent-bit
  -> Fluent Bit tails /var/log/dung-lab/*.log
  -> Fluent Bit prints parsed logs to stdout for local validation
```

One-time install on the VM:

```bash
sudo apt-get update
sudo apt-get install -y git
sudo git clone https://github.com/caotuandungg/BaoCao.git /opt/bocao-gitops
cd /opt/bocao-gitops
sudo bash yaml_conf/vm-gitops/install-gitops-puller.sh
```

Manual reconcile:

```bash
sudo systemctl start bocao-vm-gitops.service
```

Watch reconcile logs:

```bash
journalctl -u bocao-vm-gitops.service -f
```

Check the timer:

```bash
systemctl status bocao-vm-gitops.timer
systemctl list-timers bocao-vm-gitops.timer
```

Check generated app logs:

```bash
tail -f /var/log/dung-lab/fe.log
tail -f /var/log/dung-lab/be.log
tail -f /var/log/dung-lab/db.log
tail -f /var/log/dung-lab/web.log
```

Check Fluent Bit:

```bash
systemctl status fluent-bit
journalctl -u fluent-bit -f
```
