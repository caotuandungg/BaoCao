# Báo cáo Hiện trạng Cụm Kubernetes (K8s)

## 1. Tổng quan
- **Cơ chế phân phối (Distribution):** RKE2 (phiên bản `v1.33.6+rke2r1`)
- **Tổng số Node:** 6 Node.
- **Tình trạng:** Tất cả các Node đều đang hoạt động ổn định (`Ready`).

## 2. Chi tiết hệ thống Nodes
**Cách kiểm tra:**
```bash
# Xem danh sách và thông tin tóm tắt
k get nodes -o wide

# Xem thông tin cấu hình chi tiết CPU/RAM của từng node
k get nodes -o custom-columns="NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory"
```

Cụm bao gồm 3 Control-plane (Master) nodes và 3 Worker nodes, chạy trên hệ điều hành **Ubuntu 24.04.3 LTS** (Kernel `6.8.0-90-generic`) với container runtime là **containerd** (`v2.1.5-k3s1`).

| NAME | STATUS | ROLES | AGE | VERSION | INTERNAL-IP | EXTERNAL-IP | OS-IMAGE | KERNEL-VERSION | CONTAINER-RUNTIME |
|------|--------|-------|-----|---------|-------------|-------------|----------|----------------|-------------------|
| `cp01` | Ready | control-plane,etcd,master | 49d | v1.33.6+rke2r1 | 172.18.0.51 | `<none>` | Ubuntu 24.04.3 LTS | 6.8.0-90-generic | containerd://2.1.5-k3s1 |
| `cp02` | Ready | control-plane,etcd,master | 49d | v1.33.6+rke2r1 | 172.18.0.52 | `<none>` | Ubuntu 24.04.3 LTS | 6.8.0-90-generic | containerd://2.1.5-k3s1 |
| `cp03` | Ready | control-plane,etcd,master | 49d | v1.33.6+rke2r1 | 172.18.0.53 | `<none>` | Ubuntu 24.04.3 LTS | 6.8.0-90-generic | containerd://2.1.5-k3s1 |
| `wk01` | Ready | `<none>` | 49d | v1.33.6+rke2r1 | 172.18.0.61 | `<none>` | Ubuntu 24.04.3 LTS | 6.8.0-90-generic | containerd://2.1.5-k3s1 |
| `wk02` | Ready | `<none>` | 49d | v1.33.6+rke2r1 | 172.18.0.62 | `<none>` | Ubuntu 24.04.3 LTS | 6.8.0-90-generic | containerd://2.1.5-k3s1 |
| `wk03` | Ready | `<none>` | 49d | v1.33.6+rke2r1 | 172.18.0.63 | `<none>` | Ubuntu 24.04.3 LTS | 6.8.0-90-generic | containerd://2.1.5-k3s1 |

## 3. Hệ thống Lưu trữ (Storage - PV/PVC)
**Cách kiểm tra:**
```bash
# Xem các loại Storage (StorageClass) và ổ cứng đang được cấp (PV, PVC)
k get sc,pv,pvc -A
```

Cụm đang sử dụng **OpenStack Cinder CSI** (`cinder.csi.openstack.org`) làm giải pháp Storage Provisioner trực tiếp tích hợp với hạ tầng mây.

**3.1. Các mức lưu trữ (StorageClasses):**
Cụm sử dụng OpenStack Cinder làm giải pháp lưu trữ chính thông qua CSI driver.
**Cách kiểm tra:**
```bash
k get sc -A -o wide
```
| NAME | PROVISIONER | RECLAIMPOLICY | VOLUMEBINDINGMODE | ALLOWVOLUMEEXPANSION | AGE |
|------|-------------|---------------|-------------------|----------------------|-----|
| `csi-cinder-sc-delete` | `cinder.csi.openstack.org` | Delete | Immediate | true | 49d |
| `csi-cinder-sc-retain` | `cinder.csi.openstack.org` | Retain | Immediate | true | 49d |

**3.2. Hiện trạng Persistent Volumes (PV):**
PV là tài nguyên lưu trữ ở mức Cluster-level đã được cấp phát.
**Cách kiểm tra:**
```bash
k get pv -A -o wide
```
| NAME | CAPACITY | ACCESS MODES | RECLAIM POLICY | STATUS | CLAIM | STORAGECLASS | VOLUMEATTRIBUTESCLASS | REASON | AGE | VOLUMEMODE |
|------|----------|--------------|----------------|--------|-------|--------------|-----------------------|--------|-----|------------|
| `pvc-01107...c0e4` | 20Gi | RWO | Retain | Bound | `snipe-it/datadir-snipe-it-db-cluster-1` | `csi-cinder-sc-retain` | `<unset>` | | 43d | Filesystem |
| `pvc-024ce...29af` | 30Gi | RWO | Delete | Bound | `elk/elasticsearch-master-elasticsearch-master-1` | `csi-cinder-sc-delete` | `<unset>` | | 37d | Filesystem |
| `pvc-3528f...8193` | 20Gi | RWO | Retain | Bound | `snipe-it/datadir-snipe-it-db-cluster-0` | `csi-cinder-sc-retain` | `<unset>` | | 43d | Filesystem |
| `pvc-70f4c...4b68` | 20Gi | RWO | Retain | Bound | `keycloak/psql-keycloak-3` | `csi-cinder-sc-retain` | `<unset>` | | 49d | Filesystem |
| `pvc-a4120...4790` | 20Gi | RWO | Retain | Bound | `keycloak/psql-keycloak-2` | `csi-cinder-sc-retain` | `<unset>` | | 49d | Filesystem |
| `pvc-bb67b...bd9f` | 30Gi | RWO | Delete | Bound | `elk/elasticsearch-master-elasticsearch-master-2` | `csi-cinder-sc-delete` | `<unset>` | | 37d | Filesystem |
| `pvc-bb85a...071e` | 20Gi | RWO | Retain | Bound | `snipe-it/datadir-snipe-it-db-cluster-2` | `csi-cinder-sc-retain` | `<unset>` | | 43d | Filesystem |
| `pvc-caebe...7d5a` | 20Gi | RWO | Retain | Bound | `keycloak/psql-keycloak-1` | `csi-cinder-sc-retain` | `<unset>` | | 49d | Filesystem |
| `pvc-ecea0...d1ef` | 30Gi | RWO | Delete | Bound | `elk/elasticsearch-master-elasticsearch-master-0` | `csi-cinder-sc-delete` | `<unset>` | | 37d | Filesystem |

**3.3. Hiện trạng Persistent Volume Claims (PVC):**
Có 9 PVC do các ứng dụng gửi yêu cầu xuống xin không gian lưu trữ. PVC nằm ở trong từng Namespace riêng của ứng dụng:

| NAMESPACE | NAME | STATUS | VOLUME | CAPACITY | ACCESS MODES | STORAGECLASS | VOLUMEATTRIBUTESCLASS | AGE |
|-----------|------|--------|--------|----------|--------------|--------------|-----------------------|-----|
| elk | `elasticsearch-master-elasticsearch-master-0` | Bound | pvc-ecea0...d1ef | 30Gi | RWO | csi-cinder-sc-delete | `<unset>` | 37d |
| elk | `elasticsearch-master-elasticsearch-master-1` | Bound | pvc-024ce...29af | 30Gi | RWO | csi-cinder-sc-delete | `<unset>` | 37d |
| elk | `elasticsearch-master-elasticsearch-master-2` | Bound | pvc-bb67b...bd9f | 30Gi | RWO | csi-cinder-sc-delete | `<unset>` | 37d |
| keycloak | `psql-keycloak-1` | Bound | pvc-caebe...7d5a | 20Gi | RWO | csi-cinder-sc-retain | `<unset>` | 49d |
| keycloak | `psql-keycloak-2` | Bound | pvc-a4120...4790 | 20Gi | RWO | csi-cinder-sc-retain | `<unset>` | 49d |
| keycloak | `psql-keycloak-3` | Bound | pvc-70f4c...4b68 | 20Gi | RWO | csi-cinder-sc-retain | `<unset>` | 49d |
| snipe-it | `datadir-snipe-it-db-cluster-0` | Bound | pvc-3528f...8193 | 20Gi | RWO | csi-cinder-sc-retain | `<unset>` | 43d |
| snipe-it | `datadir-snipe-it-db-cluster-1` | Bound | pvc-01107...c0e4 | 20Gi | RWO | csi-cinder-sc-retain | `<unset>` | 43d |
| snipe-it | `datadir-snipe-it-db-cluster-2` | Bound | pvc-bb85a...071e | 20Gi | RWO | csi-cinder-sc-retain | `<unset>` | 43d |


## 4. Hệ thống Mạng lưới (Network)
- **CNI Plugin:** Sử dụng **Cilium** kết hợp ứng dụng **Hubble** để giám sát và bảo mật mạng dựa trên chuẩn eBPF với hiệu suất cao.
- **CoreDNS:** Được RKE2 tự động cung cấp (`rke2-coredns`).
- **Load Balancing (Layer 2/3):** Chạy `kube-vip` dưới dạng DaemonSet trên 3 node control-plane (`cp01`, `cp02`, `cp03`) để tạo IP độ HA cao trực tiếp gắn cho Apiserver và LoadBalancer services.
- **Ingress Controller (Layer 7):** Đang chạy **NGINX Ingress Controller** (Namespace: `nginx-ingress`), expose Ingress Class `nginx`.

**4.1. Hiện trạng Dịch vụ Mạng (Services):**
Các Services đóng vai trò là điểm vào ổn định cho ứng dụng.
**Cách kiểm tra:**
```bash
k get svc -A -o wide
```
| NAMESPACE | NAME | TYPE | CLUSTER-IP | EXTERNAL-IP | PORT(S) | AGE | SELECTOR |
|-----------|------|------|------------|-------------|---------|-----|----------|
| cnpg-system | `cnpg-webhook-service` | ClusterIP | `10.101.21.171` | `<none>` | `443/TCP` | 49d | `app.kubernetes.io/name=cloudnative-pg` |
| default | `kubernetes` | ClusterIP | `10.101.0.1` | `<none>` | `443/TCP` | 49d | `<none>` |
| elk | `elasticsearch-master` | ClusterIP | `10.101.232.144` | `<none>` | `9200/TCP,9300/TCP` | 37d | `app=elasticsearch-master,chart=elasticsearch,release=elasticsearch` |
| elk | `elasticsearch-master-headless` | ClusterIP | None | `<none>` | `9200/TCP,9300/TCP` | 37d | `app=elasticsearch-master` |
| elk | `kibana-kibana` | ClusterIP | `10.101.82.190` | `<none>` | `5601/TCP` | 37d | `app=kibana,release=kibana` |
| keycloak | `keycloak` | ClusterIP | `10.101.39.214` | `<none>` | `8080/TCP` | 49d | `app=keycloak` |
| keycloak | `keycloak-discovery` | ClusterIP | None | `<none>` | `<none>` | 49d | `app=keycloak` |
| keycloak | `psql-keycloak-r` | ClusterIP | `10.101.104.200` | `<none>` | `5432/TCP` | 49d | `cnpg.io/cluster=psql-keycloak,cnpg.io/podRole=instance` |
| keycloak | `psql-keycloak-ro` | ClusterIP | `10.101.216.224` | `<none>` | `5432/TCP` | 49d | `cnpg.io/cluster=psql-keycloak,cnpg.io/instanceRole=replica` |
| keycloak | `psql-keycloak-rw` | ClusterIP | `10.101.113.13` | `<none>` | `5432/TCP` | 49d | `cnpg.io/cluster=psql-keycloak,cnpg.io/instanceRole=primary` |
| kube-system | `cilium-envoy` | ClusterIP | None | `<none>` | `9964/TCP` | 49d | `k8s-app=cilium-envoy` |
| kube-system | `hubble-peer` | ClusterIP | `10.101.92.4` | `<none>` | `443/TCP` | 49d | `k8s-app=cilium` |
| kube-system | `rke2-coredns-rke2-coredns` | ClusterIP | `10.101.0.10` | `<none>` | `53/UDP,53/TCP` | 49d | `app.kubernetes.io/instance=rke2-coredns,app.kubernetes.io/name=rke2-coredns,k8s-app=kube-dns` |
| kube-system | `rke2-metrics-server` | ClusterIP | `10.101.213.108` | `<none>` | `443/TCP` | 49d | `app.kubernetes.io/instance=rke2-metrics-server,app.kubernetes.io/name=rke2-metrics-server,app=rke2-metrics-server` |
| nginx-ingress | `nginx-ingress` | NodePort | `10.101.48.214` | `<none>` | `80:32053/TCP,443:31489/TCP` | 49d | `app=nginx-ingress` |
| sonobuoy | `sonobuoy-aggregator` | ClusterIP | `10.101.64.185` | `<none>` | `8080/TCP` | 35d | `sonobuoy-component-aggregator` |

**4.2. Hiện trạng Tên miền ngoài (Ingresses):**
Tất cả các Ingress đều đang sử dụng Ingress Class là `nginx` và tự động cấp cổng HTTP/HTTPS.
**Cách kiểm tra:**
```bash
k get ingress -A
```
| NAMESPACE | NAME | CLASS | HOSTS | ADDRESS | PORTS | AGE |
|-----------|------|-------|-------|---------|-------|-----|
| elk | `elasticsearch-master` | nginx | `elasticsearch.vnpost.cloud` | | 80, 443 | 37d |
| elk | `kibana-kibana` | nginx | `kibana.vnpost.cloud` | | 80, 443 | 37d |
| keycloak | `keycloak` | nginx | `iam.vnpost.cloud` | | 80, 443 | 49d |

**4.3. Hiện trạng Ứng dụng chạy thực tế (Pods):**
Đây là danh sách đầy đủ tất cả các Pod đang chạy trong toàn bộ Cluster.
**Cách kiểm tra:**
```bash
k get pods -A -o wide
```
| NAMESPACE | NAME | READY | STATUS | RESTARTS | AGE | IP | NODE | NOMINATED NODE | READINESS GATES |
|-----------|------|-------|--------|----------|-----|----|------|----------------|-----------------|
| cnpg-system | `cnpg-controller-manager-7d4d7f5854-5br77` | 1/1 | Running | 76 | 49d | 10.100.5.6 | wk01 | `<none>` | `<none>` |
| elk | `elasticsearch-master-0` | 1/1 | Running | 0 | 37d | 10.100.3.185 | wk02 | `<none>` | `<none>` |
| elk | `elasticsearch-master-1` | 1/1 | Running | 0 | 35d | 10.100.5.191 | wk01 | `<none>` | `<none>` |
| elk | `elasticsearch-master-2` | 1/1 | Running | 0 | 37d | 10.100.5.234 | wk01 | `<none>` | `<none>` |
| elk | `kibana-kibana-894d6648-qstwd` | 1/1 | Running | 0 | 37d | 10.100.3.148 | wk02 | `<none>` | `<none>` |
| keycloak | `keycloak-0` | 1/1 | Running | 0 | 48d | 10.100.5.4 | wk01 | `<none>` | `<none>` |
| keycloak | `keycloak-1` | 1/1 | Running | 0 | 35d | 10.100.3.219 | wk02 | `<none>` | `<none>` |
| keycloak | `psql-keycloak-1` | 1/1 | Running | 0 | 35d | 10.100.5.32 | wk01 | `<none>` | `<none>` |
| keycloak | `psql-keycloak-2` | 1/1 | Running | 0 | 49d | 10.100.5.70 | wk01 | `<none>` | `<none>` |
| keycloak | `psql-keycloak-3` | 1/1 | Running | 0 | 49d | 10.100.3.200 | wk02 | `<none>` | `<none>` |
| kube-system | `cilium-4qqbf` | 1/1 | Running | 0 | 49d | 172.18.0.51 | cp01 | `<none>` | `<none>` |
| kube-system | `cilium-7dqkx` | 1/1 | Running | 0 | 49d | 172.18.0.61 | wk01 | `<none>` | `<none>` |
| kube-system | `cilium-envoy-6cbrv` | 1/1 | Running | 0 | 49d | 172.18.0.53 | cp03 | `<none>` | `<none>` |
| kube-system | `cilium-envoy-9nrhb` | 1/1 | Running | 0 | 49d | 172.18.0.62 | wk02 | `<none>` | `<none>` |
| kube-system | `cilium-envoy-c5c2d` | 1/1 | Running | 0 | 49d | 172.18.0.61 | wk01 | `<none>` | `<none>` |
| kube-system | `cilium-envoy-dp5fl` | 1/1 | Running | 0 | 49d | 172.18.0.63 | wk03 | `<none>` | `<none>` |
| kube-system | `cilium-envoy-hvs7w` | 1/1 | Running | 0 | 49d | 172.18.0.52 | cp02 | `<none>` | `<none>` |
| kube-system | `cilium-envoy-wdvgz` | 1/1 | Running | 0 | 49d | 172.18.0.51 | cp01 | `<none>` | `<none>` |
| kube-system | `cilium-ftr8g` | 1/1 | Running | 0 | 49d | 172.18.0.53 | cp03 | `<none>` | `<none>` |
| kube-system | `cilium-operator-669f5bbc66-gbh49` | 1/1 | Running | 80 | 49d | 172.18.0.51 | cp01 | `<none>` | `<none>` |
| kube-system | `cilium-p9q9t` | 1/1 | Running | 0 | 49d | 172.18.0.52 | cp02 | `<none>` | `<none>` |
| kube-system | `cilium-sjdhc` | 1/1 | Running | 0 | 49d | 172.18.0.63 | wk03 | `<none>` | `<none>` |
| kube-system | `cilium-zh4zh` | 1/1 | Running | 0 | 49d | 172.18.0.62 | wk02 | `<none>` | `<none>` |
| kube-system | `etcd-cp01` | 1/1 | Running | 0 | 49d | 172.18.0.51 | cp01 | `<none>` | `<none>` |
| kube-system | `etcd-cp02` | 1/1 | Running | 0 | 49d | 172.18.0.52 | cp02 | `<none>` | `<none>` |
| kube-system | `etcd-cp03` | 1/1 | Running | 0 | 49d | 172.18.0.53 | cp03 | `<none>` | `<none>` |
| kube-system | `kube-apiserver-cp01` | 1/1 | Running | 1 | 35d | 172.18.0.51 | cp01 | `<none>` | `<none>` |
| kube-system | `kube-apiserver-cp02` | 1/1 | Running | 1 | 35d | 172.18.0.52 | cp02 | `<none>` | `<none>` |
| kube-system | `kube-apiserver-cp03` | 1/1 | Running | 1 | 35d | 172.18.0.53 | cp03 | `<none>` | `<none>` |
| kube-system | `kube-controller-manager-cp01` | 1/1 | Running | 28 | 49d | 172.18.0.51 | cp01 | `<none>` | `<none>` |
| kube-system | `kube-controller-manager-cp02` | 1/1 | Running | 35 | 49d | 172.18.0.52 | cp02 | `<none>` | `<none>` |
| kube-system | `kube-controller-manager-cp03` | 1/1 | Running | 29 | 49d | 172.18.0.53 | cp03 | `<none>` | `<none>` |
| kube-system | `kube-scheduler-cp01` | 1/1 | Running | 33 | 49d | 172.18.0.51 | cp01 | `<none>` | `<none>` |
| kube-system | `kube-scheduler-cp02` | 1/1 | Running | 26 | 49d | 172.18.0.52 | cp02 | `<none>` | `<none>` |
| kube-system | `kube-scheduler-cp03` | 1/1 | Running | 20 | 49d | 172.18.0.53 | cp03 | `<none>` | `<none>` |
| kube-system | `kube-vip-ds-4mvfl` | 1/1 | Running | 307 | 49d | 172.18.0.52 | cp02 | `<none>` | `<none>` |
| kube-system | `kube-vip-ds-6j2k4` | 1/1 | Running | 305 | 49d | 172.18.0.51 | cp01 | `<none>` | `<none>` |
| kube-system | `kube-vip-ds-frtgv` | 1/1 | Running | 290 | 49d | 172.18.0.53 | cp03 | `<none>` | `<none>` |
| kube-system | `openstack-cinder-csi-controllerplugin-746d568bb4-8gc7p` | 6/6 | Running | 628 | 49d | 10.100.3.142 | wk02 | `<none>` | `<none>` |
| kube-system | `openstack-cinder-csi-nodeplugin-2pmkt` | 3/3 | Running | 0 | 49d | 172.18.0.52 | cp02 | `<none>` | `<none>` |
| kube-system | `openstack-cinder-csi-nodeplugin-2v65w` | 3/3 | Running | 0 | 49d | 172.18.0.63 | wk03 | `<none>` | `<none>` |
| kube-system | `openstack-cinder-csi-nodeplugin-7r8k9` | 3/3 | Running | 0 | 49d | 172.18.0.61 | wk01 | `<none>` | `<none>` |
| kube-system | `openstack-cinder-csi-nodeplugin-8nltk` | 3/3 | Running | 0 | 49d | 172.18.0.51 | cp01 | `<none>` | `<none>` |
| kube-system | `openstack-cinder-csi-nodeplugin-rqlqv` | 3/3 | Running | 0 | 49d | 172.18.0.62 | wk02 | `<none>` | `<none>` |
| kube-system | `openstack-cinder-csi-nodeplugin-slf8x` | 3/3 | Running | 0 | 49d | 172.18.0.53 | cp03 | `<none>` | `<none>` |
| kube-system | `rke2-coredns-rke2-coredns-85d6696775-865ss` | 1/1 | Running | 0 | 49d | 10.100.0.193 | cp01 | `<none>` | `<none>` |
| kube-system | `rke2-coredns-rke2-coredns-85d6696775-jcgrc` | 1/1 | Running | 0 | 49d | 10.100.1.193 | cp02 | `<none>` | `<none>` |
| kube-system | `rke2-coredns-rke2-coredns-autoscaler-665b7f6f86-fqpjt` | 1/1 | Running | 0 | 49d | 10.100.0.171 | cp01 | `<none>` | `<none>` |
| kube-system | `rke2-metrics-server-7c4c577547-6m22k` | 1/1 | Running | 0 | 35d | 10.100.5.221 | wk01 | `<none>` | `<none>` |
| kube-system | `rke2-snapshot-controller-696989ffdd-dlldh` | 1/1 | Running | 158 | 49d | 10.100.5.57 | wk01 | `<none>` | `<none>` |
| mysql-operator | `mysql-operator-868f798d97-qjld7` | 1/1 | Running | 0 | 42d | 10.100.3.159 | wk02 | `<none>` | `<none>` |
| nginx-ingress | `nginx-ingress-69cb797b4d-jvljc` | 1/1 | Running | 0 | 38d | 10.100.3.205 | wk02 | `<none>` | `<none>` |
| sonobuoy | `sonobuoy` | 1/1 | Running | 0 | 35d | 10.100.4.17 | wk03 | `<none>` | `<none>` |

**4.4. Hiện trạng Điểm cuối (Endpoints):**
Endpoints là IP thực tế của các Pod mà Service sẽ chuyển hướng traffic tới.
**Cách kiểm tra:**
```bash
k get endpoints -A -o wide
```
| NAMESPACE | NAME | ENDPOINTS | AGE |
|-----------|------|-----------|-----|
| cnpg-system | `cnpg-webhook-service` | `10.100.5.6:9443` | 49d |
| default | `kubernetes` | `172.18.0.51:6443,172.18.0.52:6443,172.18.0.53:6443` | 49d |
| elk | `elasticsearch-master` | `10.100.3.185:9200,10.100.5.191:9200,10.100.5.234:9200 + 3 more...` | 37d |
| elk | `elasticsearch-master-headless` | `10.100.3.185:9200,10.100.5.191:9200,10.100.5.234:9200 + 3 more...` | 37d |
| elk | `kibana-kibana` | `10.100.3.148:5601` | 37d |
| keycloak | `keycloak` | `10.100.3.219:8080,10.100.5.4:8080` | 49d |
| keycloak | `keycloak-discovery` | `10.100.3.219,10.100.5.4` | 49d |
| keycloak | `psql-keycloak-r` | `10.100.3.200:5432,10.100.5.32:5432,10.100.5.70:5432` | 49d |
| keycloak | `psql-keycloak-ro` | `10.100.3.200:5432,10.100.5.32:5432` | 49d |
| keycloak | `psql-keycloak-rw` | `10.100.5.70:5432` | 49d |
| kube-system | `cilium-envoy` | `172.18.0.51:9964,172.18.0.52:9964,172.18.0.53:9964 + 3 more...` | 49d |
| kube-system | `hubble-peer` | `172.18.0.51:4244,172.18.0.52:4244,172.18.0.53:4244 + 3 more...` | 49d |
| kube-system | `rke2-coredns-rke2-coredns` | `10.100.0.193:53,10.100.1.193:53,10.100.0.193:53 + 1 more...` | 49d |
| kube-system | `rke2-metrics-server` | `10.100.5.221:10250` | 49d |
| nginx-ingress | `nginx-ingress` | `10.100.3.205:443,10.100.3.205:80` | 49d |
| sonobuoy | `sonobuoy-aggregator` | `10.100.4.17:8080` | 35d |
