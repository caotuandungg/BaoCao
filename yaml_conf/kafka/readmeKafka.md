# README Kafka External Ingress

File này ghi lại quy trình đã làm để mở đường cho log từ VM bên ngoài k8s đi vào Kafka riêng trong namespace `kafka-dung`, thông qua NGINX Ingress TLS passthrough.

Nguyên tắc quan trọng:

- Không sửa Kafka/Strimzi/Ingress của người khác trong namespace `kafka`.
- Chỉ đọc tài nguyên có sẵn để học cách route.
- Chỉ apply/patch tài nguyên thuộc namespace của mình: `kafka-dung`.
- RBAC cluster-scoped nếu có tạo thì chỉ bind vào service account `kafka-dung:strimzi-cluster-operator`.

## Mục tiêu

VM chạy 4 app Python sinh log. Fluent Bit trên VM sẽ gửi log vào Kafka topic riêng:

```text
vm-logs-topic
```

Đường đi mong muốn:

```text
VM Fluent Bit
  -> dung-my-cluster-b0.kafka.vnpost.cloud:443
  -> NGINX Ingress TLS passthrough
  -> TransportServer trong namespace kafka-dung
  -> Kafka external listener của my-cluster
  -> topic vm-logs-topic
```

## Các file liên quan

```text
yaml_conf/kafka/Kafka_Official_K8s_Config.yaml
yaml_conf/kafka/my-cluster-nginx-transportservers.yaml
yaml_conf/kafka/my-topic.yaml
yaml_conf/kafka/my-cluster-external-dns-notes.md
yaml_conf/kafka/export-my-cluster-ca-for-vm.ps1
yaml_conf/kafka/my-cluster-ca.crt
yaml_conf/kafka/strimzi-kafka-dung-global-rbac.yaml
yaml_conf/kafka/strimzi-kafka-dung-node-rbac.yaml
yaml_conf/kafka/strimzi-dung-operator-tmp-patch.md
```

## 1. Kiểm tra mô hình Kafka có sẵn

Ban đầu mình chỉ kiểm tra read-only Kafka/Ingress có sẵn của người khác để hiểu mô hình route.

Các điểm học được:

- Kafka có external TLS listener.
- NGINX Ingress dùng `TransportServer`.
- Listener của NGINX là `tls-passthrough`, port `443`, protocol `TLS_PASSTHROUGH`.
- Với Kafka riêng của mình đang dùng `nodeport` + `TransportServer`, Fluent Bit dùng broker domain `b0` làm bootstrap luôn.
- Có route riêng cho broker `0`.
- DNS trỏ domain Kafka về IP public của NGINX Ingress.

Lưu ý: phần này chỉ `get/describe`, không apply hoặc patch tài nguyên của người khác.

## 2. Thêm external listener cho Kafka riêng

File đã sửa:

```text
yaml_conf/kafka/Kafka_Official_K8s_Config.yaml
```

Trong Kafka `my-cluster` namespace `kafka-dung`, thêm listener:

```yaml
- name: external2
  port: 9095
  type: nodeport
  tls: true
  configuration:
    brokers:
      - broker: 0
        advertisedHost: dung-my-cluster-b0.kafka.vnpost.cloud
        advertisedPort: 443
```

Ý nghĩa:

- Kafka vẫn chạy trong k8s.
- Strimzi tạo service NodePort cho bootstrap và broker.
- Client bên ngoài không đi trực tiếp vào NodePort, mà đi qua domain `*.kafka.vnpost.cloud:443`.
- Kafka broker quảng bá địa chỉ external là `dung-my-cluster-b0.kafka.vnpost.cloud:443`.

Lệnh apply:

```powershell
kubectl apply -n kafka-dung -f .\yaml_conf\kafka\Kafka_Official_K8s_Config.yaml
```

## 3. Tạo TransportServer cho NGINX Ingress

File đã tạo:

```text
yaml_conf/kafka/my-cluster-nginx-transportservers.yaml
```

Có 2 route:

```text
dung-my-cluster-b0.kafka.vnpost.cloud -> my-cluster-combined-external2-0:9095
```

Lệnh apply:

```powershell
kubectl apply -f .\yaml_conf\kafka\my-cluster-nginx-transportservers.yaml
```

Kiểm tra:

```powershell
kubectl get transportserver -n kafka-dung
kubectl describe transportserver my-cluster-kafka-broker-0-ts -n kafka-dung
```

Trạng thái đúng là `Valid`.

## 4. DNS cần có

File ghi chú:

```text
yaml_conf/kafka/my-cluster-external-dns-notes.md
```

DNS cần trỏ về public IP của NGINX Ingress:

```text
dung-my-cluster-b0.kafka.vnpost.cloud -> 103.252.73.212
```

Kiểm tra DNS:

```powershell
Resolve-DnsName dung-my-cluster-b0.kafka.vnpost.cloud
```

## 5. Tạo Kafka topic cho log từ VM

File đã sửa:

```text
yaml_conf/kafka/my-topic.yaml
```

Trong file này có thêm topic:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: vm-logs-topic
  namespace: kafka-dung
  labels:
    strimzi.io/cluster: my-cluster
spec:
  partitions: 1
  replicas: 1
```

Lệnh apply:

```powershell
kubectl apply -n kafka-dung -f .\yaml_conf\kafka\my-topic.yaml
```

Kiểm tra:

```powershell
kubectl get kafkatopic -n kafka-dung
```

Topic đúng là `Ready=True`.

## 6. Export CA cert cho VM Fluent Bit

Vì Kafka external listener dùng TLS, Fluent Bit trên VM cần CA cert của Kafka cluster.

File script:

```text
yaml_conf/kafka/export-my-cluster-ca-for-vm.ps1
```

Script export secret:

```text
my-cluster-cluster-ca-cert
```

ra file:

```text
yaml_conf/kafka/my-cluster-ca.crt
```

Trên VM cần copy CA này vào:

```bash
/etc/fluent-bit/kafka-ca.crt
```

Ví dụ nếu repo đã được pull trên VM ở `/opt/bocao-gitops`:

```bash
sudo cp /opt/bocao-gitops/yaml_conf/kafka/my-cluster-ca.crt /etc/fluent-bit/kafka-ca.crt
sudo systemctl restart fluent-bit
```

## 7. Cấu hình Fluent Bit VM gửi vào vm-logs-topic

File liên quan:

```text
yaml_conf/fluent-bit/vm-fluent-bit.conf
```

Output Kafka trên VM dùng:

```ini
[OUTPUT]
    Name              kafka
    Match             vm.dunglab.*
    Brokers           dung-my-cluster-b0.kafka.vnpost.cloud:443
    Topics            vm-logs-topic
    Format            json
    Timestamp_Key     @timestamp
    Timestamp_Format  iso8601
    Retry_Limit       False
    rdkafka.client.id fluent-bit-simple-vm
    rdkafka.security.protocol ssl
    rdkafka.ssl.ca.location /etc/fluent-bit/kafka-ca.crt
    rdkafka.request.required.acks 1
    storage.total_limit_size 50MB
```

Ý nghĩa:

- Log external từ VM bị ép đi vào `vm-logs-topic`.
- Không dùng topic cũ của log nội bộ k8s.
- Dùng TLS qua port `443`.
- CA file bắt buộc phải tồn tại trên VM.

## 8. RBAC đã tạo cho Strimzi riêng

Khi thêm external listener kiểu NodePort, Strimzi operator cần quyền cluster-scoped nhất định.

Đã tạo RBAC chỉ bind vào service account của namespace `kafka-dung`.

File:

```text
yaml_conf/kafka/strimzi-kafka-dung-global-rbac.yaml
yaml_conf/kafka/strimzi-kafka-dung-node-rbac.yaml
```

Các binding:

```text
strimzi-cluster-operator-kafka-dung-global
strimzi-kafka-dung-node-access-binding
```

Service account được bind:

```text
kafka-dung:strimzi-cluster-operator
```

Không bind vào service account của namespace `kafka`.

Kiểm tra quyền:

```powershell
kubectl auth can-i get nodes --as=system:serviceaccount:kafka-dung:strimzi-cluster-operator
```

Kết quả đúng:

```text
yes
```

## 9. Lỗi đã gặp: Strimzi thiếu quyền get nodes

Khi apply Kafka external listener, Strimzi cần đọc thông tin node để reconcile NodePort listener.

Triệu chứng:

```text
forbidden: User "system:serviceaccount:kafka-dung:strimzi-cluster-operator" cannot get resource "nodes"
```

Cách xử lý:

Tạo `ClusterRole` cho quyền:

```yaml
resources:
  - nodes
verbs:
  - get
  - list
```

và bind vào:

```text
kafka-dung:strimzi-cluster-operator
```

File xử lý:

```text
yaml_conf/kafka/strimzi-kafka-dung-node-rbac.yaml
```

## 10. Lỗi đã gặp: /tmp của Strimzi operator bị đầy

Sau khi có quyền, Strimzi vẫn reconcile lỗi vì `/tmp` trong pod operator bị quá nhỏ.

Triệu chứng:

```text
No space left on device
```

Nguyên nhân quan sát được:

- Pod `strimzi-cluster-operator` trong namespace `kafka-dung` có `/tmp` 1MiB.
- File agent trong `/tmp` chiếm gần hết dung lượng.
- Khi Strimzi generate cert hoặc xử lý TLS listener thì thiếu chỗ ghi tạm.

Cách xử lý:

Patch deployment `strimzi-cluster-operator` trong namespace `kafka-dung` để mount `/tmp` bằng `emptyDir` memory 64Mi.

Ghi chú nằm ở:

```text
yaml_conf/kafka/strimzi-dung-operator-tmp-patch.md
```

Lệnh đã dùng dạng:

```powershell
kubectl patch deploy strimzi-cluster-operator -n kafka-dung --type=merge --patch-file <patch-file>
kubectl rollout status deploy/strimzi-cluster-operator -n kafka-dung
```

Lưu ý: chỉ patch operator trong `kafka-dung`, không patch operator của người khác.

## 11. Kiểm tra sau khi apply

Kiểm tra Kafka:

```powershell
kubectl get kafka my-cluster -n kafka-dung
kubectl get pods -n kafka-dung
kubectl get svc -n kafka-dung
```

Kỳ vọng:

```text
my-cluster Ready=True
my-cluster-combined-external2-0
```

Kiểm tra TransportServer:

```powershell
kubectl get transportserver -n kafka-dung
```

Kỳ vọng:

```text
my-cluster-kafka-broker-0-ts    Valid
```

Kiểm tra topic:

```powershell
kubectl get kafkatopic -n kafka-dung
```

Kỳ vọng:

```text
vm-logs-topic   True
```

## 12. Kiểm tra từ VM

Kiểm tra port 443 tới broker domain, dùng làm bootstrap cho Fluent Bit:

```bash
nc -vz dung-my-cluster-b0.kafka.vnpost.cloud 443
```

Kiểm tra TLS:

```bash
openssl s_client \
  -connect dung-my-cluster-b0.kafka.vnpost.cloud:443 \
  -servername dung-my-cluster-b0.kafka.vnpost.cloud \
  -CAfile /etc/fluent-bit/kafka-ca.crt
```

Restart Fluent Bit:

```bash
sudo systemctl restart fluent-bit
sudo journalctl -u fluent-bit -f
```

Nếu thấy lỗi thiếu CA:

```text
/etc/fluent-bit/kafka-ca.crt not found
```

thì copy lại CA:

```bash
sudo cp /opt/bocao-gitops/yaml_conf/kafka/my-cluster-ca.crt /etc/fluent-bit/kafka-ca.crt
sudo systemctl restart fluent-bit
```

## 13. Kiểm tra log đã vào Kafka chưa

Consume topic từ trong Kafka pod:

```powershell
kubectl exec -n kafka-dung my-cluster-combined-0 -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic vm-logs-topic --from-beginning --timeout-ms 10000
```

Nếu có log JSON từ 4 app VM thì đường external đã hoạt động.

Các field nên thấy:

```json
{
  "service": "frontend",
  "log_source": "vm-dung-lab",
  "log_scope": "external",
  "vm_name": "simple-vm"
}
```

## 14. Các lệnh apply tổng hợp

Chạy từ thư mục repo:

```powershell
kubectl apply -f .\yaml_conf\kafka\strimzi-kafka-dung-global-rbac.yaml
kubectl apply -f .\yaml_conf\kafka\strimzi-kafka-dung-node-rbac.yaml
kubectl apply -n kafka-dung -f .\yaml_conf\kafka\Kafka_Official_K8s_Config.yaml
kubectl apply -n kafka-dung -f .\yaml_conf\kafka\my-topic.yaml
kubectl apply -f .\yaml_conf\kafka\my-cluster-nginx-transportservers.yaml
```

Nếu Strimzi operator trong `kafka-dung` lại gặp lỗi `/tmp`:

```powershell
kubectl patch deploy strimzi-cluster-operator -n kafka-dung --type=merge --patch-file <patch-file>
kubectl rollout status deploy/strimzi-cluster-operator -n kafka-dung
```

## 15. Ranh giới tài nguyên không được đụng

Không apply, patch, delete các tài nguyên sau nếu không có chủ sở hữu xác nhận:

```text
namespace kafka
Kafka global-shared-1
TransportServer global-shared-1-*
Ingress/NGINX global config của người khác
Strimzi operator/service account của namespace kafka
```

Chỉ dùng chúng để đọc tham khảo khi cần học mô hình route.
