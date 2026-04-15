# Sổ Tay Khắc Phục Sự Cố (Troubleshooting Guide)

Tài liệu này tổng hợp toàn bộ các lỗi thực tế đã phát sinh trong quá trình triển khai hệ thống Logging (Elasticsearch, Kibana, Kafka, Fluent Bit), mô tả nguyên nhân gốc rễ và cung cấp các câu lệnh chuẩn xác nhất để kiểm tra, xử lý.

---

## I. Sự Cố Vận Hành Trạm Thông Điệp (Kafka & Strimzi)

### Lỗi 1.1: Kafka Pods kẹt ở trạng thái CrashLoopBackOff (Tràn ổ đĩa)
**1. Biểu hiện:** 
Các Pod chạy Broker như `my-cluster-combined-0`, `1`, `2` đồng loạt sập và vòng lặp khởi động liên tục báo `CrashLoopBackOff`. 

**2. Nguyên nhân gốc rễ:** 
Hệ giả lập `dung-lab` bơm log không ngừng vào hệ thống. Do lúc đầu phân vùng Topic chưa được quy định chính sách dọn dẹp, tổng lượng Message Log tràn khỏi giới hạn sức chứa 20GB. Khi ổ cứng vật lý cạn kiệt (100%), nền tảng bộ não của Kafka (KRaft Controller) thất bại trong việc ghi lại Metadata, dẫn đến từ chối khởi động và báo Error: `Fatal error while waiting for the controller to acknowledge`.

**3. Câu lệnh phát hiện:**
```powershell
# Xem trạng thái tuổi đời và số lần Restart
kubectl get pods -n kafka-dung

# Rút trích lỗi từ nhật ký trước khi chết (Previous Log)
kubectl logs -n kafka-dung my-cluster-combined-0 --previous | Select-String -Pattern "error"
```

**4. Cách khắc phục:**
Ngăn chặn hoàn toàn bằng cách cài đặt giới hạn dung lượng và tuổi thọ chốt chặn. 
Sửa file `my-topic.yaml` bằng cách thêm thông số ràng buộc:
```yaml
  config:
    retention.ms: 7200000       # Bắt buộc xóa rác cũ tuổi đời trên 2 tiếng
    retention.bytes: 2147483648 # Giao thức phanh khẩn: Đầy tới 2GB là khóa
```
Áp dụng lên cụm:
```powershell
kubectl apply -f my-topic.yaml -n kafka-dung
```

### Lỗi 1.2: Strimzi Operator Rơi Vào Lặp Chết (Deadlock Reconciliation)
**1. Biểu hiện:** 
- Đã cố tình dọn sạch PVC hay xóa Pods nhưng các Pod mới sinh ra cứ treo mãi ở trạng thái `Pending` báo lỗi `persistentvolumeclaim not found`.
- Con robot Strimzi Operator ngưng phản hồi vòng đời, không chịu cấp ổ cứng mới.

**2. Nguyên nhân gốc rễ:**
- Tính năng khai báo `KafkaNodePool` của bạn có gắn khóa `deleteClaim: false`, căn dặn kĩ Operator rằng tuyệt đối không được tự xóa ổ cứng.
- Bạn vô tình dùng lệnh thủ công `kubectl delete pvc` cắt bỏ các rễ liên kết này. Strimzi rơi vào vòng lặp vô tận (Stuck Reconciliation Loop) khi bối rối sửa chữa các Node cũ mà chờ mãi không được.

**3. Câu lệnh phát hiện:**
```powershell
# Kiểm tra log của bảng điều khiển trung tâm Operator
kubectl logs -n kafka-dung -l name=strimzi-cluster-operator --tail=50
# Nếu thấy log báo "Reconciliation is in progress" nhưng đứng im hoặc báo "Pod not responding" nhiều phút, tức là đã bị kẹt.
```

**4. Cách khắc phục:**
Cần rút điện Operator và khởi tạo lại mặt bằng sạch:
```powershell
# Bước 1: Diệt Operator hiện tại để thoát vòng lặp lỗi
kubectl delete pod -l name=strimzi-cluster-operator -n kafka-dung

# Bước 2: Dọn sạch mọi cấu hình dời rạc cũ rác của Cluster Kafka
kubectl delete -f Kafka_Official_K8s_Config.yaml -n kafka-dung

# Bước 3: Áp dụng lại cấu hình và Operator sẽ vẽ lại cụm mới 100% cực mượt
kubectl apply -f Kafka_Official_K8s_Config.yaml -n kafka-dung
```

### Tiện ích: Kiểm tra dung lượng ổ đĩa thực tế của Kafka
Dùng lệnh này để xem ổ đĩa `20Gi` hiện tại của các Broker đã bị lấp đầy bao nhiêu %:
```powershell
kubectl exec -n kafka-dung my-cluster-combined-0 -- df -h /var/lib/kafka/data-0
```

---

## II. Sự Cố Cài Đặt Bộ Trực Quan và Phân Tích (Kibana & Elasticsearch)

*(Lốc lỗi này được tổng hợp từ báo cáo triển khai Instance Kibana thứ 2 ẩn danh chuyên phục vụ tra cứu nhánh Logging)*

### Lỗi 2.1: Bị gián đoạn Timeout trong lúc kéo Image
**1. Biểu hiện:** Terminal chót vót hiện thông báo `timed out waiting for the condition` sau khi Helm treo 5 phút.
**2. Nguyên nhân:** Gói dữ liệu image của Kibana tương đối nặng (gần 1 GB), việc giải nén trên băng thông yếu khiến Hook của Helm bị mất kiên nhẫn.
**3. Cách khắc phục:** Khai trương lại bằng tham số nới lỏng mức chờ `10 phút`:
```powershell
helm install kibana-dung elastic/kibana --namespace elk -f kibana-logging-values.yaml --timeout 10m
```

### Lỗi 2.2: Sụp đổ FailedMount do thất lạc Secret TLS
**1. Biểu hiện:** K8s chặn khởi động báo lỗi không thể truy cập chứng chỉ kết nối TLS nội bộ.
**2. Nguyên nhân:** Chứa chấp tư duy dọn Kibana sang một namespace tinh khôi như `elk-dung` cho nhẹ gánh, nhưng quên mất hệ thống bảo mật SSL của Elasticsearch gốc (nằm tại namespace `elk`) quyết không cấp phép sang biên giới Namespace ngoài để mượn khóa.
**3. Cách khắc phục:** Bắt buộc phải đặt Kibana Log Search mới **vào cùng chung namespace `elk`**. Chỉ cần tách biệt nó bằng thuộc tính `kibana.index: ".kibana_logging"` trong file JSON thay vì chật vật xây namespace mới.

### Lỗi 2.3: Chướng ngại vật từ lần hủy cài đặt gần nhất (Kẹt Hook)
**1. Biểu hiện:** Cứ lôi lệnh cài Helm ra là nhận lại cục tức `configmap kibana-dung-kibana-helm-scripts already exists`.
**2. Nguyên nhân:** Mảnh vỡ từ lần cài thất bại trước đó nằm vật vờ trên Namespace.
**3. Cách rà soát và dọn dẹp:**
Xoá bỏ thủ công toàn bộ các mảnh rác móc treo đó trước khi xây mới:
```powershell
kubectl delete configmap kibana-dung-kibana-helm-scripts -n elk --ignore-not-found
kubectl delete serviceaccounts pre-install-kibana-dung-kibana -n elk --ignore-not-found
kubectl delete role pre-install-kibana-dung-kibana -n elk --ignore-not-found
kubectl delete rolebinding pre-install-kibana-dung-kibana -n elk --ignore-not-found
```

### Lỗi 2.4: Đặc quyền "elastic" bị vô hiệu hoá nội đệm
**1. Biểu hiện:** Chạy ngập lỗi đăng nhập: `value of "elastic" is forbidden`.
**2. Nguyên nhân:** Policy khép kín của ES 8.x cấm tuyệt đối việc sử dụng biến truyền User/Pass thẳng vào YAML để cắm sâu Kibana, đòi hỏi tính chứng thực qua Token.
**3. Cách khắc phục:** Xóa bỏ đi cấu hình username/password cho user `elastic` trong tệp cấu hình truyền thống trỏ file Cài đặt. Sau đó để Helm thả nổi tự do sinh ra một bộ Service Account Token chuyên biệt bảo mật hoàn hảo.

### Lỗi 2.5: Giao diện web báo sai tài khoản (Crossover Session)
**1. Biểu hiện:** Đã mở Port-forward sang 5602 (bản Kibana Log). Gõ mật khẩu `elastic` cực chuẩn nhưng vẫn bị báo login sai dữ liệu liên tục.
**2. Nguyên nhân:** Mâu thuẫn danh tính cookie! Trên cùng một tên miền định tuyến `localhost`, trình duyệt âm thầm ưu tiên dùng cục Cookie được cấp từ instance Kibana cũ ở Port 5601. Dữ liệu đâm sang nhau sinh ra sai lệch giải mã mã hóa token.
**3. Cách khắc phục:** Rất đơn giản, mở kết nối ứng dụng Port 5602 trên một **Cửa Sổ Trình Duyệt Ẩn Danh (Incognito/Private Tab)** rỗng Cookie để gõ lại Pass.

---

## III. Su co Logstash (vua gap thuc te) va cach xu ly

### Loi 3.1: `kubectl logs -l app=logstash` bao `No resources found in elk namespace`
**1. Bieu hien:**
- Chay lenh:
```powershell
kubectl logs -n elk -l app=logstash --tail=200
```
- Tra ve: `No resources found in elk namespace.`

**2. Nguyen nhan goc re:**
- Pod Logstash co ton tai, nhung label selector `app=logstash` khong khop label thuc te cua chart Helm.

**3. Huong xu ly:**
```powershell
# Tim Pod Logstash chac chan theo ten
kubectl get pods -A | findstr /I logstash

# Xem label thuc te
kubectl get pods -n elk --show-labels | findstr /I logstash

# Xem log theo ten pod (an toan nhat)
kubectl logs -n elk logstash-dung-logstash-0 --tail=200
kubectl logs -n elk logstash-dung-logstash-0 --since=10m
```

### Loi 3.2: `docs.count` khong tang (nghi log khong di vao Elasticsearch)
**1. Bieu hien:**
- Chay `_cat/indices/dung-*` nhieu lan nhung `docs.count` gan nhu khong doi.

**2. Nguyen nhan goc re:**
- `docs.count` tong co the tang cham hoac kho quan sat trong khoang thoi gian ngan.
- Can kiem tra theo `@timestamp` document moi nhat de biet pipeline co di hay khong.

**3. Huong xu ly (khoanh vung theo tung tang):**
```powershell
# A) Nguon sinh log
kubectl get pods -n dung-lab
kubectl logs -n dung-lab -l app=dung-fe-log-generator --tail=5
kubectl logs -n dung-lab -l app=dung-be-log-generator --tail=5

# B) Fluent Bit -> Kafka
kubectl logs -n elk -l app.kubernetes.io/name=fluent-bit --since=5m

# C) Kafka consumer group cua Logstash
kubectl exec -n kafka-dung my-cluster-combined-0 -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group logstash-consumer-group-2

# D) Kiem tra document moi nhat theo timestamp
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ "https://localhost:9200/dung-fe-*/_search?size=1&sort=@timestamp:desc"
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ "https://localhost:9200/dung-be-*/_search?size=1&sort=@timestamp:desc"
```

### Loi 3.3: Logstash ban loi `Elasticsearch Unreachable [http://elasticsearch:9200/]`
**1. Bieu hien:**
- Log co chuoi:
  - `Elasticsearch Unreachable [http://elasticsearch:9200/]`
  - `Name or service not known`
  - `logstash.licensechecker.licensereader`

**2. Nguyen nhan goc re:**
- `pipeline/logstash.conf` da dung host ES.
- Nhung `config/logstash.yml` van de monitoring host sai:
  - `xpack.monitoring.elasticsearch.hosts: ["http://elasticsearch:9200"]`
- DNS `elasticsearch` khong ton tai trong namespace nen monitoring checker loi lien tuc.

**3. Cau lenh phat hien:**
```powershell
kubectl exec -n elk logstash-dung-logstash-0 -- cat /usr/share/logstash/pipeline/logstash.conf
kubectl exec -n elk logstash-dung-logstash-0 -- cat /usr/share/logstash/config/logstash.yml
kubectl logs -n elk logstash-dung-logstash-0 --since=5m
```

**4. Huong xu ly:**
- Cap nhat `logstash-values.yaml` de ghi de `logstash.yml`:
```yaml
logstashConfig:
  logstash.yml: |
    http.host: "0.0.0.0"
    xpack.monitoring.enabled: false
```
- Apply lai Helm release:
```powershell
helm upgrade --install logstash-dung elastic/logstash -n elk -f logstash-values.yaml
kubectl rollout status statefulset/logstash-dung-logstash -n elk
```

**5. Xac nhan da khac phuc:**
```powershell
# Khong con loi elasticsearch:9200
kubectl logs -n elk logstash-dung-logstash-0 --since=5m | findstr /I "Elasticsearch Unreachable elasticsearch:9200"

# Co document moi theo timestamp
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ "https://localhost:9200/dung-fe-*/_search?size=1&sort=@timestamp:desc"
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ "https://localhost:9200/dung-be-*/_search?size=1&sort=@timestamp:desc"
```

### Loi 3.4: Popup Windows `ms-screenclip://?source=HotKey`
**1. Bieu hien:**
- Trong luc thao tac terminal xuat hien popup:
  - `This file does not have an app associated with it...`
  - URI: `ms-screenclip://?source=HotKey`

**2. Nguyen nhan goc re:**
- Loi association cua he dieu hanh Windows (Snipping Tool / Screen Clip), **khong lien quan** Kubernetes, Logstash, Kafka hay Elasticsearch.

**3. Huong xu ly:**
- Co the bo qua khi debug ha tang log.
- Neu can sua tren may tram: cai/repair Snipping Tool va gan lai default app cho giao thuc `ms-screenclip`.

---

## IV. Chuan kiem tra nhanh pipeline Logstash sau moi lan chinh cau hinh
```powershell
# 1) Pod Logstash
kubectl get pods -n elk | findstr /I logstash

# 2) Log runtime 5 phut gan nhat
kubectl logs -n elk logstash-dung-logstash-0 --since=5m

# 3) Kafka lag consumer group
kubectl exec -n kafka-dung my-cluster-combined-0 -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group logstash-consumer-group-2

# 4) ES doc moi nhat
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ "https://localhost:9200/dung-fe-*/_search?size=1&sort=@timestamp:desc"
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ "https://localhost:9200/dung-be-*/_search?size=1&sort=@timestamp:desc"
```