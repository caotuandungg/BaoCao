# Hướng Dẫn Cài Đặt Log Agent Trên Máy Chủ Ngoài K8s (VM)

Tài liệu này hướng dẫn cách cài đặt Fluent Bit lên một máy chủ Linux (Ubuntu/CentOS) nằm ngoài cụm Kubernetes để thu thập log và gửi về trung tâm Elasticsearch.

---

## 1. Cài Đặt (Trên Ubuntu/Debian)

Chạy các lệnh sau trên Server đích:

```bash
# Thêm khóa GPG của Fluent Bit
curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh
```

Hoặc cài thủ công:
```bash
wget -qO - https://packages.fluentbit.io/fluentbit.key | sudo apt-key add -
echo "deb https://packages.fluentbit.io/ubuntu/focal focal main" | sudo tee /etc/apt/sources.list.d/fluentbit.list
sudo apt-get update
sudo apt-get install td-agent-bit
sudo service td-agent-bit start
```

---

## 2. Cấu Hình Gửi Log Về K8s (td-agent-bit.conf)

Sửa file cấu hình tại `/etc/td-agent-bit/td-agent-bit.conf`:

```ini
[SERVICE]
    Flush        1
    Log_Level    info
    Daemon       off
    Parsers_File parsers.conf

[INPUT]
    Name         tail
    Path         /var/log/syslog
    Tag          vm.syslog

[INPUT]
    Name         tail
    Path         /var/log/nginx/access.log
    Tag          vm.nginx

[OUTPUT]
    Name            es
    Match           vm.*
    Host            <IP_CUA_K8S_NODE>
    Port            <NODEPORT_CUA_ELASTIC>
    HTTP_User       elastic
    HTTP_Passwd     1qK@B5mQ
    Logstash_Format On
    Logstash_Prefix vm-logs
    TLS             On
    TLS.Verify      Off
```

**Lưu ý:**
*   `<IP_CUA_K8S_NODE>`: Là địa chỉ IP của một trong các máy chủ trong cụm Kubernetes.
*   `<NODEPORT_CUA_ELASTIC>`: Bạn cần tạo một Service loại `NodePort` cho Elasticsearch để máy bên ngoài có thể nhìn thấy.

---

## 3. Cách Mở Cổng Cho Elasticsearch (Trên K8s)

Nếu Elasticsearch chưa có cổng ra ngoài, hãy chạy lệnh sau để tạo một Service loại NodePort:

```bash
kubectl expose service elasticsearch-master --type=NodePort --name=elasticsearch-external -n elk
```

Sau đó kiểm tra cổng được cấp:
```bash
kubectl get svc elasticsearch-external -n elk
```
(Dùng cổng trong khoảng 30000-32767 hiện ra ở cột PORT).
