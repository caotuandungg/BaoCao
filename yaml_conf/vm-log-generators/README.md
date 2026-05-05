# VM Log Generators

This directory is the Git source of truth for the 4 fake Python log generators.

The VM runtime layout is:

```text
/opt/dung-log-generators/fe.py
/opt/dung-log-generators/be.py
/opt/dung-log-generators/db.py
/opt/dung-log-generators/web.py

/var/log/dung-lab/fe.log
/var/log/dung-lab/be.log
/var/log/dung-lab/db.log
/var/log/dung-lab/web.log
```

Deploy or redeploy from the Vagrant shared folder:

```bash
cd /vagrant/yaml_conf/vm-log-generators
sudo bash install-vm-log-generators.sh
```

Check services:

```bash
systemctl status dung-fe-log-generator
systemctl status dung-be-log-generator
systemctl status dung-db-log-generator
systemctl status dung-web-log-generator
```

Watch generated logs:

```bash
tail -f /var/log/dung-lab/fe.log
tail -f /var/log/dung-lab/be.log
tail -f /var/log/dung-lab/db.log
tail -f /var/log/dung-lab/web.log
```

GitOps-style workflow for this lab:

```text
Edit files in Git repo on host
git commit
vagrant ssh
cd /vagrant/yaml_conf/vm-log-generators
sudo bash install-vm-log-generators.sh
```

If you add this script to `Vagrantfile` provisioning, the VM can also reconcile
itself on `vagrant provision`.
