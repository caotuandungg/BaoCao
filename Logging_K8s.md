# Nghiên Cứu: Xây Dựng Hệ Thống Log + Log Search Tập Trung Trên Kubernetes

> **Người thực hiện:** Dũng  
> **Ngày:** 31/03/2026  
> **Mục tiêu:** Tìm hiểu kiến trúc, công nghệ và cách triển khai hệ thống logging tập trung trên Kubernetes

---

## Mục Lục

1. [Tại sao cần hệ thống Log tập trung trên K8s?](#1-tại-sao-cần-hệ-thống-log-tập-trung-trên-k8s)
2. [Kiến trúc Logging trong Kubernetes (Tài liệu chính thức)](#2-kiến-trúc-logging-trong-kubernetes)
3. [Các mô hình thu thập Log trên K8s](#3-các-mô-hình-thu-thập-log-trên-k8s)
4. [Các giải pháp Logging Stack phổ biến](#4-các-giải-pháp-logging-stack-phổ-biến)
5. [So sánh chi tiết: EFK Stack vs PLG Stack (Loki)](#5-so-sánh-chi-tiết-efk-stack-vs-plg-stack)
6. [Phương án đề xuất: PLG Stack (Promtail + Loki + Grafana)](#6-phương-án-đề-xuất-plg-stack)
7. [Phương án thay thế: EFK Stack](#7-phương-án-thay-thế-efk-stack)
8. [Best Practices cho Production](#8-best-practices-cho-production)
9. [Tài liệu tham khảo chính thức](#9-tài-liệu-tham-khảo-chính-thức)

---

## 1. Tại Sao Cần Hệ Thống Log Tập Trung Trên K8s?

### 1.1 Vấn đề với logging mặc định của Kubernetes

Theo tài liệu chính thức của Kubernetes ([Logging Architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/)):

> *"Application logs can help you understand what is happening inside your application. The logs are particularly useful for debugging problems and monitoring cluster activity... However, the native functionality provided by a container engine or runtime is usually not enough for a complete logging solution."*

Kubernetes mặc định chỉ cung cấp khả năng xem log cơ bản thông qua `kubectl logs`. Tuy nhiên, điều này **không đủ** cho môi trường production vì:

| Vấn đề | Giải thích |
|---------|-----------|
| **Pod là ephemeral (tạm thời)** | Khi Pod bị xóa/restart, toàn bộ log sẽ **mất vĩnh viễn** |
| **Không tìm kiếm được** | `kubectl logs` không hỗ trợ full-text search, filter nâng cao |
| **Phân tán** | Log nằm rải rác trên từng Node, không có cái nhìn tổng quan |
| **Không có correlation** | Không thể liên kết log từ nhiều service/pod liên quan |
| **Không có alerting** | Không thể tự động cảnh báo khi phát hiện pattern lỗi |
| **Log rotation** | Container runtime có giới hạn log rotation, dễ mất log cũ |

### 1.2 Mục tiêu của hệ thống Log tập trung

```
┌─────────────────────────────────────────────────────┐
│              HỆ THỐNG LOG TẬP TRUNG                 │
│                                                     │
│  ✅ Thu thập log từ TẤT CẢ pods/containers          │
│  ✅ Lưu trữ lâu dài, không mất khi Pod bị xóa      │
│  ✅ Tìm kiếm full-text nhanh chóng                  │
│  ✅ Lọc theo namespace, pod, container, label       │
│  ✅ Trực quan hóa bằng dashboard                    │
│  ✅ Cảnh báo tự động khi phát hiện lỗi              │
│  ✅ Tương quan log giữa các microservices            │
└─────────────────────────────────────────────────────┘
```

---

## 2. Kiến Trúc Logging Trong Kubernetes

### 2.1 Cách Kubernetes xử lý Log (Tài liệu chính thức)

Theo [kubernetes.io/docs/concepts/cluster-administration/logging](https://kubernetes.io/docs/concepts/cluster-administration/logging/):

Kubernetes xử lý log container theo quy trình sau:

```
┌──────────────────────────────────────────────────────────────┐
│                        KUBERNETES NODE                       │
│                                                              │
│  ┌──────────────┐                                            │
│  │  Container    │──── stdout/stderr ────┐                   │
│  │  (App)        │                       │                   │
│  └──────────────┘                        ▼                   │
│                                  ┌──────────────────┐        │
│                                  │  Container       │        │
│                                  │  Runtime         │        │
│                                  │  (containerd)    │        │
│                                  └────────┬─────────┘        │
│                                           │                  │
│                                           ▼                  │
│                                  /var/log/pods/              │
│                                  /var/log/containers/        │
│                                  (JSON log files)            │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Chi tiết:**
1. **Application** ghi log ra `stdout` và `stderr`
2. **Container Runtime** (containerd) bắt các stream này
3. Ghi log vào file trên Node tại `/var/log/pods/<namespace>_<pod-name>_<pod-uid>/<container-name>/`
4. Kubernetes tự động thực hiện **log rotation** khi file đạt kích thước giới hạn (mặc định `10MB`, giữ tối đa `5 file`)

### 2.2 Cluster-level Logging Architecture

Kubernetes chính thức mô tả **3 phương pháp** để triển khai cluster-level logging:

```
┌───────────────────────────────────────────────────────────────────┐
│                 CLUSTER-LEVEL LOGGING OPTIONS                     │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Option 1: Node-level Logging Agent (DaemonSet)    ⭐ KHUYÊN  │  │
│  │                                                    DÙNG     │  │
│  │  • Chạy agent trên MỖI Node dưới dạng DaemonSet            │  │
│  │  • Agent đọc log files từ /var/log/pods/                    │  │
│  │  • Gửi đến backend tập trung                               │  │
│  │  • Ví dụ: Fluent Bit, Fluentd, Vector                      │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Option 2: Sidecar Container                                 │  │
│  │                                                              │  │
│  │  • Container phụ chạy cùng Pod                              │  │
│  │  • Dùng khi app KHÔNG ghi ra stdout/stderr                 │  │
│  │  • Chia làm 2 loại:                                        │  │
│  │    - Streaming sidecar: đọc file → ghi ra stdout           │  │
│  │    - Agent sidecar: đọc file → gửi thẳng đến backend       │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Option 3: Push trực tiếp từ Application                     │  │
│  │                                                              │  │
│  │  • Application tự gửi log đến backend                       │  │
│  │  • Không khuyến khích vì coupling cao                       │  │
│  └─────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
```

---

## 3. Các Mô Hình Thu Thập Log Trên K8s

### 3.1 Node-level Logging Agent (⭐ Khuyên dùng)

Đây là phương pháp **được khuyến nghị nhất** bởi Kubernetes và cộng đồng CNCF.

```
 Node 1                          Node 2                        Node 3
┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
│ ┌─────┐ ┌─────┐ │        │ ┌─────┐ ┌─────┐ │        │ ┌─────┐ ┌─────┐ │
│ │Pod A│ │Pod B│ │        │ │Pod C│ │Pod D│ │        │ │Pod E│ │Pod F│ │
│ └──┬──┘ └──┬──┘ │        │ └──┬──┘ └──┬──┘ │        │ └──┬──┘ └──┬──┘ │
│    │       │    │        │    │       │    │        │    │       │    │
│    ▼       ▼    │        │    ▼       ▼    │        │    ▼       ▼    │
│ /var/log/pods/  │        │ /var/log/pods/  │        │ /var/log/pods/  │
│    │            │        │    │            │        │    │            │
│    ▼            │        │    ▼            │        │    ▼            │
│ ┌────────────┐  │        │ ┌────────────┐  │        │ ┌────────────┐  │
│ │ Fluent Bit │  │        │ │ Fluent Bit │  │        │ │ Fluent Bit │  │
│ │ (DaemonSet)│  │        │ │ (DaemonSet)│  │        │ │ (DaemonSet)│  │
│ └─────┬──────┘  │        │ └─────┬──────┘  │        │ └─────┬──────┘  │
└───────┼─────────┘        └───────┼─────────┘        └───────┼─────────┘
        │                          │                          │
        └──────────────┬───────────┘──────────────────────────┘
                       │
                       ▼
            ┌──────────────────┐
            │  Log Backend     │
            │  (Elasticsearch  │
            │   hoặc Loki)     │
            └──────────────────┘
```

**Ưu điểm:**
- Chỉ cần 1 agent per node, tiết kiệm tài nguyên
- Tự động thu thập log từ TẤT CẢ pods trên node
- Không cần sửa đổi application code
- Tự động bổ sung metadata (namespace, pod name, labels)

### 3.2 Sidecar Container Pattern

```
┌─────────────────────────────────────┐
│              POD                     │
│                                     │
│  ┌──────────────┐  ┌─────────────┐  │
│  │  Main App    │  │  Sidecar    │  │
│  │              │  │  (Log Agent)│  │
│  │  Ghi log     │  │             │  │
│  │  vào file    │──│  Đọc file   │  │
│  │  /var/log/   │  │  → gửi đi   │  │
│  │  app.log     │  │             │  │
│  └──────────────┘  └─────────────┘  │
│         │               │            │
│         └───── shared ──┘            │
│              emptyDir                │
└─────────────────────────────────────┘
```

**Khi nào dùng:**
- App legacy không thể ghi ra stdout/stderr
- Cần xử lý/biến đổi log phức tạp riêng cho từng app
- Cần tách các luồng log khác nhau trong cùng 1 Pod

---

## 4. Các Giải Pháp Logging Stack Phổ Biến

### 4.1 Tổng quan các Stack

```
┌───────────────────────────────────────────────────────────────────────┐
│                    LOGGING STACK COMPARISON                           │
├───────────────┬─────────────────────┬─────────────────────────────────┤
│               │     EFK Stack       │     PLG Stack (Loki)            │
├───────────────┼─────────────────────┼─────────────────────────────────┤
│  Thu thập     │  Fluentd/Fluent Bit │  Promtail/Grafana Alloy/        │
│  (Collector)  │                     │  Fluent Bit                     │
├───────────────┼─────────────────────┼─────────────────────────────────┤
│  Lưu trữ     │  Elasticsearch      │  Grafana Loki                   │
│  (Storage)    │                     │                                 │
├───────────────┼─────────────────────┼─────────────────────────────────┤
│  Trực quan    │  Kibana             │  Grafana                        │
│  (UI)         │                     │                                 │
├───────────────┼─────────────────────┼─────────────────────────────────┤
│  Indexing     │  Full-text index    │  Chỉ index metadata/labels      │
├───────────────┼─────────────────────┼─────────────────────────────────┤
│  Tài nguyên   │  CAO (RAM/CPU/Disk) │  THẤP                          │
├───────────────┼─────────────────────┼─────────────────────────────────┤
│  Chi phí      │  Cao                │  Thấp                           │
│  lưu trữ      │                     │                                 │
├───────────────┼─────────────────────┼─────────────────────────────────┤
│  CNCF Status  │  Fluentd: Graduated │  Không (Grafana Labs)           │
│               │  ES: Elastic NV     │  Open Source (AGPL-3.0)         │
├───────────────┼─────────────────────┼─────────────────────────────────┤
│  Phù hợp     │  Enterprise,        │  DevOps, Cloud-native,          │
│               │  Security/Compliance│  đã dùng Prometheus+Grafana     │
└───────────────┴─────────────────────┴─────────────────────────────────┘
```

---

## 5. So Sánh Chi Tiết: EFK Stack vs PLG Stack

### 5.1 EFK Stack (Elasticsearch + Fluentd/Fluent Bit + Kibana)

**Kiến trúc:**

```
┌──────────────────────────────────────────────────────────────────┐
│                        EFK STACK                                 │
│                                                                  │
│  ┌──────────┐     ┌───────────┐     ┌──────────────┐            │
│  │ Fluent   │     │           │     │              │            │
│  │ Bit      │────▶│Elasticsearch────▶│   Kibana     │            │
│  │(DaemonSet│     │ (StatefulSet)   │ (Deployment) │            │
│  │ mỗi Node)│     │           │     │              │            │
│  └──────────┘     └───────────┘     └──────────────┘            │
│                        │                                         │
│                   PersistentVolume                                │
│                   (Lưu trữ index)                                │
└──────────────────────────────────────────────────────────────────┘
```

**Thành phần chi tiết:**

| Thành phần | Vai trò | Triển khai trên K8s | Tài liệu chính thức |
|-----------|---------|--------------------|--------------------|
| **Elasticsearch** | Search engine + lưu trữ. Index toàn bộ nội dung log dạng full-text | `StatefulSet` với `PersistentVolumeClaim` | [elastic.co/guide](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html) |
| **Fluent Bit** | Thu thập log nhẹ, viết bằng C | `DaemonSet` trên mỗi Node | [docs.fluentbit.io](https://docs.fluentbit.io/) |
| **Fluentd** | Thu thập + xử lý log nặng hơn, viết bằng Ruby, plugin phong phú | `DaemonSet` hoặc `Deployment` (aggregator) | [docs.fluentd.org](https://docs.fluentd.org/) |
| **Kibana** | Giao diện web trực quan, tìm kiếm, dashboard | `Deployment` + `Service` | [elastic.co/kibana](https://www.elastic.co/guide/en/kibana/current/index.html) |

**ECK Operator (Elastic Cloud on Kubernetes):**

Elastic cung cấp operator chính thức để triển khai trên K8s:
> Nguồn: [elastic.co/guide/en/cloud-on-k8s](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)

```bash
# Cài đặt ECK Operator
kubectl apply -f https://download.elastic.co/downloads/eck/<version>/crds.yaml
kubectl apply -f https://download.elastic.co/downloads/eck/<version>/operator.yaml
```

```yaml
# Ví dụ: Tạo Elasticsearch cluster bằng ECK
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: logging-cluster
  namespace: logging
spec:
  version: 8.x.x
  nodeSets:
  - name: default
    count: 3
    config:
      node.store.allow_mmap: false
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 50Gi
        storageClassName: standard
```

### 5.2 PLG Stack (Promtail/Alloy + Loki + Grafana)

**Kiến trúc:**

Theo tài liệu chính thức Grafana Loki ([grafana.com/docs/loki/latest/get-started/overview](https://grafana.com/docs/loki/latest/get-started/overview/)):

> *"Loki is a horizontally scalable, highly available, multi-tenant log aggregation system inspired by Prometheus."*

```
┌───────────────────────────────────────────────────────────────────┐
│                         PLG STACK                                 │
│                                                                   │
│  ┌──────────┐     ┌───────────────────────────┐     ┌──────────┐ │
│  │ Promtail │     │        Grafana Loki        │     │          │ │
│  │ / Alloy  │────▶│                           │────▶│ Grafana  │ │
│  │(DaemonSet│     │ ┌───────────┐ ┌─────────┐ │     │    UI    │ │
│  │ mỗi Node)│     │ │Distributor│ │ Ingester│ │     │          │ │
│  └──────────┘     │ └───────────┘ └────┬────┘ │     └──────────┘ │
│                   │                    │      │                   │
│                   │  ┌─────────────┐   │      │                   │
│                   │  │Query Frontend│   │      │                   │
│                   │  └──────┬──────┘   │      │                   │
│                   │         │          │      │                   │
│                   │  ┌──────▼──────┐   │      │                   │
│                   │  │   Querier   │◀──┘      │                   │
│                   │  └─────────────┘          │                   │
│                   └───────────┬────────────────┘                   │
│                               │                                   │
│                        Object Storage                              │
│                    (S3/GCS/MinIO/Filesystem)                       │
└───────────────────────────────────────────────────────────────────┘
```

**Điểm khác biệt cốt lõi của Loki:**

```
┌──────────────────────────────────────────────────────────────┐
│            ELASTICSEARCH vs LOKI: INDEXING STRATEGY           │
│                                                              │
│  Elasticsearch:                                              │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Log Line: "2024-03-31 ERROR  Connection timeout to DB"  │ │
│  │                                                         │ │
│  │ Index: "2024" → doc1                                    │ │
│  │        "03"   → doc1                                    │ │
│  │        "31"   → doc1                                    │ │
│  │        "ERROR" → doc1                                   │ │
│  │        "Connection" → doc1                              │ │
│  │        "timeout" → doc1                                 │ │
│  │        "DB" → doc1                                      │ │
│  │                                                         │ │
│  │ → Index MỌI từ → Tốn RAM/Disk → Search CỰC NHANH      │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  Loki:                                                       │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Log Line: "2024-03-31 ERROR  Connection timeout to DB"  │ │
│  │                                                         │ │
│  │ Labels (Index): {job="myapp", namespace="production",   │ │
│  │                  pod="myapp-abc123"}                     │ │
│  │                                                         │ │
│  │ Content: Nén & lưu nguyên, KHÔNG index nội dung         │ │
│  │                                                         │ │
│  │ → Chỉ index labels → Tiết kiệm → Search theo labels    │ │
│  │   rồi grep trong chunks                                │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

**Các component của Loki:**

Theo [grafana.com/docs/loki/latest/get-started/components](https://grafana.com/docs/loki/latest/get-started/components/):

| Component | Vai trò |
|-----------|---------|
| **Distributor** | Nhận log từ agent, validate, phân phối đến Ingester |
| **Ingester** | Nhận log, xây dựng chunks nén trong memory, flush xuống storage |
| **Querier** | Xử lý query LogQL, lấy data từ Ingester (recent) + Storage (historical) |
| **Query Frontend** | Nhận query từ client, chia thành sub-queries, caching |
| **Compactor** | Nén và tối ưu index trong long-term storage |

**Deployment modes trên K8s:**

Theo [grafana.com/docs/loki/latest/get-started/deployment-modes](https://grafana.com/docs/loki/latest/get-started/deployment-modes/):

| Mode | Mô tả | Phù hợp |
|------|-------|---------|
| **Monolithic** | Tất cả component trong 1 process/container | Dev/Test, quy mô nhỏ (< 100GB/ngày) |
| **Simple Scalable (SSD)** | Chia thành Read, Write, Backend targets | Production quy mô vừa |
| **Microservices** | Mỗi component là service riêng | Production quy mô lớn |

---

## 6. Phương Án Đề Xuất: PLG Stack

### 6.1 Lý do chọn PLG Stack

| Tiêu chí | Lý do |
|----------|-------|
| **Chi phí infrastructure thấp** | Loki không index full-text → ít RAM/CPU/Disk hơn Elasticsearch rất nhiều |
| **Tích hợp Prometheus+Grafana** | Nếu đã dùng Prometheus cho metrics → Grafana đã có sẵn → thêm Loki rất tự nhiên |
| **Cloud-native** | Dùng Object Storage (S3/MinIO) → chi phí lưu trữ thấp, scalable |
| **Label-based giống K8s** | Loki dùng labels giống hệt Kubernetes labels → query trực quan |
| **Dễ triển khai** | Helm chart chính thức, hoạt động tốt trên K8s |
| **LogQL** | Ngôn ngữ query tương tự PromQL, team đã quen |

### 6.2 Kiến trúc triển khai đề xuất

```
┌─────────────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                                │
│                                                                     │
│  ┌──── Namespace: monitoring ──────────────────────────────────────┐│
│  │                                                                 ││
│  │  Node 1              Node 2              Node 3                 ││
│  │  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐        ││
│  │  │  Promtail    │   │  Promtail    │   │  Promtail    │        ││
│  │  │  (DaemonSet) │   │  (DaemonSet) │   │  (DaemonSet) │        ││
│  │  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘        ││
│  │         │                  │                  │                 ││
│  │         └──────────────────┼──────────────────┘                 ││
│  │                            │                                    ││
│  │                            ▼                                    ││
│  │                  ┌──────────────────┐                            ││
│  │                  │   Grafana Loki   │                            ││
│  │                  │   (StatefulSet)  │                            ││
│  │                  │                  │                            ││
│  │                  │  Mode: Simple    │                            ││
│  │                  │  Scalable hoặc   │                            ││
│  │                  │  Monolithic      │                            ││
│  │                  └────────┬─────────┘                            ││
│  │                           │                                     ││
│  │               ┌───────────┴───────────┐                         ││
│  │               │                       │                         ││
│  │               ▼                       ▼                         ││
│  │     ┌──────────────────┐    ┌──────────────────┐                ││
│  │     │  MinIO / PV      │    │    Grafana        │                ││
│  │     │  (Object Store)  │    │    (Deployment)   │                ││
│  │     │  Lưu trữ chunks  │    │    Dashboard +    │                ││
│  │     │  + index          │    │    Log Explorer   │                ││
│  │     └──────────────────┘    └──────────────────┘                ││
│  │                                                                 ││
│  └─────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

### 6.3 Triển khai bằng Helm

Theo tài liệu chính thức Loki: [grafana.com/docs/loki/latest/setup/install/helm](https://grafana.com/docs/loki/latest/setup/install/helm/):

```bash
# Bước 1: Thêm Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Bước 2: Cài đặt Loki (Simple Scalable mode)
helm install loki grafana/loki \
  --namespace monitoring \
  --create-namespace \
  -f loki-values.yaml

# Bước 3: Cài đặt Promtail (DaemonSet collector)
helm install promtail grafana/promtail \
  --namespace monitoring \
  --set "config.clients[0].url=http://loki-gateway.monitoring.svc:3100/loki/api/v1/push"

# Bước 4: Cài đặt Grafana (nếu chưa có)
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set persistence.enabled=true
```

**Ví dụ file `loki-values.yaml`:**

```yaml
# loki-values.yaml - Cấu hình cho môi trường lab/small production
loki:
  # Chế độ auth
  auth_enabled: false
  
  # Schema config
  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: s3
        schema: v13
        index:
          prefix: loki_index_
          period: 24h

  # Storage config - dùng MinIO hoặc filesystem
  storage:
    type: s3
    s3:
      endpoint: minio.monitoring.svc:9000
      bucketnames: loki-chunks
      access_key_id: minioadmin
      secret_access_key: minioadmin
      insecure: true
      s3ForcePathStyle: true

  # Giới hạn
  limits_config:
    retention_period: 30d            # Giữ log 30 ngày
    max_query_length: 721h
    ingestion_rate_mb: 10
    ingestion_burst_size_mb: 20

# Deployment mode
deploymentMode: SimpleScalable

# Resource requests
write:
  replicas: 2
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

read:
  replicas: 2
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

backend:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

### 6.4 Sử dụng LogQL để tìm kiếm

Theo [grafana.com/docs/loki/latest/query](https://grafana.com/docs/loki/latest/query/):

```logql
# 1. Xem log của 1 namespace
{namespace="production"}

# 2. Lọc log theo pod name
{namespace="production", pod=~"nginx-.*"}

# 3. Tìm kiếm text trong log (giống grep)
{namespace="production"} |= "error"

# 4. Tìm kiếm regex
{namespace="production"} |~ "status=[45][0-9]{2}"

# 5. Parse log JSON và filter
{namespace="production"} | json | status_code >= 500

# 6. Đếm số lỗi per phút (metric from logs)
rate({namespace="production"} |= "ERROR" [1m])

# 7. Top 10 pods có nhiều error nhất
topk(10, sum by (pod) (rate({namespace="production"} |= "ERROR" [5m])))
```

---

## 7. Phương Án Thay Thế: EFK Stack

### 7.1 Khi nào nên chọn EFK thay vì PLG

| Tình huống | Giải thích |
|-----------|-----------|
| **Cần full-text search phức tạp** | Elasticsearch có engine search mạnh nhất |
| **Security/Compliance** | Cần phân tích SIEM, forensics chi tiết |
| **Dữ liệu đa dạng** | Cần index log + metrics + APM traces trong 1 hệ thống |
| **Đội ngũ đã có kinh nghiệm** | Team đã quen Elasticsearch/Kibana |
| **Enterprise features** | Cần Machine Learning, Anomaly Detection tích hợp |

### 7.2 Triển khai EFK cơ bản

```yaml
# --- Namespace ---
apiVersion: v1
kind: Namespace
metadata:
  name: logging

---
# --- Elasticsearch StatefulSet (đơn giản, 1 node) ---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: elasticsearch
  namespace: logging
spec:
  serviceName: elasticsearch
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
      - name: elasticsearch
        image: docker.elastic.co/elasticsearch/elasticsearch:8.12.0
        env:
        - name: discovery.type
          value: single-node
        - name: ES_JAVA_OPTS
          value: "-Xms512m -Xmx512m"
        - name: xpack.security.enabled
          value: "false"
        ports:
        - containerPort: 9200
          name: http
        - containerPort: 9300
          name: transport
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        volumeMounts:
        - name: data
          mountPath: /usr/share/elasticsearch/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 30Gi

---
# --- Elasticsearch Service ---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: logging
spec:
  selector:
    app: elasticsearch
  ports:
  - port: 9200
    targetPort: 9200
  type: ClusterIP

---
# --- Kibana Deployment ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
    spec:
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana:8.12.0
        env:
        - name: ELASTICSEARCH_HOSTS
          value: "http://elasticsearch.logging.svc:9200"
        ports:
        - containerPort: 5601
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"

---
# --- Kibana Service ---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: logging
spec:
  selector:
    app: kibana
  ports:
  - port: 5601
    targetPort: 5601
  type: NodePort
```

```yaml
# --- Fluent Bit DaemonSet ---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: logging
spec:
  selector:
    matchLabels:
      app: fluent-bit
  template:
    metadata:
      labels:
        app: fluent-bit
    spec:
      serviceAccountName: fluent-bit
      containers:
      - name: fluent-bit
        image: fluent/fluent-bit:latest
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: config
          mountPath: /fluent-bit/etc/
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: config
        configMap:
          name: fluent-bit-config

---
# --- Fluent Bit ConfigMap ---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: logging
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush         5
        Log_Level     info
        Daemon        off
        Parsers_File  parsers.conf

    [INPUT]
        Name              tail
        Tag               kube.*
        Path              /var/log/containers/*.log
        Parser            cri
        DB                /var/log/flb_kube.db
        Mem_Buf_Limit     5MB
        Skip_Long_Lines   On
        Refresh_Interval  10

    [FILTER]
        Name                kubernetes
        Match               kube.*
        Kube_URL            https://kubernetes.default.svc:443
        Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
        Merge_Log           On
        K8S-Logging.Parser  On
        K8S-Logging.Exclude On

    [OUTPUT]
        Name            es
        Match           *
        Host            elasticsearch.logging.svc
        Port            9200
        Logstash_Format On
        Logstash_Prefix k8s-logs
        Retry_Limit     False

  parsers.conf: |
    [PARSER]
        Name        cri
        Format      regex
        Regex       ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z
```

---

## 8. Best Practices Cho Production

### 8.1 Thu thập Log

| Practice | Chi tiết |
|----------|---------|
| **Ghi log ra stdout/stderr** | ⭐ Luôn khuyến khích ứng dụng ghi log ra standard streams |
| **Structured logging (JSON)** | Dùng JSON format để dễ parse và query |
| **Đặt resource limits cho agent** | Agent DaemonSet phải có requests/limits rõ ràng |
| **Label enrichment** | Đảm bảo log được gắn metadata: namespace, pod, container, node |
| **Log rotation** | Cấu hình log rotation ở container runtime level |

### 8.2 Lưu trữ

| Practice | Chi tiết |
|----------|---------|
| **Dùng PersistentVolume** | Elasticsearch/Loki cần PVC để tránh mất data khi pod restart |
| **Log retention policy** | Cấu hình tự động xóa log cũ (ILM cho ES, retention cho Loki) |
| **Separate storage** | Tách storage của logging khỏi application storage |
| **Backup** | Snapshot thường xuyên (ES snapshot hoặc object store replication) |

### 8.3 Bảo mật

| Practice | Chi tiết |
|----------|---------|
| **RBAC** | Phân quyền truy cập log theo namespace/team |
| **TLS** | Mã hóa giao tiếp giữa các component |
| **Sensitive data masking** | Lọc/ẩn thông tin nhạy cảm (password, token, PII) trước khi lưu |
| **Network Policy** | Giới hạn network access đến logging backend |

### 8.4 Monitoring the Monitoring

```
┌───────────────────────────────────────────────────────┐
│         GIÁM SÁT CHÍNH HỆ THỐNG LOG                   │
│                                                       │
│  Cần monitor:                                         │
│  • Fluent Bit/Promtail: Drop rate, buffer usage       │
│  • Loki/ES: Ingestion rate, query latency            │
│  • Storage: Disk usage, IOPS                          │
│  • Alerting:                                          │
│    - Khi log ingestion bị drop                       │
│    - Khi storage sắp đầy                             │
│    - Khi query response time quá lâu                 │
└───────────────────────────────────────────────────────┘
```

---

## 9. Tài Liệu Tham Khảo Chính Thức

### Kubernetes
| Tài liệu | Link |
|-----------|------|
| Logging Architecture | https://kubernetes.io/docs/concepts/cluster-administration/logging/ |
| System Logs | https://kubernetes.io/docs/concepts/cluster-administration/system-logs/ |
| Monitoring, Logging, and Debugging | https://kubernetes.io/docs/tasks/debug/ |

### Grafana Loki
| Tài liệu | Link |
|-----------|------|
| Loki Overview | https://grafana.com/docs/loki/latest/get-started/overview/ |
| Architecture & Components | https://grafana.com/docs/loki/latest/get-started/architecture/ |
| Deployment Modes | https://grafana.com/docs/loki/latest/get-started/deployment-modes/ |
| Install using Helm | https://grafana.com/docs/loki/latest/setup/install/helm/ |
| LogQL Query Language | https://grafana.com/docs/loki/latest/query/ |
| Label Best Practices | https://grafana.com/docs/loki/latest/get-started/labels/bp-labels/ |

### Elasticsearch / ECK
| Tài liệu | Link |
|-----------|------|
| ECK Documentation | https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html |
| Elasticsearch Reference | https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html |
| Kibana Guide | https://www.elastic.co/guide/en/kibana/current/index.html |

### Fluent Bit / Fluentd
| Tài liệu | Link |
|-----------|------|
| Fluent Bit Documentation | https://docs.fluentbit.io/ |
| Fluentd Documentation | https://docs.fluentd.org/ |
| CNCF Fluentd Project | https://www.cncf.io/projects/fluentd/ |

### Fluent Bit vs Fluentd (CNCF)
| Tiêu chí | Fluent Bit | Fluentd |
|----------|-----------|---------|
| Ngôn ngữ | C (nhẹ, nhanh) | Ruby + C |
| Memory | ~450KB | ~60MB |
| Vai trò chính | Forwarder/Collector | Aggregator/Processor |
| Plugin | Ít hơn, tập trung | Rất phong phú (700+) |
| Khuyến nghị | DaemonSet trên mỗi Node | Central aggregator |

---

## Tổng Kết

```
┌───────────────────────────────────────────────────────────────┐
│                     QUYẾT ĐỊNH CUỐI CÙNG                      │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  NẾU đã dùng Prometheus + Grafana ──────▶  PLG Stack   │  │
│  │  NẾU cần tiết kiệm tài nguyên  ────────▶  PLG Stack   │  │
│  │  NẾU mới bắt đầu, quy mô nhỏ  ────────▶  PLG Stack   │  │
│  │                                                         │  │
│  │  NẾU cần full-text search mạnh  ────────▶  EFK Stack   │  │
│  │  NẾU cần SIEM/security analytics ──────▶  EFK Stack   │  │
│  │  NẾU đã có Elasticsearch ecosystem ────▶  EFK Stack   │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  📌 Đề xuất cho dự án hiện tại:                               │
│     PLG Stack (Promtail + Loki + Grafana)                     │
│     với Helm chart trên Kubernetes                            │
│                                                               │
│  Lý do: Chi phí thấp, cloud-native, tích hợp tốt với K8s,   │
│  dễ triển khai và vận hành, phù hợp cho DevOps team.          │
└───────────────────────────────────────────────────────────────┘
```
