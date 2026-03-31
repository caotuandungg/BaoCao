# Nghiên Cứu: Hệ Thống Log Tập Trung Trên Kubernetes

> **Người thực hiện:** Dũng  
> **Ngày:** 31/03/2026  
> **Mục tiêu:** Tìm hiểu kiến trúc logging tập trung trên Kubernetes theo tài liệu chính thức

---

## Mục Lục

1. [Tại sao cần hệ thống Log tập trung trên K8s?](#1-tại-sao-cần-hệ-thống-log-tập-trung-trên-k8s)
2. [Kiến trúc Logging trong Kubernetes](#2-kiến-trúc-logging-trong-kubernetes)
3. [Các mô hình thu thập Log trên K8s](#3-các-mô-hình-thu-thập-log-trên-k8s)
4. [Best Practices cho Production](#4-best-practices-cho-production)
5. [Tài liệu tham khảo chính thức](#5-tài-liệu-tham-khảo-chính-thức)

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
│ │ Log Agent  │  │        │ │ Log Agent  │  │        │ │ Log Agent  │  │
│ │ (DaemonSet)│  │        │ │ (DaemonSet)│  │        │ │ (DaemonSet)│  │
│ └─────┬──────┘  │        │ └─────┬──────┘  │        │ └─────┬──────┘  │
└───────┼─────────┘        └───────┼─────────┘        └───────┼─────────┘
        │                          │                          │
        └──────────────┬───────────┘──────────────────────────┘
                       │
                       ▼
            ┌──────────────────┐
            │  Log Backend     │
            │  (Lưu trữ +     │
            │   Tìm kiếm)     │
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

### 3.3 So sánh các mô hình

| Tiêu chí | Node-level Agent ⭐ | Sidecar | App tự gửi |
|----------|---------------------|---------|------------|
| **Tài nguyên** | Thấp (1 agent/node) | Cao (1 agent/pod) | Không tốn thêm |
| **Sửa app code** | Không | Không | Có |
| **Phù hợp** | Mọi trường hợp | App legacy | Không khuyến khích |
| **Độ phức tạp** | Thấp | Trung bình | Cao |
| **K8s khuyến nghị** | ✅ Có | Tùy trường hợp | ❌ Không |

---

## 4. Best Practices Cho Production

### 4.1 Thu thập Log

| Practice | Chi tiết |
|----------|---------|
| **Ghi log ra stdout/stderr** | ⭐ Luôn khuyến khích ứng dụng ghi log ra standard streams |
| **Structured logging (JSON)** | Dùng JSON format để dễ parse và query |
| **Đặt resource limits cho agent** | Agent DaemonSet phải có requests/limits rõ ràng |
| **Label enrichment** | Đảm bảo log được gắn metadata: namespace, pod, container, node |
| **Log rotation** | Cấu hình log rotation ở container runtime level |

### 4.2 Lưu trữ

| Practice | Chi tiết |
|----------|---------|
| **Dùng PersistentVolume** | Backend lưu log cần PVC để tránh mất data khi pod restart |
| **Log retention policy** | Cấu hình tự động xóa log cũ để tránh đầy ổ cứng |
| **Separate storage** | Tách storage của logging khỏi application storage |
| **Backup** | Snapshot thường xuyên để đảm bảo an toàn dữ liệu |

### 4.3 Bảo mật

| Practice | Chi tiết |
|----------|---------|
| **RBAC** | Phân quyền truy cập log theo namespace/team |
| **TLS** | Mã hóa giao tiếp giữa các component |
| **Sensitive data masking** | Lọc/ẩn thông tin nhạy cảm (password, token, PII) trước khi lưu |
| **Network Policy** | Giới hạn network access đến logging backend |

### 4.4 Monitoring the Monitoring

```
┌───────────────────────────────────────────────────────┐
│         GIÁM SÁT CHÍNH HỆ THỐNG LOG                   │
│                                                       │
│  Cần monitor:                                         │
│  • Log Agent: Drop rate, buffer usage                │
│  • Backend: Ingestion rate, query latency            │
│  • Storage: Disk usage, IOPS                          │
│  • Alerting:                                          │
│    - Khi log ingestion bị drop                       │
│    - Khi storage sắp đầy                             │
│    - Khi query response time quá lâu                 │
└───────────────────────────────────────────────────────┘
```

---

## 5. Tài Liệu Tham Khảo Chính Thức

### Kubernetes
| Tài liệu | Link |
|-----------|------|
| Logging Architecture | https://kubernetes.io/docs/concepts/cluster-administration/logging/ |
| System Logs | https://kubernetes.io/docs/concepts/cluster-administration/system-logs/ |
| Monitoring, Logging, and Debugging | https://kubernetes.io/docs/tasks/debug/ |

---

## Tổng Kết

```
┌───────────────────────────────────────────────────────────────┐
│                       TÓM TẮT                                │
│                                                               │
│  1. Kubernetes KHÔNG cung cấp giải pháp logging tập trung     │
│     sẵn có. Bạn cần tự triển khai.                            │
│                                                               │
│  2. Phương pháp được khuyến nghị nhất:                        │
│     ⭐ Node-level Logging Agent (DaemonSet)                   │
│     → Chạy 1 agent trên mỗi Node                             │
│     → Agent đọc log từ /var/log/pods/                         │
│     → Gửi đến backend lưu trữ tập trung                      │
│                                                               │
│  3. Ứng dụng nên:                                             │
│     → Ghi log ra stdout/stderr                                │
│     → Dùng structured logging (JSON)                          │
│                                                               │
│  4. Đọc thêm tài liệu chính thức:                            │
│     kubernetes.io/docs/concepts/cluster-administration/       │
│     logging/                                                  │
└───────────────────────────────────────────────────────────────┘
```
