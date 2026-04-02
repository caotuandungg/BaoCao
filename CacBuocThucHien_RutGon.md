# Các Bước Thực Hiện Thực Tế (Actionable Steps)

Dựa trên hiện trạng hạ tầng đã có sẵn Elasticsearch và Kibana, quy trình thực hiện chỉ tập trung vào việc cài đặt thành phần còn thiếu (Fluent Bit) và cấu hình hiển thị. Dưới đây là tuần tự các bước cấu hình trực tiếp trên Terminal.

---

### Bước 1: Khởi tạo File Cấu Hình
Tạo tệp văn bản mang tên `fluent-bit-values.yaml` tại thư mục làm việc hiện tại và dán đoạn mã sau vào:

```yaml
kind: DaemonSet # Đảm bảo mỗi máy chủ (Node) trong cụm đều chạy chính xác 1 Pod thu gom log
hostNetwork: true # Cho phép Agent dùng mạng vật lý của Node, tránh bị chặn bởi mạng ảo CNI (Cilium)
dnsPolicy: ClusterFirstWithHostNet # Đảm bảo phân giải tên miền chuẩn khi dùng HostNetwork
config:
  service: |
    [SERVICE]
        Flush         1             # Đẩy log về đích mỗi 1 giây (độ trễ gần như realtime)
        Log_Level     info          # Mức độ log hệ thống của chính Fluent Bit
        Daemon        off           # Không chạy ngầm để Kubernetes tiện quản lý vòng đời
        Parsers_File  parsers.conf  # Tập hợp file chứa các quy tắc phân tách log 
        HTTP_Server   On            # Bật máy chủ HTTP nội bộ 
        HTTP_Listen   0.0.0.0       # Thiết lập dải IP lắng nghe (Healthcheck)
        HTTP_Port     2020          # Cổng giao tiếp theo dõi sức khỏe (Metrics)
  inputs: |
    [INPUT]
        Name              tail      # Cơ chế đọc nối đuôi (tail -f) nội dung log mới phát sinh
        Path              /var/log/containers/*.log # Thư mục đích chứa toàn bộ log của các Pod trên Node hiện tại
        Read_from_Head    On        # Khi Agent mới chạy, sẽ đọc lại log từ thuở sơ khai trong giới hạn đĩa để vét hết dữ kiện
        Parser            docker    # Cú pháp Format mặc định
        Tag               kube.*    # Đánh dán nhãn toàn bộ lượng dữ liệu này là 'kube.*' để dễ lọc ở Filter
        Refresh_Interval  5         # Định kỳ 5 giây rà soát ổ cứng xem có file log của Ứng dụng mới nào vừa ra log không
        Mem_Buf_Limit     50MB      # Giới hạn RAM tối đa của agent fluent bit trên mỗi Node
        Skip_Long_Lines   On        # Tự động chối từ thu thập những dòng log quá dài
  filters: |
    [FILTER]
        Name                kubernetes
        Match               kube.*
        Merge_Log           On             # Cố gắng hợp nhất các chuỗi JSON lồng nhau
        K8S-Logging.Parser  On             # Hỗ trợ phân tích cú pháp từ Label của Pod
        K8S-Logging.Exclude Off            # Thu thập log của tất cả các Pod , ko quan tâm có nhãn hay không
  outputs: |
    [OUTPUT]
        Name            es          # Kích hoạt module gửi đầu ra tới Elasticsearch Backend
        Match           *           # Đẩy toàn bộ dữ liệu log có trong khoang (bất chấp Tag) đi
        Host            elasticsearch-master.elk.svc.cluster.local # Địa chỉ IP dịch vụ nội bộ (FQDN DNS của K8s)
        Port            9200        # Cổng gọi REST API nhập liệu gốc của Elasticsearch 
        HTTP_User       elastic     # Tài khoản quyền cao nhất của ES
        HTTP_Passwd     1qK@B5mQ    # Password khớp với Elasticsearch Cluster
        Buffer_Size     False       # Tắt giới hạn RAM bắt nhận phản hồi (Tránh bị kẹt lỗi cannot increase buffer 512KB)
        Logstash_Format On          # Sinh ra tệp dữ liệu lưu trữ dưới chuẩn theo khung ngày (VD: fluent-bit-YYYY.MM.DD)
        Logstash_Prefix fluent-bit  # Đặt tiền tố index name (Tức là trên Kibana sẽ truy hồi theo chữ fluent-bit-*)
        Retry_Limit     5           # Chỉ thử lại 5 lần nếu lỗi thay vì thử vĩnh viễn (Tránh kẹt cục bộ vĩnh viễn)
        Trace_Error     On          # [QUAN TRỌNG] Bật chế độ in chi tiết lỗi nếu Elasticsearch từ chối nhận log
        Replace_Dots    On          # Khắc phục dứt điểm lỗi Mapper Parsing Exception khi Label K8s chứa dấu chấm
        TLS             On          # Mã hóa toàn trình giao thức đường dây HTTPS để đảm bảo bảo mật nội bộ
        TLS.Verify      Off         # Skip bước chứng thực Certificate SSL (Vì chúng ta dùng Trust nội mạng Self-Signed)
        Suppress_Type_Name On       # Cắt bỏ mapping tham chiếu "_type", vì Elasticsearch version 8.x CẤM sử dụng "_type"
rbac:
  create: true       # Cấp quyền cho Fluent-bit Agent được phép
  nodeAccess: true   # Rà soát tài nguyên File Log từ cấp độ truy cập Host máy đích
```

### Bước 2: Thực Thi Lệnh Cài Đặt (Helm)
Sao chép và chạy lần lượt 3 lệnh sau đây tại cửa sổ dòng lệnh (Terminal):

```bash
# 1. Khai báo nguồn phần mềm của Fluent Bit
helm repo add fluent https://fluent.github.io/helm-charts

# 2. Cập nhật dữ liệu từ nguồn
helm repo update

# 3. Kích hoạt tiến trình cài đặt với tệp cấu hình vừa tạo
helm install fluent-bit fluent/fluent-bit --namespace elk -f fluent-bit-values.yaml
```

### Bước 3: Xác Nhận Trạng Thái Triển Khai
Giám sát việc cấp phát tài nguyên bằng lệnh sau (đợi đến khi xuất hiện trạng thái `Running` là đã hoàn tất phần Backend):

```bash
kubectl get pods -n elk -l app.kubernetes.io/name=fluent-bit
```

### Bước 4: Mở Liên Kết Và Thiết Lập Giao Diện
Tiếp tục sao chép lệnh sau để mở luồng kết nối từ máy chủ cụm về máy cá nhân:

```bash
kubectl port-forward svc/kibana-kibana 5601:5601 -n elk
```

Sau khi Terminal báo luồng mở thành công:
1. Mở trình duyệt web, truy cập: `http://localhost:5601`
2. Truy cập **Management -> Stack Management -> Data Views**.
3. Bấm **Create data view**.
4. Ở mục *Index pattern*, điền chính xác: `fluent-bit-*`
5. Ở mục *Timestamp field*, chọn `@timestamp`.
6. Chọn **Save data view** để hoàn tất.

Hệ thống đã sẵn sàng tìm kiếm log từ menu **Analytics -> Discover**.

---

### Phân Tích Kỹ Thuật: Vì sao cần cấu hình mới?

Việc triển khai ban đầu gặp lỗi do cấu hình chưa tương thích hoàn toàn với môi trường thực tế của cụm RKE2 và phiên bản Elasticsearch 8.x có bảo mật. Dưới đây là các điểm mấu chốt đã được chỉnh sửa:

1. **Xác thực và Bảo mật (HTTPS/Auth):** Hệ thống ELK hiện tại yêu cầu kết nối qua giao thức mã hóa (HTTPS) và thông tin đăng nhập. Cấu hình mới đã bật `TLS On` và bổ sung `HTTP_User/HTTP_Passwd`.
2. **Từ khóa cấu hình chính xác:** Plugin Elasticsearch của Fluent Bit yêu cầu tham số mật khẩu là `HTTP_Passwd` (thay vì `HTTP_Pass`).
3. **Tránh nghẽn mạng API (Metadata Timeout):** Cấu hình cũ cố gắng kết nối tới Kube API qua địa chỉ tĩnh và chứng chỉ bên ngoài, dẫn đến lỗi Timeout trên mạng nội bộ. Việc loại bỏ các dòng này giúp Fluent Bit tự động dùng biến môi trường nội bộ ổn định hơn.
4. **Tương thích Elasticsearch 8.x:** Thêm `Suppress_Type_Name On` để loại bỏ thẻ `_type` (vốn đã bị cấm trên các phiên bản ES mới), giúp dữ liệu được chấp nhận và lưu trữ.
5. **Thu thập dữ liệu lịch sử:** `Read_from_Head On` ép hệ thống đọc lại toàn bộ log cũ trong ổ đĩa, thay vì chỉ đợi log mới phát sinh.

---

### Hướng dẫn sử dụng và tìm kiếm Log (Dành cho báo cáo)

Để thực hiện tìm kiếm và phân tích log sau khi đã cài đặt thành công, kỹ sư thực hiện theo các bước sau:

#### 1. Truy cập giao diện Discover
* Tại menu bên trái (biểu tượng 3 gạch ngang), chọn **Analytics** -> **Discover**.
* Tại ô chọn **Data View** (phía trên bên trái), chọn `fluent-bit-logs` vừa tạo.

#### 2. Lọc dữ liệu theo nhu cầu
* **Theo thời gian:** Sử dụng bộ lọc thời gian ở góc trên bên phải (mặc định là *Last 15 minutes*) để xem log cũ hơn (ví dụ: *Last 24 hours*).
* **Theo Ứng dụng (Namespace/Pod):** 
    * Nhấn vào **+ Add filter**.
    * Chọn Field: `kubernetes.namespace_name` và nhập giá trị (ví dụ: `argocd`).
    * Hoặc chọn Field: `kubernetes.pod_name` để xem cụ thể một Pod.
* **Theo từ khóa:** Gõ trực tiếp nội dung cần tìm vào thanh **Search** (ví dụ: `error`, `404`, `connection failed`).

#### 3. Tùy chỉnh cột hiển thị
Trong danh sách **Available fields** ở bên trái, hãy nhấn dấu **(+)** cạnh các trường sau để bảng log dễ đọc hơn:
* `log`: Nội dung tin nhắn log thực tế.
* `kubernetes.pod_name`: Tên Pod phát sinh log.
* `kubernetes.namespace_name`: Không gian tên chứa Pod.

#### 4. Xem chi tiết log
Nhấn vào biểu tượng mở rộng (mũi tên hướng xuống hoặc nút **>** ) ở đầu mỗi dòng log để xem toàn bộ metadata liên quan (Node, IP, Images, Time...).

---

## Phần Nâng Cao: Triển Khai Kibana Thứ 2 Độc Lập

Phần này hướng dẫn cách tách biệt hoàn toàn không gian Kibana cho hệ thống Log riêng, không ảnh hưởng đến con Kibana hiện có của cụm, nhưng vẫn dùng chung kho Elasticsearch.

**Nguyên lý hoạt động:**
- Kibana cũ và Kibana mới cùng kết nối vào 1 Elasticsearch.
- Tách biệt bằng tham số `kibanaIndex: ".kibana_logging"` — đây là vùng lưu cấu hình riêng trong Elasticsearch. Con Kibana cũ dùng `.kibana`, con mới dùng tên khác nên **không bao giờ đè lên nhau**.

### Bước 1: Tạo file cấu hình cho Kibana mới

Tạo file `kibana-logging-values.yaml`:

```yaml
elasticsearchHosts: "https://elasticsearch-master:9200"

kibanaConfig:
  kibana.yml: |
    elasticsearch.ssl.verificationMode: none

service:
  port: 5601

replicas: 1
```

# Bước 2: Tạo Namespace mới và cài đặt

```bash
# 1. Tạo namespace riêng (nếu chưa có)
kubectl create namespace elk-dung

# 2. Thêm repo Elastic (chỉ cần chạy 1 lần)
helm repo add elastic https://helm.elastic.co
helm repo update

# 3. Cài Kibana với tên release "kibana-dung-logging" vào namespace "elk-dung"
helm install kibana-dung-logging elastic/kibana --namespace elk-dung -f kibana-logging-values.yaml
```

### Bước 3: Kiểm tra Pod đã chạy chưa

```bash
kubectl get pods -n elk-dung -l app=kibana-dung-logging
```

Chờ đến khi cột `READY` hiện `1/1` và `STATUS` là `Running`.

### Bước 4: Mở trình duyệt vào con Kibana mới

Vì con Kibana mới chạy trên namespace khác, bạn mở một cửa sổ Terminal mới và chạy lệnh port-forward với **port khác** (ví dụ: 5602 để không trùng với con cũ đang chạy ở 5601):

```bash
kubectl port-forward svc/kibana-dung-logging-kibana 5602:5601 -n elk-dung
```

Sau đó mở trình duyệt, vào địa chỉ: **`http://localhost:5602`**

Đăng nhập bằng tài khoản `elastic` / `1qK@B5mQ`.

### Bước 5: Khai báo Data View trên Kibana mới

Màn hình sẽ trắng tinh (vì `kibana.index` mới, chưa có cấu hình gì). Bạn chỉ cần:
1. Vào **Management -> Stack Management -> Data Views**.
2. Bấm **Create data view**.
3. Điền Index pattern: `fluent-bit-*`.
4. Chọn Timestamp field: `@timestamp`.
5. Bấm **Save data view**.

Toàn bộ log từ Fluent Bit sẽ xuất hiện ngay lập tức vì log vẫn đang được lưu trong kho Elasticsearch chung!

---

## VII. Cấu Hình Parser Nâng Cao (Xử lý Format Log)

Để biến log văn bản thô thành dạng có cấu trúc, bạn cần khai báo các `[PARSER]` trong Fluent Bit. Dưới đây là 2 ví dụ cấu hình thường dùng nhất:

### 1. Parser cho Nginx (Web Server)
Giúp tách rời các trường: IP, Method, Path, Status, Latency...

**Cấu hình bổ sung vào `fluent-bit-values.yaml`:**
```yaml
config:
  customParsers: |
    [PARSER]
        Name   nginx_custom
        Format regex
        Regex  ^(?<remote>[^ ]*) (?<host>[^ ]*) (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)")?$
        Time_Key time
        Time_Format %d/%b/%Y:%H:%M:%S %z
```

### 2. Parser cho Java (Xử lý Log nhiều dòng - Multiline)
Khi ứng dụng Java bị lỗi, log sẽ in ra hàng chục dòng Stacktrace. Nếu không có Parser này, Kibana sẽ coi mỗi dòng đó là một bản dịch rời rạc, làm cho việc tìm kiếm cực kỳ khó khăn.

**Cấu hình xử lý đa dòng:**
```yaml
config:
  service: |
    [SERVICE]
        Parsers_File custom_parsers.conf

  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        Multiline         On
        Parser_Firstline  java_multiline

  customParsers: |
    [PARSER]
        Name        java_multiline
        Format      regex
        Regex       /^\[(?<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (?<level>[A-Z]+) (?<message>.*)/
```

---

## VIII. Các Lỗi Đã Gặp Khi Cài Kibana Mới Vào Namespace `elk`


> Ghi chép lại các lỗi xương máu để tránh lặp lại trong các lần cài đặt sau.

---

### Lỗi 1: `timed out waiting for the condition`
**Nguyên nhân:** Helm mặc định chỉ chờ 5 phút. Nếu cụm kéo image Kibana chậm (image ~1GB), hook pre-install sẽ timeout trước khi Pod kịp khởi động.
**Cách fix:** Thêm `--timeout 10m` vào lệnh helm.

---

### Lỗi 2: Lỗi thiếu Secret TLS (FailedMount)
**Nguyên nhân:** Cố gắng triển khai Kibana vào một namespace khác (ví dụ `elk-dung`) trong khi Elasticsearch đang ở namespace `elk`. Secret TLS không được chia sẻ xuyên namespace.
**Cách fix:** Cài Kibana mới vào **cùng namespace `elk`** để tái sử dụng Secret TLS có sẵn của Elasticsearch.

---

### Lỗi 3: Lỗi Kẹt Hook (`configmap ... already exists`)
**Nguyên nhân:** Lệnh cài đặt Helm trước đó bị lỗi hoặc timeout giữa chừng, để lại các tài nguyên rác của Hook (ConfigMap, Role, ServiceAccount) cản trở lần cài đặt tiếp theo.
**Cách fix:** Trước khi cài lại, phải dọn dẹp sạch bằng lệnh:
```powershell
kubectl delete configmap kibana-dung-kibana-helm-scripts -n elk --ignore-not-found
kubectl delete serviceaccounts pre-install-kibana-dung-kibana -n elk --ignore-not-found
kubectl delete role pre-install-kibana-dung-kibana -n elk --ignore-not-found
kubectl delete rolebinding pre-install-kibana-dung-kibana -n elk --ignore-not-found
```

---

### Lỗi 4: Lỗi cấm dùng tài khoản `elastic` (`value of "elastic" is forbidden`)
**Nguyên nhân:** Kibana 8.x không cho phép dùng tài khoản `elastic` (superuser) để kết nối (bằng biến môi trường `ELASTICSEARCH_USERNAME/PASSWORD`), bắt buộc phải dùng Service Account Token.
**Cách fix:** Gỡ bỏ các biến truyền Username/Password ra khỏi file cấu hình của Kibana.

---

### Lỗi 5: Lỗi xác thực Token Elasticsearch (`failed to authenticate service account [elastic/kibana] with token name [...]`)
**Nguyên nhân:** Do cố tình dùng cờ `--no-hooks` để ép Helm bỏ qua lỗi số 3, dẫn đến việc Helm không gọi được API của Elasticsearch để tự sinh ra Token cho con Kibana mới. Dù có ép dùng Token của Kibana cũ thông qua `extraEnvs` thì Elasticsearch vẫn từ chối phiên bản Token không khớp tên.
**Cách fix Tuyệt Đối:** Xóa hoàn toàn bản cài đặt lỗi (`helm uninstall`). Quét sạch các tài nguyên rác như Lỗi 3. Sau đó để Helm tự chạy bình thường (không dùng `--no-hooks`), Helm sẽ tự động hook vào Elasticsearch và xin được Token cực kỳ mượt mà.

---

### Lỗi 6: Lỗi "Sai tài khoản hoặc mật khẩu" (Cookie Session Clash)
**Nguyên nhân:** Sau khi Kibana mới trỏ thành công vào hệ thống và chạy port-forward ở `localhost:5602`, bạn gõ đúng `elastic` và mật khẩu nhưng Kibana vẫn báo sai. Lý do là trình duyệt lưu Session Cookie theo chữ `localhost`, vô tình đẩy cái Session của con Kibana gốc (5601) sang con Kibana mới (5602) dẫn đến không thể giải mã.
**Cách fix:** Mở Tab Trình Duyệt Ẩn Danh (Incognito/Private Browsing - `Ctrl+Shift+N`) và truy cập `http://localhost:5602`. Tách biệt hoàn toàn Cookie là sẽ đăng nhập thành công ngay lập tức!

---

### CẤU HÌNH FINAL HOẠT ĐỘNG HOÀN HẢO

File `kibana-logging-values.yaml`:
```yaml
elasticsearchHosts: "https://elasticsearch-master:9200"

kibanaConfig:
  kibana.yml: |
    elasticsearch.ssl.verificationMode: none

service:
  port: 5601

replicas: 1
```

**Bộ lệnh cài đặt chuẩn:**
```powershell
# 1. Dọn rác đề phòng (nếu đã từng cài lỗi)
kubectl delete configmap kibana-dung-kibana-helm-scripts -n elk --ignore-not-found
kubectl delete serviceaccounts pre-install-kibana-dung-kibana -n elk --ignore-not-found
kubectl delete role pre-install-kibana-dung-kibana -n elk --ignore-not-found
kubectl delete rolebinding pre-install-kibana-dung-kibana -n elk --ignore-not-found
kubectl delete secret kibana-dung-kibana-es-token -n elk --ignore-not-found

# 2. Bắt đầu Cài đặt
helm install kibana-dung elastic/kibana --namespace elk -f kibana-logging-values.yaml --timeout 10m

# 3. Mở port (mở trên Terminal mới sau khi Pod báo Running)
kubectl port-forward svc/kibana-dung-kibana 5602:5601 -n elk
```
