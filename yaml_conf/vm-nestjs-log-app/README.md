# VM NestJS Raw Log App

This lab app runs on the VM and emits raw NestJS-style text logs for parsing practice.

It intentionally does not emit the Log Center JSON schema. The goal is to send raw app logs through Fluent Bit and let Logstash parse/normalize them later.

## Install On VM

From the GitOps repo on the VM:

```bash
cd /opt/bocao-gitops
sudo bash yaml_conf/vm-nestjs-log-app/install-vm-nestjs-log-app.sh
```

The installer creates a systemd service:

```bash
systemctl status dung-nestjs-log-app
```

## Logs

The service writes raw logs to:

```text
/var/log/dung-lab/nestjs.log
/var/log/dung-lab/nestjs.err.log
```

Example lines:

```text
[Nest] 12345  - 05/08/2026, 9:00:00 AM     LOG [HTTP] GET /orders 200 12ms
[Nest] 12345  - 05/08/2026, 9:00:05 AM    WARN [SyntheticEventsService] external api latency provider=inventory request_id=req-12345 duration_ms=1800
[Nest] 12345  - 05/08/2026, 9:00:10 AM   ERROR [HTTP] GET /payment/error 500 6ms error="Payment gateway timeout"
```

## Test Endpoints

```bash
curl http://localhost:3000/health
curl http://localhost:3000/orders
curl -X POST http://localhost:3000/orders
curl http://localhost:3000/slow-query
curl http://localhost:3000/payment/error
```

## Fluent Bit Input To Add Later

```ini
[INPUT]
    Name              tail
    Tag               vm.dunglab.nestjs
    Path              /var/log/dung-lab/nestjs.log
    Read_from_Head    On
    Refresh_Interval  5
    Rotate_Wait       30
    Mem_Buf_Limit     5MB
    Skip_Long_Lines   On
    DB                /var/lib/fluent-bit/state/nestjs.db
    DB.locking        true
    storage.type      filesystem
```
