# Tài Liệu Cài Đặt Và Triển Khai Hệ Thống Logging


## 1. Chuẩn bị môi trường

Cần có các công cụ sau trên máy quản trị:

```bash
kubectl version
helm version
```

Kiểm tra đã kết nối được vào Kubernetes cluster:

```bash
kubectl get nodes
kubectl get namespaces
```

Cập nhật repo Helm của Elastic:

```bash
helm repo add elastic https://helm.elastic.co
helm repo update
```

Kiểm tra chart Elastic:

```bash
helm search repo elastic/elasticsearch
helm search repo elastic/kibana
helm search repo elastic/logstash
```

## 2. Tạo namespace

Namespace lab ứng dụng:

```bash
kubectl apply -f yaml_conf/namespaces/namespace.yaml
```

Kiểm tra:

```bash
kubectl get ns
```

Các namespace chính đang dùng:

```text
dung-lab     Chạy các pod sinh log giả lập
elk-dung     Chạy Elasticsearch, Kibana, Logstash, ElastAlert
kafka-dung   Chạy Kafka riêng bằng Strimzi
```

## 3. Triển khai Elasticsearch

Cài hoặc cập nhật Elasticsearch bằng Helm:

```bash
helm upgrade --install elasticsearch-dung elastic/elasticsearch -n elk-dung -f yaml_conf/elasticsearch/es-dung-values.yaml
```

Dựa trên thức gốc : 
```bash
helm upgrade --install <tên-release-tự-đặt> <repo>/<tên-chart> -n <namespace> -f <file-values.yaml>
```


Theo dõi StatefulSet:

```bash
kubectl rollout status statefulset/elasticsearch-master -n elk-dung --timeout=180s
```

Kiểm tra pod, service, PVC:

```bash
kubectl get pods -n elk-dung | grep elasticsearch
kubectl get svc -n elk-dung | grep elasticsearch
kubectl get pvc -n elk-dung | grep elasticsearch
```

Kiểm tra Helm release:

```bash
helm list -n elk-dung
helm status elasticsearch-dung -n elk-dung
```

## 4. Triển khai Ingress cho Elasticsearch

Apply Ingress:

```bash
kubectl apply -f yaml_conf/elasticsearch/elasticsearch-dung-ingress.yaml
```

Kiểm tra:

```bash
kubectl get ingress -n elk-dung
kubectl describe ingress elasticsearch-dung -n elk-dung
```

Ingress này dùng để mở đường truy cập Elasticsearch qua domain bên ngoài.

## 5. Triển khai Kibana

Cài hoặc cập nhật Kibana bằng Helm:

```bash
helm upgrade --install kibana-dung elastic/kibana -n elk-dung -f yaml_conf/elasticsearch/kibana-logging-values.yaml
```

Theo dõi Deployment:

```bash
kubectl rollout status deployment/kibana-dung-kibana -n elk-dung --timeout=180s
```

Kiểm tra:

```bash
kubectl get pods -n elk-dung | grep kibana
kubectl get svc -n elk-dung | grep kibana
helm status kibana-dung -n elk-dung
```

## 6. Triển khai Ingress cho Kibana

Apply Ingress:

```bash
kubectl apply -f yaml_conf/elasticsearch/kibana-dung-ingress.yaml
```

Kiểm tra:

```bash
kubectl get ingress -n elk-dung
kubectl describe ingress kibana-dung -n elk-dung
```

## 7. Triển khai Logstash trên Kubernetes bằng Helm

Nếu Logstash cần đọc Kubernetes events, apply RBAC trước:

```bash
kubectl apply -f yaml_conf/logstash/logstash-k8s-events-rbac.yaml
```

Cài hoặc cập nhật Logstash:

```bash
helm upgrade --install logstash-dung elastic/logstash -n elk-dung -f yaml_conf/logstash/logstash-values0.yaml
```

Nếu đang dùng file cấu hình khác, thay phần `-f` bằng file tương ứng:

```bash
helm upgrade --install logstash-dung elastic/logstash -n elk-dung -f yaml_conf/logstash/logstash-values1.yaml
helm upgrade --install logstash-dung elastic/logstash -n elk-dung -f yaml_conf/logstash/logstash-values2.yaml
```

Theo dõi rollout:

```bash
kubectl rollout status statefulset/logstash-dung-logstash -n elk-dung --timeout=180s
```

Kiểm tra:

```bash
kubectl get pods -n elk-dung | grep logstash
kubectl logs -n elk-dung logstash-dung-logstash-0 --tail=100
helm status logstash-dung -n elk-dung
```

## 8. Triển khai Fluent Bit trên Kubernetes

Triển khai Fluent Bit bằng Helm values trong thư mục `fluent-bit`:

```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update
```

Ví dụ triển khai Fluent Bit đẩy log về Kafka:

```bash
helm upgrade --install fluent-bit-dung fluent/fluent-bit -n elk-dung -f yaml_conf/fluent-bit/fluent-bit-dung-lab-to-kafka-values.yaml
```

Nếu dùng file values khác:

```bash
helm upgrade --install fluent-bit-dung fluent/fluent-bit -n elk-dung -f yaml_conf/fluent-bit/fluent-bit-values.yaml
```

Kiểm tra:

```bash
kubectl get pods -n elk-dung | grep fluent
kubectl logs -n elk-dung -l app.kubernetes.io/name=fluent-bit --tail=100
```

## 9. Triển khai các pod sinh log trong Kubernetes

Apply ConfigMap script trước:

```bash
kubectl apply -f yaml_conf/log-generators/configmap-log-scripts.yaml
```

Apply các Deployment sinh log:

```bash
kubectl apply -f yaml_conf/log-generators/deploy-fe.yaml
kubectl apply -f yaml_conf/log-generators/deploy-be.yaml
kubectl apply -f yaml_conf/log-generators/deploy-db.yaml
kubectl apply -f yaml_conf/log-generators/deploy-web.yaml
```

Kiểm tra:

```bash
kubectl get pods -n dung-lab
kubectl logs -n dung-lab deployment/dung-fe-log-generator --tail=50
kubectl logs -n dung-lab deployment/dung-be-log-generator --tail=50
kubectl logs -n dung-lab deployment/dung-db-log-generator --tail=50
kubectl logs -n dung-lab deployment/dung-web-log-generator --tail=50
```

## 10. Triển khai Kafka bằng Strimzi

Apply RBAC nếu cụm yêu cầu quyền bổ sung cho Strimzi trong namespace riêng:

```bash
kubectl apply -f yaml_conf/kafka/strimzi-kafka-dung-global-rbac.yaml
kubectl apply -f yaml_conf/kafka/strimzi-kafka-dung-node-rbac.yaml
```

Cài Strimzi operator bằng Helm:

```bash
helm repo add strimzi https://strimzi.io/charts/
helm repo update
helm upgrade --install strimzi-dung strimzi/strimzi-kafka-operator -n kafka-dung --create-namespace
```

Apply Kafka cluster:

```bash
kubectl apply -f yaml_conf/kafka/Kafka_Official_K8s_Config.yaml
```

Apply Kafka topic:

```bash
kubectl apply -f yaml_conf/kafka/my-topic.yaml
```

Apply TransportServer để mở Kafka ra ngoài qua NGINX Ingress:

```bash
kubectl apply -f yaml_conf/kafka/my-cluster-nginx-transportservers.yaml
```

Kiểm tra Kafka:

```bash
kubectl get kafka,kafkatopic -n kafka-dung
kubectl get pods -n kafka-dung
kubectl get svc -n kafka-dung
kubectl get transportserver -n kafka-dung
```

Xuất CA certificate cho VM nếu cần client ngoài cluster kết nối Kafka:

```powershell
powershell -ExecutionPolicy Bypass -File yaml_conf/kafka/export-my-cluster-ca-for-vm.ps1
```

## 11. Triển khai ElastAlert

Apply ConfigMap cấu hình:

```bash
kubectl apply -f yaml_conf/elastalert/elastalert-configmap.yaml
```

Apply ConfigMap rule:

```bash
kubectl apply -f yaml_conf/elastalert/elastalert-rules-configmap.yaml
```

Apply Deployment:

```bash
kubectl apply -f yaml_conf/elastalert/elastalert-deployment.yaml
```

Kiểm tra:

```bash
kubectl get pods -n elk-dung | grep elastalert
kubectl logs -n elk-dung deployment/elastalert2 --tail=100
```

## 12. Cài GitOps puller trên VM

Trên VM Ubuntu, clone repo:

```bash
sudo apt-get update
sudo apt-get install -y git
sudo git clone https://github.com/caotuandungg/BaoCao.git /opt/bocao-gitops
```

Cài GitOps puller:

```bash
cd /opt/bocao-gitops
sudo bash yaml_conf/vm-gitops/install-gitops-puller.sh
```

Chạy reconcile thủ công:

```bash
sudo systemctl start bocao-vm-gitops.service
```

Kiểm tra timer và log:

```bash
systemctl status bocao-vm-gitops.timer
systemctl list-timers bocao-vm-gitops.timer
journalctl -u bocao-vm-gitops.service -f
```

## 13. Cài các log generator trên VM

Nếu làm thủ công trên VM:

```bash
cd /opt/bocao-gitops
sudo bash yaml_conf/vm-log-generators/install-vm-log-generators.sh
```

Kiểm tra service:

```bash
systemctl status dung-fe-log-generator
systemctl status dung-be-log-generator
systemctl status dung-db-log-generator
systemctl status dung-web-log-generator
```

Xem log sinh ra:

```bash
tail -f /var/log/dung-lab/fe.log
tail -f /var/log/dung-lab/be.log
tail -f /var/log/dung-lab/db.log
tail -f /var/log/dung-lab/web.log
```

## 14. Cài app NestJS sinh log trên VM

Có thể làm theo hướng dẫn chi tiết:

```text
yaml_conf/vm-nestjs-log-app/manual-install-vm-nestjs-log-app.md
```

Nếu dùng script cài tự động:

```bash
cd /opt/bocao-gitops
sudo bash yaml_conf/vm-nestjs-log-app/install-vm-nestjs-log-app.sh
```

Kiểm tra app:

```bash
systemctl status dung-nestjs-log-app
journalctl -u dung-nestjs-log-app -f
tail -f /var/log/dung-lab/nestjs.log
```

## 15. Cài Logstash trực tiếp trên VM

Có thể làm theo hướng dẫn chi tiết:

```text
yaml_conf/vm-logstash/manual-install-vm-logstash.md
```

Nếu dùng script cài tự động:

```bash
cd /opt/bocao-gitops
sudo bash yaml_conf/vm-logstash/install-vm-logstash.sh
```

Kiểm tra Logstash trên VM:

```bash
sudo systemctl status logstash
sudo journalctl -u logstash -f
```

Kiểm tra file pipeline đang chạy:

```bash
sudo cat /etc/logstash/conf.d/dung-vm-logstash.conf
```

Kiểm tra cấu hình trước khi restart:

```bash
sudo runuser -u logstash -- /usr/share/logstash/bin/logstash --path.settings /etc/logstash --config.test_and_exit
```

## 16. Logging Kit cho đối tác hoặc nguồn log mới

Thư mục `logging-kit` dùng để bàn giao format log và config mẫu cho bên tích hợp.

Kiểm tra schema:

```powershell
powershell -ExecutionPolicy Bypass -File yaml_conf/logging-kit/tests/validate-log-schema.ps1
```

Các tài liệu chính:

```text
yaml_conf/logging-kit/README.md
yaml_conf/logging-kit/schema/log-schema-v1.md
yaml_conf/logging-kit/schema/log-schema-v1.schema.json
```

Các agent mẫu:

```text
yaml_conf/logging-kit/agents/fluent-bit
yaml_conf/logging-kit/agents/filebeat
yaml_conf/logging-kit/agents/vector
yaml_conf/logging-kit/agents/logstash
```

## 17. Kiểm tra tổng thể sau khi triển khai

Kiểm tra Helm release:

```bash
helm list -A
helm list -n elk-dung
```

Kiểm tra tài nguyên trong namespace logging:

```bash
kubectl get all -n elk-dung
kubectl get ingress -n elk-dung
kubectl get pvc -n elk-dung
```

Kiểm tra app sinh log:

```bash
kubectl get pods -n dung-lab
kubectl logs -n dung-lab deployment/dung-fe-log-generator --tail=20
```

Kiểm tra Kafka:

```bash
kubectl get kafka,kafkatopic -n kafka-dung
kubectl get pods -n kafka-dung
```

Kiểm tra Elasticsearch có nhận dữ liệu:

```bash
kubectl exec -n elk-dung elasticsearch-master-0 -- curl -sk -u elastic:<PASSWORD> https://localhost:9200/_cat/indices?v
```

## 18. Apply lại khi thay đổi cấu hình

Nếu thay đổi file Helm values của Elasticsearch:

```bash
helm upgrade elasticsearch-dung elastic/elasticsearch -n elk-dung -f yaml_conf/elasticsearch/es-dung-values.yaml
```

Nếu thay đổi file Helm values của Kibana:

```bash
helm upgrade kibana-dung elastic/kibana -n elk-dung -f yaml_conf/elasticsearch/kibana-logging-values.yaml
```

Nếu thay đổi file Helm values của Logstash:

```bash
helm upgrade logstash-dung elastic/logstash -n elk-dung -f yaml_conf/logstash/logstash-values0.yaml
kubectl rollout status statefulset/logstash-dung-logstash -n elk-dung --timeout=180s
```

Nếu thay đổi YAML thuần Kubernetes:

```bash
kubectl apply -f <duong-dan-file-yaml>
```

Nếu thay đổi cấu hình VM và dùng GitOps:

```bash
cd /opt/bocao-gitops
sudo git pull
sudo systemctl start bocao-vm-gitops.service
```

## 19. Rollback khi Helm upgrade lỗi

Xem lịch sử release:

```bash
helm history <release-name> -n <namespace>
```

Rollback về revision cũ:

```bash
helm rollback <release-name> <revision> -n <namespace>
```

Ví dụ:

```bash
helm rollback logstash-dung 76 -n elk-dung
```

Kiểm tra lại:

```bash
helm status <release-name> -n <namespace>
kubectl get pods -n <namespace>
```

## 20. Thứ tự triển khai 

Thứ tự triển khai từ đầu:

```text
1. Cài kubectl, Helm và kết nối cluster
2. Tạo namespace
3. Cài Elasticsearch
4. Cài Kibana
5. Apply Ingress cho Elasticsearch và Kibana
6. Cài Kafka bằng Strimzi nếu dùng pipeline qua Kafka
7. Cài Fluent Bit nếu cần thu log từ Kubernetes
8. Cài Logstash Kubernetes bằng Helm
9. Apply các pod sinh log trong dung-lab
10. Cài ElastAlert nếu cần cảnh báo
11. Cài GitOps puller trên VM nếu muốn VM tự cập nhật
12. Cài log generator, NestJS app, VM Logstash trên VM
13. Kiểm tra log vào Elasticsearch và hiển thị trên Kibana
```



helm upgrade elasticsearch-dung elastic/elasticsearch -n elk-dung -f yaml_conf/elasticsearch/es-dung-values.yaml --force-conflicts --wait=watcher --timeout 5m