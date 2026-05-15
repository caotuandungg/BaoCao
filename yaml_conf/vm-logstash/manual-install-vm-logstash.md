

## 1. Cai Logstash

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
```

```bash
sudo install -d -m 0755 /usr/share/keyrings
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
  | sudo gpg --dearmor -o /usr/share/keyrings/elastic-archive-keyring.gpg
```

Tao file repo APT cua Elastic:

```bash
sudo nano /etc/apt/sources.list.d/elastic-8.x.list
```

Dan noi dung sau vao file:

```text
deb [signed-by=/usr/share/keyrings/elastic-archive-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main
```

Luu file trong nano:

```text
Ctrl + O
Enter
Ctrl + X
```

```bash
sudo apt-get update
sudo apt-get install -y logstash
```

## 2. Copy file pipeline Logstash

Di chuyen vao thu muc GitOps tren VM:

```bash
cd /opt/bocao-gitops
```

Copy file cau hinh pipeline:

```bash
sudo install -d -m 0755 /etc/logstash/conf.d
sudo install -m 0644 yaml_conf/vm-logstash/vm-logstash.conf /etc/logstash/conf.d/dung-vm-logstash.conf
```

## 3. Tao file bien moi truong

```bash
sudo nano /etc/default/dung-vm-logstash
```


```text
# Runtime settings for dung VM Logstash.
VM_LOGSTASH_ES_HOST=https://elasticsearch-dung.vnpost.cloud:443
VM_LOGSTASH_ES_USER=elastic
VM_LOGSTASH_ES_PASSWORD=1xNIfTEXaH0MsbQN
LS_JAVA_OPTS=-Xms512m -Xmx512m
```

Luu file trong nano:

```text

## 4. Cho systemd doc file bien moi truong

```bash
sudo install -d -m 0755 /etc/systemd/system/logstash.service.d
```

```bash
sudo nano /etc/systemd/system/logstash.service.d/10-dung-vm-logstash.conf
```


```text
[Service]
EnvironmentFile=-/etc/default/dung-vm-logstash
```

Luu file trong nano:

```text
Ctrl + O
Enter
Ctrl + X
```

```bash
sudo systemctl daemon-reload
```

## 5. Cap quyen cho user logstash

```bash
sudo install -d -m 0750 -o logstash -g logstash /var/lib/logstash
sudo install -d -m 0750 -o logstash -g logstash /var/lib/logstash/queue
sudo install -d -m 0750 -o logstash -g logstash /var/lib/logstash/dead_letter_queue
sudo install -d -m 0750 -o logstash -g logstash /var/lib/logstash/plugins
sudo install -d -m 0750 -o logstash -g logstash /var/log/logstash
sudo chown logstash:logstash /etc/logstash/conf.d/dung-vm-logstash.conf
```

## 6. Kiem tra cau hinh truoc khi chay

```bash
sudo runuser -u logstash -- /usr/share/logstash/bin/logstash --path.settings /etc/logstash --config.test_and_exit
```

Neu thay `Configuration OK` la file cau hinh hop le.

## 7. Bat va restart Logstash

```bash
sudo systemctl enable logstash
sudo systemctl restart logstash
```

## 8. Kiem tra trang thai

```bash
sudo systemctl status logstash
```

Xem log runtime:

```bash
sudo journalctl -u logstash -f
```

Xem file pipeline dang duoc apply:

```bash
sudo cat /etc/logstash/conf.d/dung-vm-logstash.conf
```

## 9. Khi sua pipeline va muon apply lai

Sau khi sua file trong Git repo tren VM:

```bash
cd /opt/bocao-gitops
sudo install -m 0644 yaml_conf/vm-logstash/vm-logstash.conf /etc/logstash/conf.d/dung-vm-logstash.conf
sudo runuser -u logstash -- /usr/share/logstash/bin/logstash --path.settings /etc/logstash --config.test_and_exit
sudo systemctl restart logstash
```
