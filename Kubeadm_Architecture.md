# Hướng dẫn Chuyên sâu: Kiến trúc và Thực hành Cụm Kubeadm

Tài liệu này cung cấp cái nhìn chi tiết về kiến trúc của một cụm Kubernetes được khởi tạo bằng `kubeadm`, các thành phần cốt lõi, và hướng dẫn thực hành cài đặt chuẩn.

---

## 1. Tổng quan về Kubeadm
**Kubeadm** là công cụ tiêu chuẩn được thiết kế để thiết lập một cụm Kubernetes tối thiểu nhưng bảo mật và tuân thủ các "best practices".

*   **Triết lý:** Kubeadm đóng vai trò như một **bộ khung (framework)**. Nó chỉ cài đặt những thứ "vừa đủ" để cụm hoạt động. Các lớp như Network (CNI), Storage (CSI) hay Ingress được để ngỏ để người quản trị tự chọn giải pháp phù hợp.
*   **Đặc điểm:** Tối giản, tập trung vào quản lý vòng đời (Lifecycle) như khởi tạo, nâng cấp (`upgrade`), và quản lý chứng chỉ (`certs`).

> 📖 **Nguồn tài liệu chính thức:**
> *   [Overview of kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
> *   [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)

---

## 2. Kiến trúc Control Plane (Lớp Điều khiển)
Trong cụm Kubeadm, các thành phần Control Plane thường chạy dưới dạng **Static Pods**. Kubelet sẽ quét thư mục `/etc/kubernetes/manifests` và tự động chạy các file `.yaml` tại đó.

### 2.1. Các thành phần chính:
*   **kube-apiserver:** Cổng giao tiếp duy nhất của cụm. Tất cả các thành phần khác đều gọi vào đây. Nó lưu trạng thái vào etcd.
*   **etcd:** Cơ sở dữ liệu Key-Value phân tán. Trong Kubeadm mặc định, etcd chạy cùng trên node Master (Stacked etcd).
*   **kube-scheduler:** Lập lịch cho Pod. Nó tìm node phù hợp nhất dựa trên tài nguyên sẵn có.
*   **kube-controller-manager:** Chạy các bộ điều khiển (controllers) để đảm bảo trạng thái thực tế khớp với trạng thái mong muốn (ví dụ: đảm bảo đủ số lượng replica).

> 📖 **Nguồn tài liệu chính thức:**
> *   [Kubernetes Components (Control Plane)](https://kubernetes.io/docs/concepts/overview/components/#control-plane-components)
> *   [Static Pods in Kubeadm](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)

---

## 3. Kiến trúc Worker Node (Lớp Thực thi)
Worker node là nơi các ứng dụng thực sự chạy.

*   **Kubelet:** Đại lý (Agent) chạy trên mỗi node. Nó nhận chỉ thị từ Control Plane và điều phối với **Container Runtime** để chạy container. *Lưu ý: Kubelet chạy trực tiếp trên OS (systemd), không phải trong container.*
*   **kube-proxy:** Phụ trách mạng lưới (Networking) cho Service. Nó điều hướng traffic đến đúng Pod bằng cách cấu hình `iptables` hoặc `IPVS` trên node.
*   **Container Runtime (CRI):** Phần mềm thực thi container (ví dụ: `containerd`, `CRI-O`).

> 📖 **Nguồn tài liệu chính thức:**
> *   [Node Components](https://kubernetes.io/docs/concepts/overview/components/#node-components)
> *   [Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)

---

## 4. Các mảng quan trọng "thường bị bỏ quên"
Để một cụm Kubeadm thực sự sẵn sàng dùng cho môi trường Lab/Production, cần hiểu thêm:

1.  **CNI (Container Network Interface):** Kubeadm **KHÔNG** cài sẵn mạng. Sau khi `init`, node sẽ ở trạng thái `NotReady` cho đến khi bạn cài một plugin mạng như **Cilium, Calico, hoặc Flannel**.
2.  **Cơ chế TLS Bootstrapping:** Kubeadm tự động tạo ra một hệ thống PKI (Private Key Infrastructure). Các chứng chỉ mặc định có thời hạn **01 năm**. Bạn cần dùng lệnh `kubeadm certs renew` để gia hạn.
3.  **High Availability (HA):** Để làm HA cho Kubeadm, bạn cần một **External Load Balancer** (như HAProxy/Keepalived) đặt trước các node API Server.
4.  **CoreDNS:** Là add-on duy nhất Kubeadm cài sẵn để phục vụ phân giải tên miền trong cụm.

---

## 5. Quy trình Khởi tạo Core Cluster
Thay vì liệt kê chi tiết việc cài đặt gói hệ thống, phần này tập trung vào các lệnh khởi tạo cốt lõi để thiết lập cụm.

### Bước 1: Khởi tạo Control Plane
Sử dụng dải mạng Pod tương ứng với CNI sẽ cài đặt (Cilium mặc định hỗ trợ dải này).
```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Cấu hình kubectl cho user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Bước 2: Cài đặt CNI (Cilium)
Cilium sử dụng eBPF để xử lý mạng, cung cấp hiệu suất và khả năng bảo mật mạnh mẽ.
```bash
# Cài đặt Cilium CLI và thực thi install
cilium install
```

### Bước 3: Thêm Worker Node vào cụm (Join Cluster)
Sau khi `kubeadm init` thành công, terminal sẽ in ra một lệnh `kubeadm join` kèm theo token. Bạn cần chạy lệnh này trên các **Worker Node**:
```bash
# Lệnh ví dụ (Lấy từ output của bước init trên Master Node)
sudo kubeadm join <control-plane-host>:<control-plane-port> --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

> 📖 **Nguồn tài liệu chính thức:**
> *   [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
> *   [Joining your nodes](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#join-nodes)

---

## 6. Deep Dive: Cơ chế High Availability (HA)
Khi triển khai môi trường Production, việc chạy 1 node Master là cực kỳ rủi ro. Kubeadm hỗ trợ 2 mô hình HA chính:

### 6.1. Stacked etcd Topology (Phổ biến nhất)
*   **Mô hình:** Mỗi node Control Plane sẽ chạy cả `kube-apiserver` và một thành phần `etcd` local.
*   **Ưu điểm:** Dễ thiết lập, tiết kiệm số lượng node.
*   **Nhược điểm:** Nếu một node chết, bạn mất cả API Server và 1 member etcd.

### 6.2. External etcd Topology
*   **Mô hình:** Cụm etcd được tách riêng ra các node khác (thường là 3 node). Các node Control Plane chỉ chạy API Server và gọi sang cụm etcd này.
*   **Ưu điểm:** Tách biệt hoàn toàn lớp dữ liệu và lớp điều khiển, bảo mật và ổn định hơn.

### 6.3. Vai trò của Load Balancer
Trong Kubeadm HA, bạn **bắt buộc** phải có một Load Balancer (ví dụ: HAProxy + Keepalived hoặc F5) đứng trước.
*   Tất cả các Worker Node sẽ trỏ đến IP của Load Balancer (VIP).
*   Load Balancer sẽ phân phối traffic đến các node `kube-apiserver` ở cổng 6443.

> 📖 **Nguồn tài liệu chính thức:**
> *   [Options for Highly Available Topology](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/)
> *   [Creating Highly Available clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)

---

## 7. Deep Dive: CoreDNS trong Kubeadm
CoreDNS là "trạm điều hướng" tên miền bên trong Cluster.

### 7.1. Cách thức hoạt động
Khi bạn tạo một Service, Kube-controller-manager sẽ tạo ra một Endpoint tương ứng. CoreDNS theo dõi API Server và tự động tạo các bản ghi DNS:
*   Định dạng: `<service-name>.<namespace>.svc.cluster.local`.

### 7.2. Corefile (Trái tim của CoreDNS)
Cấu hình của CoreDNS được lưu trong một ConfigMap tên là `coredns` ở namespace `kube-system`. Một số plugin quan trọng:
*   **`kubernetes`:** Phụ trách trả lời các truy vấn cho Service/Pod trong cụm.
*   **`forward`:** Nếu không tìm thấy tên miền trong cụm (như `google.com`), nó sẽ đẩy ra DNS của Server vật lý (thông qua `/etc/resolv.conf`).
*   **`cache`:** Lưu lại các truy vấn giúp tăng tốc độ phân giải.

> 📖 **Nguồn tài liệu chính thức:**
> *   [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
> *   [Customizing DNS Service (CoreDNS)](https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/)

---
*Tài liệu được soạn thảo đáp ứng yêu cầu nghiên cứu kiến trúc cụm Kubeadm.*
