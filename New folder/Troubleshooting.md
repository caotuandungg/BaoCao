# Sổ Tay Khắc Phục Sự Cố

Tài liệu này tổng hợp các lỗi thực tế đã gặp trong quá trình dựng và vận hành hệ thống logging của bạn.

Phạm vi hệ thống hiện tại:

- `Fluent Bit -> Kafka -> Logstash -> Elasticsearch`
- Elasticsearch riêng của bạn chạy trong namespace `elk-dung`
- Kafka riêng của bạn chạy trong namespace `kafka-dung`
- Workload sinh log chạy trong namespace `dung-lab`

Mỗi mục bên dưới gồm:

- Biểu hiện
- Nguyên nhân gốc rễ
- Câu lệnh kiểm tra
- Hướng xử lý

---

## I. Luồng tổng quát cần nhớ

Luồng đúng của hệ thống là:

1. Pod trong `dung-lab` sinh log JSON ra `stdout/stderr`
2. Fluent Bit đọc file log container trên node và đẩy vào Kafka topic `dung-logs-topic`
3. Logstash consume Kafka topic, parse JSON, route theo `service`
4. Logstash ghi document vào Elasticsearch qua write alias
5. Kibana đọc dữ liệu từ Elasticsearch

Nếu Kibana không hiện log thì chưa chắc Kibana lỗi. Cần kiểm tra ngược từng tầng:

1. Pod nguồn còn sinh log không
2. Fluent Bit còn đọc và gửi không
3. Kafka còn có message mới không
4. Logstash có lag lớn hoặc lỗi output không
5. Elasticsearch có nhận document mới trong 15 phút gần nhất không

---

## II. Fluent Bit

### Lỗi 2.1: Fluent Bit chỉ đọc `dung-lab`, không đọc toàn cluster

**Biểu hiện**

- Hệ thống lab chạy ổn
- Nhưng log ngoài `dung-lab` không đi vào pipeline

**Nguyên nhân gốc rễ**

- Trong input của Fluent Bit đang để:

```ini
Path /var/log/containers/*_dung-lab_*.log
```

- Cấu hình này chỉ lấy log của namespace `dung-lab`
- Phù hợp để test lab, nhưng không phù hợp nếu mục tiêu là quan sát toàn cluster

**Câu lệnh kiểm tra**

```powershell
kubectl get configmap fluent-bit -n elk-dung -o jsonpath='{.data.fluent-bit\.conf}'
```

**Hướng xử lý**

- Nếu chỉ test project lab thì giữ nguyên là hợp lý
- Nếu muốn quan sát toàn cluster thì đổi `Path` sang toàn bộ container log và lọc hợp lý ở tầng sau

Ví dụ:

```ini
Path /var/log/containers/*.log
```

Lưu ý:

- Khi mở rộng sang toàn cluster, cần siết chặt filter hoặc routing ở Logstash
- Nếu không, `cluster-khác` sẽ rất nhiều log và dễ kéo lag cả pipeline

---

## III. Kafka và Strimzi

### Lỗi 3.1: Kafka bị đầy đĩa hoặc dễ phình to do retention chưa hợp lý

**Biểu hiện**

- PVC Kafka tăng nhanh
- Node bị tốn nhiều `ephemeral storage` hoặc `persistent storage`
- Broker có thể chậm, lag tăng, hoặc thậm chí restart

**Nguyên nhân gốc rễ**

- Topic `dung-logs-topic` nhận rất nhiều log
- Nếu retention quá dài hoặc dung lượng topic không bị giới hạn, Kafka sẽ phình to nhanh

**Câu lệnh kiểm tra**

```powershell
kubectl get pvc -n kafka-dung -o wide
kubectl get kafkatopic -n kafka-dung
kubectl get kafkatopic dung-logs-topic -n kafka-dung -o yaml
```

**Hướng xử lý**

- Giới hạn retention theo thời gian và dung lượng
- Chỉ để mức đủ cho nhu cầu debug hoặc replay ngắn hạn

Ví dụ:

```yaml
config:
  retention.ms: 7200000
  retention.bytes: 2147483648
```

---

### Lỗi 3.2: `partition = 3` là gì, có nên giảm còn `1` không

**Biểu hiện**

- Muốn giảm chi phí tài nguyên Kafka
- Phân vân giữa `partition = 3` và `partition = 1`

**Nguyên nhân gốc rễ**

- Partition quyết định mức song song khi producer ghi và consumer đọc
- Nhiều partition hơn thì scale đọc tốt hơn, nhưng cũng tăng overhead

**Giải thích ngắn**

- `partition = 3` nghĩa là topic được chia thành 3 phần log độc lập
- Consumer group có thể đọc song song tối đa theo số partition
- Nếu chỉ có 1 Logstash pod consume thực tế thì `partition = 3` chưa chắc tận dụng hết

**Khi nào để `1`**

- Log volume nhỏ đến vừa
- Chỉ 1 consumer chính
- Muốn tối giản tài nguyên

**Rủi ro nếu để `1`**

- Không scale ngang việc consume theo topic được
- Khi backlog tăng mạnh thì chỉ có 1 luồng đọc, dễ bị chậm

**Khuyến nghị cho hệ thống lab**

- Nếu mục tiêu là tiết kiệm tối đa tài nguyên và log không quá lớn, `partition = 1` là chấp nhận được
- Nếu sau này muốn HA hoặc scale Logstash lên nhiều replica để cùng consume, nên để `partition > 1`

---

### Lỗi 3.3: Strimzi entity operator báo warning probe fail

**Biểu hiện**

- Trên dashboard có cảnh báo kiểu:
  - `Startup probe failed`
  - `connect: connection refused`

**Nguyên nhân gốc rễ**

- `userOperator` không cần cho bài toán hiện tại nhưng vẫn được bật
- Pod operator khởi động phần health check không ổn định hoặc không cần thiết

**Hướng xử lý**

- Bỏ block `userOperator` trong cấu hình Kafka nếu bạn không dùng quản lý KafkaUser
- Apply lại manifest Kafka

Điều này giúp:

- Giảm một thành phần thừa
- Giảm restart/warning không cần thiết
- Tối giản tài nguyên cho hệ thống lab

---

## IV. Logstash

### Lỗi 4.1: `kubectl logs -l app=logstash` trả về `No resources found`

**Biểu hiện**

- Dùng selector cũ như:

```powershell
kubectl logs -n elk -l app=logstash --tail=200
```

- Nhưng kết quả là:

```text
No resources found
```

**Nguyên nhân gốc rễ**

- Label selector không khớp với chart Helm thực tế
- Tên release và label của chart Logstash không phải `app=logstash`

**Câu lệnh kiểm tra**

```powershell
kubectl get pods -n elk-dung | findstr /I logstash
kubectl get pods -n elk-dung -l app=logstash-dung-logstash -o wide
```

**Hướng xử lý**

- Log trực tiếp theo tên pod
- Hoặc dùng label selector đúng với release hiện tại

```powershell
kubectl logs -n elk-dung logstash-dung-logstash-0 --tail=200
kubectl logs -n elk-dung logstash-dung-logstash-0 --since=10m
```

---

### Lỗi 4.2: Logstash báo `Elasticsearch Unreachable [http://elasticsearch:9200/]`

**Biểu hiện**

- Log Logstash có các dòng:
  - `Elasticsearch Unreachable`
  - `http://elasticsearch:9200/`
  - `Name or service not known`

**Nguyên nhân gốc rễ**

- Pipeline output đã trỏ đúng sang Elasticsearch
- Nhưng phần `logstash.yml` hoặc xpack monitoring vẫn giữ host cũ là `http://elasticsearch:9200`
- DNS đó không tồn tại trong namespace hiện tại

**Câu lệnh kiểm tra**

```powershell
kubectl exec -n elk-dung logstash-dung-logstash-0 -- cat /usr/share/logstash/config/logstash.yml
kubectl logs -n elk-dung logstash-dung-logstash-0 --since=5m
```

**Hướng xử lý**

- Tắt monitoring nếu không cần
- Hoặc sửa đúng host monitoring

Ví dụ tối giản:

```yaml
logstashConfig:
  logstash.yml: |
    http.host: "0.0.0.0"
    xpack.monitoring.enabled: false
```

Sau đó update lại release Logstash.

---

### Lỗi 4.3: Logstash không lỗi nhưng Kibana vẫn không có log mới

**Biểu hiện**

- Pod Logstash `Running`
- Kafka vẫn có message mới
- Nhưng Elasticsearch không có document mới trong `15 minutes`
- Kibana Discover hiện `No results match your search criteria`

**Nguyên nhân gốc rễ**

- Logstash vẫn sống nhưng đang bị backlog lớn
- Đồng thời bị kẹt bởi output lỗi ở index `cluster-khac-*`
- Kết quả là log mới của 4 service vào ES rất chậm hoặc chưa tới nơi

**Câu lệnh kiểm tra**

```powershell
kubectl exec -n kafka-dung my-cluster-combined-0 -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group logstash-consumer-group-2

kubectl logs -n elk-dung logstash-dung-logstash-0 --since=10m

kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-be-*/_count?q=@timestamp:%5Bnow-15m%20TO%20now%5D&pretty"
```

**Dấu hiệu nhận biết**

- `LAG` tăng lớn
- Không có member active hoặc member đọc rất chậm
- ES `_count` 15 phút gần nhất bằng `0`

**Hướng xử lý**

1. Kiểm tra Logstash đang kẹt vì index nào
2. Xử lý index lỗi
3. Nếu backlog quá lớn và chấp nhận bỏ qua log cũ, reset offset về latest

Ví dụ reset:

```powershell
kubectl scale statefulset/logstash-dung-logstash -n elk-dung --replicas=0

kubectl exec -n kafka-dung my-cluster-combined-0 -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group logstash-consumer-group-2 --topic dung-logs-topic --reset-offsets --to-latest --execute

kubectl scale statefulset/logstash-dung-logstash -n elk-dung --replicas=1
kubectl rollout status statefulset/logstash-dung-logstash -n elk-dung
```

Lưu ý:

- Cách này bỏ qua backlog cũ
- Chỉ dùng khi bạn ưu tiên lấy log mới ngay lập tức

---

### Lỗi 4.4: `mapper_parsing_exception` ở `cluster-khac-*`

**Biểu hiện**

- Logstash log có các chuỗi:
  - `mapper_parsing_exception`
  - `Could not index event`
  - `failed to parse field`

**Nguyên nhân gốc rễ**

- Dữ liệu log ngoài 4 service chính đi vào index `cluster-khac-*`
- Một số field lồng nhau, đặc biệt các field kiểu `pod_labels`, thay đổi cấu trúc giữa các document
- Mapping của index trước đó đã chốt kiểu khác, document sau đi vào bị conflict

**Câu lệnh kiểm tra**

```powershell
kubectl logs -n elk-dung logstash-dung-logstash-0 --since=10m | findstr /I /C:"mapper_parsing_exception" /C:"Could not index event" /C:"failed to parse field"
```

Nếu không hiện gì, nghĩa là trong khoảng log đang xem không còn lỗi đó nữa.

**Hướng xử lý**

- Loại bỏ các field dễ conflict trước khi ghi ES
- Đặc biệt là các field pod label lồng sâu trong `cluster-khác`

Ví dụ đã từng phải bỏ:

- `[process_exec][parent][pod][pod_labels]`
- `[process_exec][process][pod][pod_labels]`
- `[process_exit][process][pod][pod_labels]`
- `[process_exit][parent][pod][pod_labels]`

Sau khi sửa pipeline:

```powershell
helm upgrade --install logstash-dung elastic/logstash -n elk-dung -f logstash-values.yaml
kubectl rollout status statefulset/logstash-dung-logstash -n elk-dung
```

---

## V. Elasticsearch và ILM

### Lỗi 5.1: Elasticsearch riêng trên `wk03` chưa có ILM, template, alias

**Biểu hiện**

- Chạy:

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/_ilm/policy/logs-lab-policy?pretty"
```

- Kết quả:
  - `resource_not_found_exception`
  - `Lifecycle policy not found`

- Hoặc:

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-fe-000001/_ilm/explain?pretty"
```

- Báo:
  - `index_not_found_exception`

**Nguyên nhân gốc rễ**

- Elasticsearch mới trên `elk-dung` vừa dựng lại
- Nhưng script bootstrap `setup-es-logging.ps1` chưa được chạy

**Hướng xử lý**

```powershell
.\setup-es-logging.ps1
```

**Câu lệnh xác nhận**

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/_ilm/policy/logs-lab-policy?pretty"
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/_cat/aliases/dung-*?v"
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-fe-write/_ilm/explain?pretty"
```

Nếu đúng thì sẽ thấy:

- policy `logs-lab-policy` tồn tại
- có write alias `dung-fe-write`, `dung-be-write`, `dung-db-write`, `dung-web-write`
- index đang được ILM quản lý với `managed: true`

---

### Lỗi 5.2: `invalid_alias_name_exception` khi chạy `setup-es-logging.ps1`

**Biểu hiện**

- Script báo:
  - `Invalid alias name [dung-fe-write]`
  - `an index or data stream exists with the same name as the alias`

**Nguyên nhân gốc rễ**

- Trước khi ILM được bootstrap, Logstash đã ghi trực tiếp vào các tên:
  - `dung-fe-write`
  - `dung-be-write`
  - `dung-db-write`
  - `dung-web-write`

- Elasticsearch tạo hẳn index thật với các tên đó
- Khi script cố tạo alias cùng tên thì bị xung đột

**Câu lệnh kiểm tra**

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/_cat/indices/dung-*-write?v"
```

**Hướng xử lý**

1. Scale Logstash về `0`
2. Xóa các index đang chiếm tên alias
3. Chạy lại script setup
4. Scale Logstash lên lại

```powershell
kubectl scale statefulset/logstash-dung-logstash -n elk-dung --replicas=0

kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN -X DELETE "https://localhost:9200/dung-fe-write"
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN -X DELETE "https://localhost:9200/dung-be-write"
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN -X DELETE "https://localhost:9200/dung-db-write"
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN -X DELETE "https://localhost:9200/dung-web-write"

.\setup-es-logging.ps1

kubectl scale statefulset/logstash-dung-logstash -n elk-dung --replicas=1
kubectl rollout status statefulset/logstash-dung-logstash -n elk-dung
```

---

### Lỗi 5.3: Kibana không hiện log trong 15 phút gần nhất dù pod vẫn chạy

**Biểu hiện**

- Kibana Discover báo:
  - `No results match your search criteria`
- Nhưng pod nguồn vẫn sinh log bình thường

**Nguyên nhân gốc rễ**

- Đây không phải lỗi giao diện Kibana
- Elasticsearch lúc đó thật sự chưa có document mới trong 15 phút gần nhất
- Lý do sâu hơn là Logstash bị backlog và bị chậm bởi lỗi ở `cluster-khac-*`

**Cách phân biệt nhanh**

Nếu Kibana để `24 hours` thì thấy log, còn `15 minutes` không thấy, nghĩa là:

- dữ liệu cũ vẫn còn
- nhưng ingest realtime đang chậm hoặc ngừng

**Câu lệnh kiểm tra**

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-fe-*/_count?q=@timestamp:%5Bnow-15m%20TO%20now%5D&pretty"

kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-fe-*/_search?size=1&sort=@timestamp:desc&pretty"
```

**Cách đọc**

- Nếu `_count` bằng `0` thì Elasticsearch chưa nhận log mới trong 15 phút gần nhất
- Hãy nhìn `@timestamp` của document mới nhất để biết log đang trễ bao lâu

---

### Lỗi 5.4: Index `cluster-khac-*` bị `red`, shard không active

**Biểu hiện**

- Logstash log có `unavailable_shards_exception`
- Nội dung nhắc đến `cluster-khac-YYYY.MM.DD`
- Consumer lag tăng mạnh

**Nguyên nhân gốc rễ**

- Index `cluster-khac-*` có primary shard không active
- Logstash cố ghi vào index lỗi này nên bị retry liên tục
- Retry làm chậm cả pipeline

**Câu lệnh kiểm tra**

```powershell
kubectl logs -n elk-dung logstash-dung-logstash-0 --since=10m

kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/_cat/indices/cluster-khac-*?v"

kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/_cluster/health/cluster-khac-2026.04.20?pretty"
```

**Hướng xử lý**

- Nếu đó là index lỗi tạm thời và bạn chấp nhận bỏ dữ liệu của index đó, có thể xóa index đỏ
- Sau đó restart Logstash để nó thoát vòng retry

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN -X DELETE "https://localhost:9200/cluster-khac-2026.04.20"

kubectl delete pod -n elk-dung logstash-dung-logstash-0
kubectl rollout status statefulset/logstash-dung-logstash -n elk-dung
```

---

### Lỗi 5.5: ILM cũ trên Elasticsearch của người khác vẫn còn sau khi bạn chuyển sang ES riêng

**Biểu hiện**

- Bạn đã chuyển hệ thống sang `elk-dung`
- Nhưng trên ES cũ trong namespace `elk` vẫn còn:
  - index `dung-*`
  - alias `dung-*`
  - template `dung-*-template`
  - policy `logs-lab-policy`

**Nguyên nhân gốc rễ**

- Tài nguyên cũ không tự mất khi bạn đổi sang cụm ES riêng
- Chúng cần được dọn thủ công

**Câu lệnh kiểm tra**

```powershell
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ "https://localhost:9200/_cat/indices/dung-*?v"
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ "https://localhost:9200/_cat/aliases/dung-*?v"
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ "https://localhost:9200/_ilm/policy/logs-lab-policy?pretty"
```

**Hướng xử lý**

- Chỉ dọn tài nguyên của bạn trên ES cũ, không đụng tài nguyên người khác

Các bước đã dùng:

1. Gỡ ILM khỏi các index `dung-*`
2. Xóa template `dung-*-template`
3. Xóa policy `logs-lab-policy`
4. Xóa các index `dung-*` bằng tên cụ thể

Ví dụ:

```powershell
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ -X POST "https://localhost:9200/dung-*/_ilm/remove?expand_wildcards=all"

kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ -X DELETE "https://localhost:9200/_index_template/dung-fe-template"
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ -X DELETE "https://localhost:9200/_index_template/dung-be-template"
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ -X DELETE "https://localhost:9200/_index_template/dung-db-template"
kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ -X DELETE "https://localhost:9200/_index_template/dung-web-template"

kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ -X DELETE "https://localhost:9200/_ilm/policy/logs-lab-policy"
```

Lưu ý:

- Nếu ES bật `action.destructive_requires_name=true` thì không xóa wildcard index được
- Khi đó phải lấy danh sách index thật rồi xóa từng tên cụ thể

---

## VI. Kibana và Dashboard

### Lỗi 6.1: Kibana Discover trống nhưng pod vẫn `Running`

**Biểu hiện**

- Mọi pod đều `Running`
- Vào Discover không thấy dữ liệu

**Nguyên nhân gốc rễ**

- `Running` chỉ chứng minh pod còn sống
- Không chứng minh được dữ liệu đã vào ES theo thời gian thực
- Lúc đã gặp thực tế, nguyên nhân là:
  - Logstash lag lớn
  - `cluster-khac-*` bị shard lỗi
  - ES không có document mới trong `15m`

**Hướng xử lý**

- Không dừng ở bước `kubectl get pods`
- Luôn kiểm tra thêm 3 thứ:

```powershell
kubectl exec -n kafka-dung my-cluster-combined-0 -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group logstash-consumer-group-2

kubectl logs -n elk-dung logstash-dung-logstash-0 --since=10m

kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-be-*/_count?q=@timestamp:%5Bnow-15m%20TO%20now%5D&pretty"
```

---

### Lỗi 6.2: Dashboard báo `Field service.keyword was not found`

**Biểu hiện**

- Panel dashboard lỗi:
  - `Field service.keyword was not found`
  - `Field error_code.keyword was not found`

**Nguyên nhân gốc rễ**

- Dashboard cũ đang tham chiếu các field dạng `.keyword`
- Nhưng mapping hiện tại của index là static và field đã có kiểu `keyword` trực tiếp
- Ví dụ:
  - `service` đã là `keyword`
  - `error_code` đã là `keyword`
- Vì vậy sẽ không có subfield `.keyword`

**Câu lệnh kiểm tra**

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-be-000003/_mapping?pretty"
```

**Hướng xử lý**

- Sửa visualization:
  - `service.keyword` -> `service`
  - `error_code.keyword` -> `error_code`

- Sau đó refresh lại field list của data view trong Kibana nếu cần

---

## VII. Script và thao tác kiểm tra

### Lỗi 7.1: Script check E2E báo `count=0` dù chạy tay thấy có dữ liệu

**Biểu hiện**

- Script PowerShell check E2E báo WARN hoặc FAIL vì `count=0`
- Nhưng khi copy cùng lệnh ra terminal chạy tay lại thấy `count > 0`

**Nguyên nhân gốc rễ**

- Chuỗi query khi ghép trong PowerShell dễ bị escape sai
- URL tới Elasticsearch bị khác giữa script và lệnh gõ tay
- Hoặc script parse JSON/count chưa đúng

**Bài học rút ra**

- Với các lệnh `_count`, `_search`, nên in ra URL cuối cùng nếu script báo sai
- Nên dùng `?pretty` khi debug
- Nên parse JSON bằng `ConvertFrom-Json` sau khi chắc output sạch

**Câu lệnh kiểm tra chuẩn**

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-fe-*/_count?q=@timestamp:%5Bnow-15m%20TO%20now%5D&pretty"
```

---

## VIII. Giải thích vì sao tuần trước chạy ngon nhưng sau 2 ngày lại lỗi

Đây là phần rất quan trọng.

Hệ thống của bạn lỗi không phải vì tự nhiên Kibana hỏng, mà vì có nhiều điểm cộng dồn:

1. Bạn chuyển dần từ ES cũ sang ES riêng nên có giai đoạn alias, template, ILM chưa bootstrap đủ
2. Logstash từng ghi thẳng vào tên alias, tạo conflict `invalid_alias_name_exception`
3. `cluster-khac` dùng chung topic với 4 service chính, nên khi `cluster-khac` lỗi mapping hoặc shard thì Logstash bị chậm toàn cục
4. Kafka backlog tăng nhưng pod vẫn `Running`, làm ta dễ tưởng hệ thống vẫn ổn
5. Dashboard Kibana đang dùng field schema cũ như `.keyword`, không còn khớp mapping mới

Nói ngắn gọn:

- Tuần trước dữ liệu còn ít, backlog nhỏ, shard chưa lỗi, nên mọi thứ trông ổn
- Sau 1 đến 2 ngày, dữ liệu tích lại, sai lệch cấu hình nhỏ bắt đầu lộ rõ

Đây là kiểu lỗi rất thường gặp ở logging pipeline:

- ban đầu chạy được
- sau vài ngày mới lộ ra vấn đề về mapping, lag, retention, alias, ILM

---

## IX. Bộ lệnh kiểm tra nhanh khi nghi ngờ hệ thống lỗi

### 1. Pod nguồn còn sinh log không

```powershell
kubectl logs -n dung-lab deployment/dung-fe-log-generator --tail=5
kubectl logs -n dung-lab deployment/dung-be-log-generator --tail=5
kubectl logs -n dung-lab deployment/dung-db-log-generator --tail=5
kubectl logs -n dung-lab deployment/dung-web-log-generator --tail=5
```

### 2. Fluent Bit còn chạy không

```powershell
kubectl get pods -n elk-dung -l app.kubernetes.io/name=fluent-bit -o wide
kubectl logs -n elk-dung -l app.kubernetes.io/name=fluent-bit --since=5m --tail=120
```

### 3. Kafka còn có message mới không

```powershell
kubectl exec -n kafka-dung my-cluster-combined-0 -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic dung-logs-topic --max-messages 20 --timeout-ms 10000
```

### 4. Logstash có đang lag không

```powershell
kubectl exec -n kafka-dung my-cluster-combined-0 -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group logstash-consumer-group-2
```

### 5. Logstash có lỗi output hoặc parsing không

```powershell
kubectl logs -n elk-dung logstash-dung-logstash-0 --since=10m

kubectl logs -n elk-dung logstash-dung-logstash-0 --since=10m | findstr /I /C:"mapper_parsing_exception" /C:"Could not index event" /C:"failed to parse field" /C:"Elasticsearch Unreachable" /C:"unavailable_shards_exception"
```

### 6. Elasticsearch có nhận log mới trong 15 phút gần nhất không

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-fe-*/_count?q=@timestamp:%5Bnow-15m%20TO%20now%5D&pretty"
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-be-*/_count?q=@timestamp:%5Bnow-15m%20TO%20now%5D&pretty"
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-db-*/_count?q=@timestamp:%5Bnow-15m%20TO%20now%5D&pretty"
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-web-*/_count?q=@timestamp:%5Bnow-15m%20TO%20now%5D&pretty"
```

### 7. Xem document mới nhất

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-fe-*/_search?size=1&sort=@timestamp:desc&pretty"
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-be-*/_search?size=1&sort=@timestamp:desc&pretty"
```

### 8. Kiểm tra ILM của ES riêng

```powershell
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/_ilm/policy/logs-lab-policy?pretty"
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/dung-fe-write/_ilm/explain?pretty"
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:1xNIfTEXaH0MsbQN "https://localhost:9200/_cat/aliases/dung-*?v"
```

---

## X. Kết luận ngắn

Những lỗi bạn đã gặp chủ yếu rơi vào 4 nhóm:

1. Bootstrap ES riêng chưa hoàn chỉnh: thiếu ILM, alias, template
2. Logstash bị kéo chậm bởi `cluster-khac-*` và backlog Kafka
3. Kibana dashboard dùng field schema cũ
4. Một số thành phần ban đầu cấu hình đúng để test lab nhưng chưa đủ tốt cho vận hành dài ngày

Nếu sau này gặp lại tình trạng "pod vẫn chạy nhưng Kibana trống", hãy kiểm tra theo thứ tự:

1. `_count` 15 phút gần nhất trong Elasticsearch
2. consumer lag của Logstash
3. log lỗi của Logstash
4. index `cluster-khac-*`
5. ILM và alias của ES riêng

Đó là đường ngắn nhất để tìm ra lỗi thật.
