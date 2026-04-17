# Mở rộng hệ thống logging: kết hợp Loki + Grafana

## 1. Mục tiêu

Bổ sung thêm nhánh quan sát nhanh bằng Loki + Grafana, chạy riêng trên `wk03`, đồng thời vẫn giữ nhánh hiện tại:

- `Fluent Bit -> Kafka -> Logstash -> Elasticsearch`

Mô hình sau khi mở rộng:

- Nhánh 1 (đang dùng): `Fluent Bit -> Kafka -> Logstash -> Elasticsearch`
- Nhánh 2 (mới): `Fluent Bit -> Loki -> Grafana`

Ý nghĩa:

- Loki: xem log realtime/fast view, tail nhanh để debug.
- Elasticsearch: phân tích sâu, search phức tạp, ILM, alert.

---

## 2. Phạm vi triển khai trong cụm hiện tại

- Namespace: `elk-dung`
- Node chạy: `wk03`
- Tên tách biệt với tài nguyên người khác:
  - Loki: `loki-dung`
  - Grafana: `grafana-dung`

File manifest đã chuẩn bị:

- `yaml_conf/loki-dung.yaml`
- `yaml_conf/grafana-dung.yaml`

---

## 3. Deploy Loki và Grafana

```powershell
kubectl apply -f yaml_conf/loki-dung.yaml
kubectl apply -f yaml_conf/grafana-dung.yaml
```

Kiểm tra pod:

```powershell
kubectl get pods -n elk-dung -o wide | findstr /I "loki-dung grafana-dung"
```

Kiểm tra service:

```powershell
kubectl get svc -n elk-dung | findstr /I "loki-dung grafana-dung"
```

---

## 4. Truy cập Grafana

Port-forward:

```powershell
kubectl port-forward -n elk-dung svc/grafana-dung 3001:3000
```

Mở trình duyệt:

- `http://localhost:3001`

Thông tin đăng nhập mặc định (theo manifest hiện tại):

- user: `admin`
- password: `admin123!ChangeMe`

Khuyến nghị:

- đổi password ngay lần đăng nhập đầu tiên.

---

## 5. Datasource đã cấu hình sẵn trong Grafana

Manifest `grafana-dung.yaml` đã provision 2 datasource:

1. `Loki-Dung`
2. `Elasticsearch-Dung`

Kiểm tra trong Grafana:

- `Connections` -> `Data sources`
- đảm bảo cả 2 datasource đều có trạng thái kết nối thành công.

---

## 6. Kết nối Fluent Bit vào Loki (dual-output)

Để có fast view thực tế, Fluent Bit cần gửi log sang Loki ngoài đường Kafka hiện tại.

Nguyên tắc:

- Giữ nguyên output Kafka (để không ảnh hưởng pipeline ES).
- Thêm output Loki song song.

Ví dụ block output Loki trong Fluent Bit:

```ini
[OUTPUT]
    Name          loki
    Match         kube.*
    Host          loki-dung.elk-dung.svc.cluster.local
    Port          3100
    Labels        job=fluent-bit,namespace=$kubernetes['namespace_name'],pod=$kubernetes['pod_name'],container=$kubernetes['container_name'],service=$service,level=$level
    Line_Format   json
```

Sau khi chỉnh `fluent-bit-values.yaml`, upgrade lại:

```powershell
helm upgrade --install fluent-bit fluent/fluent-bit -n elk-dung -f yaml_conf/fluent-bit-values.yaml
kubectl rollout status daemonset/fluent-bit -n elk-dung
```

---

## 7. Cách kiểm tra sau khi tích hợp

### 7.1 Kiểm tra Loki có nhận log

```powershell
kubectl logs -n elk-dung deploy/loki-dung --tail=100
```

Trong Grafana Explore:

- chọn datasource `Loki-Dung`
- query mẫu:
  - `{namespace="dung-lab"}`
  - `{service="frontend"}`

### 7.2 Kiểm tra nhánh ES vẫn hoạt động

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-fe-*/_count?q=@timestamp:%5Bnow-15m%20TO%20now%5D&pretty"
```

```powershell
kubectl logs -n elk-dung logstash-dung-logstash-0 --since=10m | findstr /I /C:"mapper_parsing_exception" /C:"Could not index event" /C:"Elasticsearch Unreachable"
```

---

## 8. Tối ưu tài nguyên (minimize)

Để phù hợp điều kiện node:

- Loki:
  - replica `1`
  - PVC `5Gi`
  - retention ngắn (`72h`) để tránh phình dung lượng
- Grafana:
  - replica `1`
  - PVC `2Gi`
- Không bật HA ở giai đoạn đầu.

---

## 9. Rollback nhanh (nếu cần)

Nếu cần tạm dừng nhánh Loki/Grafana:

```powershell
kubectl delete -f yaml_conf/grafana-dung.yaml
kubectl delete -f yaml_conf/loki-dung.yaml
```

Lưu ý:

- rollback này không ảnh hưởng nhánh `Fluent Bit -> Kafka -> Logstash -> Elasticsearch`.
