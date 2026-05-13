# Cai dat thu cong VM NestJS Log App

Tai lieu nay mo ta cach cai dat thu cong app NestJS trong thu muc:

- `yaml_conf/vm-nestjs-log-app`

Muc tieu la lam bang tay tren VM, khong dung script `install-vm-nestjs-log-app.sh`.

---

## 1. App nay duoc cai theo kieu nao

App nay la mot NestJS app viet bang TypeScript.

Quy trinh cai dat cua no la:

1. Cai Node.js 20
2. Copy source code len VM
3. Chay `npm install`
4. Build TypeScript thanh JavaScript
5. Chay app bang `node dist/main.js`
6. Tao `systemd service` de app chay nen va tu khoi dong lai
7. Ghi log ra file trong `/var/log/dung-lab`

---

## 2. Thu muc va file can co

Tren VM, script goc dang dung cac duong dan sau:

- App code:
  - `/opt/dung-nestjs-log-app`
- Log:
  - `/var/log/dung-lab`
- Service file:
  - `/etc/systemd/system/dung-nestjs-log-app.service`

---

## 3. Cai Node.js 20 thu cong

### Kiem tra Node.js hien tai

```bash
node -v
npm -v
```

Neu Node.js da tu version 18 tro len thi co the dung tiep.  
Neu chua co, hoac version qua cu, cai Node.js 20 theo cac buoc duoi day.

### Cai Node.js 20 tu NodeSource

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -d -m 0755 /etc/apt/keyrings
sudo rm -f /etc/apt/keyrings/nodesource.gpg
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
sudo apt-get update
sudo apt-get install -y nodejs
```

### Kiem tra lai sau khi cai

```bash
node -v
npm -v
```

Ban ky vong thay `node` version 20.x.

---

## 4. Chuan bi thu muc app va thu muc log

```bash
sudo mkdir -p /opt/dung-nestjs-log-app
sudo mkdir -p /var/log/dung-lab
sudo chown -R $USER:$USER /opt/dung-nestjs-log-app
```

Luu y:

- `/opt/dung-nestjs-log-app` la noi chua source va file build
- `/var/log/dung-lab` la noi luu log file cua app

---

## 5. Copy source code len VM

Neu ban dang o trong repo GitOps tren VM, vi du:

```bash
cd /opt/bocao-gitops
```

thi copy source app vao thu muc dich:

```bash
cp -r yaml_conf/vm-nestjs-log-app/package.json /opt/dung-nestjs-log-app/
cp -r yaml_conf/vm-nestjs-log-app/tsconfig.json /opt/dung-nestjs-log-app/
cp -r yaml_conf/vm-nestjs-log-app/src /opt/dung-nestjs-log-app/
```

Neu muon chac chan lai:

```bash
ls -la /opt/dung-nestjs-log-app
ls -la /opt/dung-nestjs-log-app/src
```

Ban nen thay:

- `package.json`
- `tsconfig.json`
- thu muc `src`

---

## 6. Cai dependency va build app

Di vao thu muc app:

```bash
cd /opt/dung-nestjs-log-app
```

### Cai dependency

```bash
npm install
```

### Build TypeScript

```bash
npm run build
```

Sau khi build xong, kiem tra:

```bash
ls -la /opt/dung-nestjs-log-app/dist
```

Ban ky vong co file:

```text
dist/main.js
```

### Cat devDependencies de gon hon

Buoc nay khong bat buoc de app chay, nhung script goc co lam:

```bash
npm prune --omit=dev
```

---

## 7. Chay thu bang tay truoc khi tao service

Buoc nay rat nen lam, vi no giup biet app co build dung khong.

```bash
cd /opt/dung-nestjs-log-app
PORT=3000 NODE_ENV=production NO_COLOR=1 node dist/main.js
```

Neu app len thanh cong, ban se thay log kieu:

```text
NestJS raw log app listening on port=3000
```

Dung app bang:

```bash
Ctrl + C
```

---

## 8. Tao systemd service thu cong

Tao file:

```bash
sudo nano /etc/systemd/system/dung-nestjs-log-app.service
```

Noi dung:

```ini
[Unit]
Description=Dung NestJS raw log app
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/dung-nestjs-log-app
Environment=NODE_ENV=production
Environment=NO_COLOR=1
Environment=PORT=3000
ExecStart=/usr/bin/node /opt/dung-nestjs-log-app/dist/main.js
Restart=always
RestartSec=3
StandardOutput=append:/var/log/dung-lab/nestjs.log
StandardError=append:/var/log/dung-lab/nestjs.err.log

[Install]
WantedBy=multi-user.target
```

Luu file lai.

---

## 9. Nap lai systemd va bat service

```bash
sudo systemctl daemon-reload
sudo systemctl enable dung-nestjs-log-app.service
sudo systemctl restart dung-nestjs-log-app.service
```

Kiem tra trang thai:

```bash
systemctl status dung-nestjs-log-app
```

Neu on, ban se thay service o trang thai `active (running)`.

---

## 10. Kiem tra log file

App nay ghi log ra 2 file:

- `/var/log/dung-lab/nestjs.log`
- `/var/log/dung-lab/nestjs.err.log`

Xem log:

```bash
tail -n 50 /var/log/dung-lab/nestjs.log
tail -n 50 /var/log/dung-lab/nestjs.err.log
```

Theo doi realtime:

```bash
tail -f /var/log/dung-lab/nestjs.log
```

---

## 11. Test endpoint de tao log

Sau khi app da chay, test nhanh:

```bash
curl http://localhost:3000/health
curl http://localhost:3000/orders
curl -X POST http://localhost:3000/orders
curl http://localhost:3000/slow-query
curl http://localhost:3000/payment/error
```

Nhung lenh nay se tao ra cac loai log khac nhau:

- `health`
  - log thong thuong
- `orders`
  - log tai request thanh cong
- `slow-query`
  - log `WARN`
- `payment/error`
  - log `ERROR`

Ngoai ra app con co `SyntheticEventsService`, cu khoang 5 giay se tu sinh log nen.

---

## 12. Dang log ky vong

App nay khong ghi JSON. No ghi raw text log kieu NestJS.

Vi du:

```text
[Nest] 12345  - 05/08/2026, 9:00:00 AM     LOG [HTTP] GET /orders 200 12ms
[Nest] 12345  - 05/08/2026, 9:00:05 AM    WARN [SyntheticEventsService] external api latency provider=inventory request_id=req-12345 duration_ms=1800
[Nest] 12345  - 05/08/2026, 9:00:10 AM   ERROR [HTTP] GET /payment/error 500 6ms error="Payment gateway timeout"
```

Va con cac message tu app:

```text
health check requested
loaded orders count=7
created order order_id=ord-12345
slow query detected table=orders duration_ms=1400
payment gateway timeout request_id=req-12345 provider=mockpay
background job completed job=sync_orders request_id=req-12345
background job failed job=charge_payment request_id=req-12345 reason=timeout
```

---

## 13. Kiem tra nhanh neu app khong len

### Xem service

```bash
systemctl status dung-nestjs-log-app
```

### Xem journal systemd

```bash
journalctl -u dung-nestjs-log-app -n 100 --no-pager
```

### Xem file build co ton tai khong

```bash
ls -la /opt/dung-nestjs-log-app/dist/main.js
```

### Xem port 3000 co nghe khong

```bash
ss -ltnp | grep 3000
```

---

## 14. Neu source code thay doi thi lam gi

Moi khi thay doi code trong:

- `src/`
- `package.json`
- `tsconfig.json`

thi quy trinh cap nhat thu cong la:

```bash
cp -r /opt/bocao-gitops/yaml_conf/vm-nestjs-log-app/package.json /opt/dung-nestjs-log-app/
cp -r /opt/bocao-gitops/yaml_conf/vm-nestjs-log-app/tsconfig.json /opt/dung-nestjs-log-app/
rm -rf /opt/dung-nestjs-log-app/src
cp -r /opt/bocao-gitops/yaml_conf/vm-nestjs-log-app/src /opt/dung-nestjs-log-app/
cd /opt/dung-nestjs-log-app
npm install
npm run build
npm prune --omit=dev
sudo systemctl restart dung-nestjs-log-app
```

---

## 15. Ban rut gon cua toan bo quy trinh

Neu chi can nho nhanh, thi la:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
# cai Node.js 20

sudo mkdir -p /opt/dung-nestjs-log-app /var/log/dung-lab
cp -r yaml_conf/vm-nestjs-log-app/package.json /opt/dung-nestjs-log-app/
cp -r yaml_conf/vm-nestjs-log-app/tsconfig.json /opt/dung-nestjs-log-app/
cp -r yaml_conf/vm-nestjs-log-app/src /opt/dung-nestjs-log-app/

cd /opt/dung-nestjs-log-app
npm install
npm run build
npm prune --omit=dev

sudo nano /etc/systemd/system/dung-nestjs-log-app.service
sudo systemctl daemon-reload
sudo systemctl enable dung-nestjs-log-app.service
sudo systemctl restart dung-nestjs-log-app.service

tail -f /var/log/dung-lab/nestjs.log
```

---

## 16. Ghi chu nho

- App chay bang `node dist/main.js`, khong phai `npm run start:dev`
- Log chinh nam o:
  - `/var/log/dung-lab/nestjs.log`
- Log loi/stderr nam o:
  - `/var/log/dung-lab/nestjs.err.log`
- App dung `systemd`, nen khi reboot VM no se tu chay lai neu service da `enable`
