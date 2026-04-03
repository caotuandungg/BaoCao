# Hướng Dẫn Tích Hợp Fluent Bit Vào ELK Stack Có Sẵn

> **Người thực hiện:** Dũng  
> **Khảo sát:** Cụm K8s đã có sẵn Elasticsearch và Kibana trong namespace `elk`.  
> **Phương án chọn:** Chỉ cài đặt thêm Fluent Bit (Agent) để gom log đẩy về Elasticsearch.

---

## Tổng quan kiến trúc hiện tại

```
  Các Pods (trên 6 Nodes)
       │
       ▼ (Ghi log ra /var/log/pods/)
       │
  ┌─────────────┐
  │ Fluent Bit  │ (Sẽ cài thêm bằng Helm làm DaemonSet)
  │ (Log Agent) │
  └──────┬──────┘
         │
         ▼ (Gửi log qua HTTP Post: cổng 9200)
         │
  ┌─────────────┐
  │Elasticsearch│ (Đã có sẵn trong namespace `elk`)
  └──────┬──────┘
         │
         ▼ (Kết nối)
         │
  ┌─────────────┐
  │   Kibana    │ (Đã có sẵn, giao diện tìm kiếm log: cổng 5601)
  └─────────────┘
```

---

## Chuẩn bị cấu hình

### 1. Thêm Helm Repository của Fluent
```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update
```

### 2. Tạo file cấu hình `fluent-bit-values.yaml`

Tạo file `fluent-bit-values.yaml` với nội dung tối ưu sau để đọc log của K8s và gửi về Elasticsearch:

```yaml
# Cấu hình Fluent Bit kết nối với ELK hiện có

# Cấu hình cài đặt chạy dưới dạng DaemonSet trên mọi Node
kind: DaemonSet

# Cấu hình lõi của Fluent Bit
config:
  # Thiết lập chung
  service: |
    [SERVICE]
        Flush         1
        Log_Level     info
        Daemon        off
        Parsers_File  parsers.conf
        HTTP_Server   On
        HTTP_Listen   0.0.0.0
        HTTP_Port     2020

  # Đọc log từ tất cả các Container K8s
  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        Parser            docker
        Tag               kube.*
        Refresh_Interval  5
        Mem_Buf_Limit     50MB
        Skip_Long_Lines   On

  # Lọc và gắn thêm thông tin K8s (Namespace, Labels, Pod_Name)
  filters: |
    [FILTER]
        Name                kubernetes
        Match               kube.*
        Kube_URL            https://kubernetes.default.svc:443
        Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
        Kube_Tag_Prefix     kube.var.log.containers.
        Merge_Log           On
        Merge_Log_Key       log_processed
        K8S-Logging.Parser  On
        K8S-Logging.Exclude Off

  # Đẩy log về Elasticsearch Service (đang chạy cổng 9200 ở namespace elk)
  outputs: |
    [OUTPUT]
        Name            es
        Match           *
        Host            elasticsearch-master.elk.svc.cluster.local
        Port            9200
        Logstash_Format On
        Logstash_Prefix fluent-bit
        Retry_Limit     False
        TLS             Off

# Cấp quyền RBAC để Fluent Bit có thể đọc thông tin Pod/Namespace
rbac:
  create: true
  nodeAccess: true
```

---

## Các bước triển khai

### Bước 1: Cài đặt Fluent Bit vào cụm K8s
*Lưu ý: Mình sẽ cài Fluent Bit vào luôn namespace `elk` cùng với Elasticsearch để dễ quản lý.*

```bash
helm install fluent-bit fluent/fluent-bit \
  --namespace elk \
  -f fluent-bit-values.yaml
```

### Bước 2: Kiểm tra Fluent Bit đang hoạt động
Bởi vì cụm có 6 node (3 Control Plane + 3 Worker), Fluent Bit DaemonSet phải tạo ra 6 Pod.
```bash
# Kiểm tra Pod Fluent Bit
kubectl get pods -n elk -l app.kubernetes.io/name=fluent-bit

# Kiểm tra log bên trong 1 pod để chắc chắn không có lỗi đẩy về ES
# (Nhấn Ctrl+C để thoát)
kubectl logs -n elk -l app.kubernetes.io/name=fluent-bit --tail=50
```

---

## Tìm kiếm Log trên Kibana

### Bước 3: Port-forward giao diện Kibana
Mở truy cập Kibana bằng lệnh sau. Đừng tắt terminal này:
```bash
kubectl port-forward svc/kibana-kibana 5601:5601 -n elk
```

### Bước 4: Thiết lập Data View trên trình duyệt
1. Mở trình duyệt: `http://localhost:5601`
2. Truy cập menu bên trái -> **Management** -> **Stack Management** (kéo hẳn xuống dưới cùng).
3. Bấm vào **Data Views** (Nếu bản cũ sẽ là *Index Patterns*).
4. Nhấn nút xanh **Create data view**.
5. Trong ô *Name* hoặc *Index pattern*, gõ `fluent-bit-*` (bởi vì trong file values mình đã thiết lập `Logstash_Prefix fluent-bit`).
6. Ở ô *Timestamp field*, chọn `@timestamp`.
7. Nhấn **Save data view**.

### Bước 5: Tìm kiếm thực tế
1. Truy cập menu bên trái -> **Analytics** -> **Discover**.
2. Góc trên bên trái, chọn Data View là `fluent-bit-*`.
3. Khám phá các log đã bắt đầu đổ về! Bạn có thể lọc bằng thanh Search (Ví dụ gõ `kubernetes.labels.app: "argocd"`).

---

## ⚠️ Khắc phục sự cố nhanh (Troubleshooting)

Nếu lên Kibana không thấy log, hãy kiểm tra kết nối từ Pod Fluent Bit sang Elasticsearch:
```bash
# Gõ lệnh sau để gọi API kiểm tra ES từ nội bộ
kubectl exec -it -n elk $(kubectl get pod -n elk -l app.kubernetes.io/name=fluent-bit -o jsonpath='{.items[0].metadata.name}') -- curl -s http://elasticsearch-master.elk.svc.cluster.local:9200
```
*(Nếu nó trả về JSON "You Know, for Search" thì tức là kết nối bình thường, lỗi nằm ở Kibana chưa cài đúng Data View).*
