# Hướng dẫn Chuyên sâu: Kiến trúc và Thực hành Cụm RKE2

Tài liệu này cung cấp cái nhìn chi tiết về kiến trúc của **RKE2 (Rancher Kubernetes Engine 2)**, bao gồm cấu trúc Server/Agent node, các Core Concepts, cơ chế High Availability (HA) và hướng dẫn cài đặt.

---

## Mục lục
- [1. Tổng quan về RKE2](#1-tổng-quan-về-rke2)
- [2. Kiến trúc Server Node (Control Plane)](#2-kiến-trúc-server-node-control-plane)
- [3. Kiến trúc Agent Node (Worker Node)](#3-kiến-trúc-agent-node-worker-node)
- [4. Các Khái niệm Cốt lõi (Core Concepts)](#4-các-khái-niệm-cốt-lõi-core-concepts)
  - [4.1. Mạng lưới (Networking / CNI)](#41-mạng-lưới-networking--cni)
  - [4.2. Ingress Controller](#42-ingress-controller)
  - [4.3. Deep Dive: CoreDNS trong RKE2](#43-deep-dive-coredns-trong-rke2)
  - [4.4. Helm Controller](#44-helm-controller)
- [5. Cơ chế High Availability (HA RKE2)](#5-cơ-chế-high-availability-ha-rke2)
  - [5.1. Kiến trúc HA cơ bản](#51-kiến-trúc-ha-cơ-bản)
  - [5.2. Giải pháp 1: Sử dụng Load Balancer (LB)](#52-giải-pháp-1-sử-dụng-load-balancer-lb)
  - [5.3. Giải pháp 2: Sử dụng Virtual IP (VIP)](#53-giải-pháp-2-sử-dụng-virtual-ip-vip)
- [6. Thực hành Cài đặt (Step-by-Step)](#6-thực-hành-cài-đặt-step-by-step)

---

## 1. Tổng quan về RKE2
RKE2, còn được gọi là *RKE Government*, là một bản phân phối Kubernetes (distribution) do Rancher phát triển với sự tuân thủ nghiêm ngặt các tiêu chuẩn bảo mật.

*   **Định hướng Bảo mật (Security-first):** RKE2 được tối ưu mặc định để tuân thủ các cấu hình CIS Benchmark và xác thực chứng chỉ FIPS 140-2.
*   **Điểm khác biệt:**
    *   **So với RKE1:** RKE1 cài đặt các components K8s qua các Docker containers (yêu cầu cài Docker daemon trước). RKE2 cài đặt trực tiếp components và quản lý chúng qua **systemd**, và hoàn toàn không phụ thuộc vào Docker (sử dụng *containerd*).
    *   **So với K3s:** K3s phù hợp cho môi trường Edge/IoT với Edge DB (SQLite) và traefik. RKE2 kế thừa sự dễ dùng của K3s nhưng điều chỉnh cho môi trường Datacenter Production (dùng etcd, NGINX Ingress, Canal CNI mặc định).

> 📖 **Nguồn tài liệu chính thức RKE2:**
> *   [Introduction to RKE2](https://docs.rke2.io/)

---

## 2. Kiến trúc Server Node (Control Plane)
Trong RKE2, "Server" là thuật ngữ dùng để chỉ các node chạy Control Plane và Datastore (etcd).

*   **Các thành phần K8s cốt lõi:** `kube-apiserver`, `kube-scheduler`, `kube-controller-manager` được quản lý bởi `rke2-server` process và chạy dưới dạng **Static Pods** (giống Kubeadm).
*   **Datastore (etcd):** Hoạt động mặc định trên mọi Server node để đảm bảo dự phòng dữ liệu (HA etcd).
*   **Các thành phần Node-level:** Kubelet, kube-proxy, và containerd được tích hợp sẵn bên trong gói phân phối RKE2 và được quản lý vòng đời trực tiếp thông qua **Systemd service** (`rke2-server.service`).

> 📖 **Nguồn tài liệu chính thức RKE2:**
> *   [RKE2 Architecture Overview](https://docs.rke2.io/architecture)
> *   [Server Node Components](https://docs.rke2.io/architecture#server-node)

---

## 3. Kiến trúc Agent Node (Worker Node)
"Agent" là thuật ngữ RKE2 dùng để chỉ các Worker Node, nơi chạy các workload thực tế.

*   **Quy trình quản lý:** Được quản lý thông qua dịch vụ `rke2-agent.service` của Systemd.
*   **Thành phần chính:** Nó chứa Kubelet, kube-proxy, và container runtime (containerd). Kubelet sẽ nhận lệnh phân bổ từ Server node để khởi tạo container.
*   **Điểm nhấn:** Agent node hoàn toàn không chứa bất kỳ thành phần điều khiển hay dữ liệu nhạy cảm nào của cụm, tăng cường tính bảo vệ cho cụm.

> 📖 **Nguồn tài liệu chính thức RKE2:**
> *   [Agent Node Components](https://docs.rke2.io/architecture#agent-node)

---

## 4. Các Khái niệm Cốt lõi (Core Concepts)
RKE2 đóng gói sẵn các thành phần "Batteries Included" (giống K3s) để giúp khởi tạo một cụm chạy được ngay mà không cần cấu hình thủ công qua từng file Manifests như Kubeadm.

### 4.1. Mạng lưới (Networking / CNI)
RKE2 triển khai các plugin mạng dưới dạng Helm Charts. Điểm mạnh của RKE2 là không cần apply các cấu hình CNI thủ công mà chỉ cần khai báo qua file `/etc/rancher/rke2/config.yaml`.
*   **Canal (Mặc định):** Lựa chọn an toàn và ổn định. Nó là sự kết hợp cực kỳ thông minh: dùng **Flannel** (nhẹ, nhanh) để cấp phát IP và tạo Overlay Network, kết hợp với **Calico** (mạnh mẽ) để thực thi Network Policies (chặn/mở port giữa các Pod).
*   **Cilium (Khuyên dùng Production):** RKE2 hỗ trợ Native Cilium. Nhờ công nghệ eBPF, Cilium vượt qua giới hạn cổ điển của iptables, cung cấp hiệu năng định tuyến cực cao, khả năng quan sát sâu (qua Hubble) và bảo vệ ở tầng 7. Chỉ cần khai báo `cni: cilium` trước khi khởi động Node đầu tiên.
*   **Tùy chỉnh linh hoạt:** RKE2 hỗ trợ thêm Multus (cho phép 1 Pod gắn nhiều card mạng vật lý). Rất hữu ích cho các cụm Viễn thông (Telco) hoặc cần tách biệt traffic Storage/Management. Quản trị viên điều chỉnh cấu hình mạng sâu hơn bằng cách tạo tài nguyên `HelmChartConfig`.

### 4.2. Ingress Controller
*   RKE2 mặc định triển khai **NGINX Ingress Controller** (thay vì Traefik như K3s) dưới dạng DaemonSet trên mọi node, mở sẵn cổng ảo hóa mạng 80 và 443 ra Host.

### 4.3. Deep Dive: CoreDNS trong RKE2
CoreDNS chịu trách nhiệm biến các tên Service (như `my-db.default.svc.cluster.local`) thành IP cụ thể. RKE2 quản lý CoreDNS theo cách hoàn toàn khác biệt so với Kubeadm:
*   **Đóng gói qua Helm:** Thay vì dùng Manifest tĩnh, CoreDNS được RKE2 quản lý hoàn toàn bằng biểu đồ Helm (Helm Chart). Điều này giúp việc nâng cấp CoreDNS diễn ra an toàn, tự động khi nâng cấp phiên bản RKE2.
*   **Tùy chỉnh qua HelmChartConfig:** Trong Kubeadm, nếu muốn sửa `Corefile` (Vd: cấu hình DNS chuyển tiếp ra nội bộ công ty), người quản trị phải sửa ConfigMap của CoreDNS (có nguy cơ bị ghi đè sau khi nâng cấp cụm). Với RKE2, chỉ cần tạo một file `HelmChartConfig` đặt trong thư mục `/var/lib/rancher/rke2/server/manifests/`. RKE2 sẽ tự động kết hợp (merge) các cấu hình tùy chỉnh vào cấu hình nội tại, giúp Custom DNS forwarding tồn tại vĩnh viễn.
*   **Plugin NodeHosts tự động:** RKE2 tự động tiêm một plugin đặc biệt tên là `NodeHosts` vào CoreDNS. Nó tự động cập nhật danh sách IP của tất cả các Node vật lý hiện có. Nhờ đó, Pods trong cụm luôn có thể phân giải tên máy chủ của node một cách siêu tốc ngay bên trong mạng K8s mà không cần ra DNS Public ngoài mạng LAN.

### 4.4. Helm Controller
*   Tính năng độc quyền: Kế thừa từ K3s, RKE2 có một bộ điều khiển tự động giám sát thư mục `/var/lib/rancher/rke2/server/manifests/`. Bất kỳ file YAML hoặc packaged Helm Chart nào file đặt vào đây đều được tự động deploy.

> 📖 **Nguồn tài liệu chính thức RKE2:**
> *   [RKE2 Networking & CNI Options](https://docs.rke2.io/networking)
> *   [Ingress Configuration](https://docs.rke2.io/networking#ingress)
> *   [Helm Integration](https://docs.rke2.io/helm)

---

## 5. Cơ chế High Availability (HA RKE2)

### 5.1. Kiến trúc HA cơ bản
Một cluster HA chuẩn thường bao gồm:
*   **3 hoặc 5 Server Nodes (Control Plane):** Đảm bảo số lẻ để duy trì Quorum cho etcd. Thuật toán Raft của etcd yêu cầu quá bán để quyết định "nguồn sự thật", giúp tránh hội chứng não chia não (Split-brain).
*   **N Agent Nodes (Worker):** Chạy khối lượng công việc thực tế.
*   **1 Endpoint chung (LB hoặc VIP):** Điểm truy cập duy nhất cho toàn bộ cluster (thay vì trỏ vào 1 IP tĩnh của Server node).

Dưới đây là phiên bản **đầy đủ về HA của RKE2**, bao gồm cả **Load Balancer (LB)** và **Virtual IP (VIP)**, kèm gợi ý công cụ và khi nên dùng:

### 5.2. Giải pháp 1: Sử dụng Load Balancer (LB)
Load Balancer (Bộ cân bằng tải) đứng giữa Client/Agent và các Server nodes, nhận traffic và phân phối đều. Nó phù hợp cho môi trường Cloud hoặc Datacenter lớn có sẵn hạ tầng mạng.

*   **2 Luồng Traffic Đặc thù:** LB của RKE2 bắt buộc phải xử lý 2 port riêng biệt:
    *   **Port 9345 (Agent Registration):** Luồng nội bộ để Agent gia nhập (join) cụm và nhận chứng chỉ.
    *   **Port 6443 (API Server):** Luồng tương tác chuẩn của Kubernetes (`kubectl`, Pods, Kubelet).
*   **Rủi ro SSL & Cờ `tls-san`:** Vì LB là trạm trung gian, chứng chỉ SSL tĩnh của Server sẽ bị từ chối do khác IP. Quản trị viên **bắt buộc** cấu hình `tls-san: ["<IP_LB>"]` trong `config.yaml` để khai báo danh tính của LB với cụm.
*   **Gợi ý công cụ:**
    *   *Cloud:* AWS ELB, Google Cloud LB, F5 BIG-IP.
    *   *Tự dựng:* HAProxy, NGINX (Stream mode proxy).
*   **Khi nào nên dùng:** Có lượng request API khổng lồ cần giảm tải cho Control Plane; hệ thống Cloud tự cấp LB nhanh gọn.

### 5.3. Giải pháp 2: Sử dụng Virtual IP (VIP)
Giải pháp VIP tạo ra một IP ảo và gán nó luân phiên cho một trong các Server nodes (mô hình Active-Passive). Trái ngược với LB, traffic đi thẳng tới node đang cầm VIP.

*   **Tính tinh gọn:** VIP gắn thẳng trên giao diện mạng vật lý của Server node. Nếu node Master 1 (đang cầm VIP) bị sập, IP VIP sẽ tự động thuyên chuyển sang node Master 2 trong vài giây, đảm bảo Agent node không bị rớt.
*   **Gợi ý công cụ:**
    *   **Kube-vip:** Công cụ hiện đại, chạy nội bộ trong cụm dưới hình thức DaemonSet. Nó sử dụng chuẩn BGP hoặc ARP để thông báo IP thay thế. *(Đây là cách hệ thống hiện tại đang tích hợp).*
    *   **Keepalived:** Dịch vụ VRRP truyền thống, yêu cầu cấu hình trên OS Ubuntu của host.
*   **Khi nào nên dùng:**
    *   Môi trường hạ tầng tự dựng (Bare-metal) hoặc On-Premise.
    *   Cần độ trễ mạng thấp nhất (vì Request đi thẳng vào Master Node thay vì qua "trạm thu phí" Load Balancer).
    *   Tiết kiệm chi phí, không cần cấp riêng cụm máy chủ chỉ để làm Load Balancer.

> 📖 **Nguồn tài liệu chính thức RKE2:**
> *   [High Availability Installation](https://docs.rke2.io/install/ha)

---

## 6. Thực hành Cài đặt (Step-by-Step)
Ví dụ cài đặt RKE2 hạ tầng cơ bản. Hệ thống `install script` tự động tải các runtime, setup systemd, tạo certs. Dưới đây là cài qua CLI:

### Bước 1: Cấu hình Fixed Address (Trên Load Balancer/DNS trước)
*   *Giả sử Load Balancer nội bộ cấp phát IP VIP: `192.168.1.100`*
*   Cấu hình LB chuyển tiếp port `6443` (Apiserver) và `9345` (Node Registration) tới 3 địa chỉ IP của các Server.

### Bước 2: Cài đặt Server Node đầu tiên (Leader Node)
```bash
# 1. Cài đặt RKE2 Server thông qua script chuẩn
curl -sfL https://get.rke2.io | sh -

# 2. Tạo file cấu hình
mkdir -p /etc/rancher/rke2
cat <<EOF > /etc/rancher/rke2/config.yaml
tls-san:
  - "192.168.1.100" # IP của Load Balancer
cni: "cilium"       # Đổi CNI mặc định sang Cilium (tuỳ chọn)
EOF

# 3. Kích hoạt và khởi động Server Process
systemctl enable rke2-server.service
systemctl start rke2-server.service

# 4. Lấy token do Server tự gen để chuẩn bị join các node khác
cat /var/lib/rancher/rke2/server/node-token
```

### Bước 3: Cài đặt các Server Node tiếp theo (HA Server)
```bash
curl -sfL https://get.rke2.io | sh -
mkdir -p /etc/rancher/rke2
cat <<EOF > /etc/rancher/rke2/config.yaml
server: "https://192.168.1.100:9345" # Trỏ về Proxy Load Balancer thay vì IP nội bộ Node 1
token: "<TOKEN-LAY-TU-BUOC-2>"
tls-san:
  - "192.168.1.100"
EOF
systemctl enable rke2-server.service
systemctl start rke2-server.service
```

### Bước 4: Cài đặt Agent Node (Worker Node)
```bash
# Export biến môi trường bắt buộc của install process
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -

mkdir -p /etc/rancher/rke2
cat <<EOF > /etc/rancher/rke2/config.yaml
server: "https://192.168.1.100:9345"
token: "<TOKEN-LAY-TU-BUOC-2>"
EOF
systemctl enable rke2-agent.service
systemctl start rke2-agent.service
```

> 📖 **Nguồn tài liệu chính thức RKE2:**
> *   [RKE2 Quick Start](https://docs.rke2.io/install/quickstart)

---
*Tài liệu nghiên cứu kiến trúc RKE2 High Availability Production Build.*
