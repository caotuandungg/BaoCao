# Nghiên cứu chuyên sâu về Apache Kafka

## 1. Mở bài: "Mở rộng" (Scale) cái gì trong Kafka?

Khi đứng trước bài toán "mở rộng", câu hỏi thường được đặt ra là: *"Hệ thống chạy bình thường thì mở rộng cái gì?"*. Trong Kafka, "mở rộng" (Scaling) giải quyết 3 nút thắt chính khi lưu lượng dữ liệu (traffic) tăng vọt.

Hãy tưởng tượng Kafka là một **Bưu điện khổng lồ**.

- **Thêm Broker (Mở rộng theo chiều ngang - Scale Out):** Khi lượng bưu kiện (messages) gửi đến bưu điện quá nhiều khiến nhà kho đầy hoặc băng thông mạng bị nghẽn, bạn xây thêm các chi nhánh bưu điện mới (Thêm Broker vào cụm).
- **Thêm Partition (Mở rộng luồng xử lý):** Trong một kho, thay vì có 1 cửa nhận/trả đồ, bạn đập tường xây thành 10 cửa. Dữ liệu của một chủ đề (Topic) được chia nhỏ thành nhiều phần (Partitions) để nhiều máy có thể cùng ghi/đọc song song.
- **Thêm Consumer (Mở rộng khả năng tiêu thụ):** Nếu bưu điện nhận được 10.000 bưu kiện/giây, nhưng đơn vị giao hàng (Consumer) chỉ giao được 1.000 bưu kiện/giây, hàng sẽ tồn đọng. Bạn cần huy động thêm nhiều shipper (Consumer Group) để xử lý song song.

---

## 2. High Availability (HA) trong Kafka

Kafka được thiết kế để "không bao giờ chết" và "không bao giờ mất dữ liệu" thông qua hai cơ chế cốt lõi:

### 2.1. Replication Factor (Nhân bản dữ liệu)
Mọi tin nhắn ghi vào Kafka đều có thể được nhân bản ra $N$ máy (Brokers) khác nhau. 
- Nếu `Replication Factor = 3`, một tin nhắn gửi tới Kafka sẽ được lưu trữ ở 3 máy chủ khác nhau. 
- Mất điện đứt cáp 1 hoặc 2 máy, máy thứ 3 vẫn có dữ liệu để phục vụ.

### 2.2. Cơ chế Leader - Follower
Trong 3 bản sao của 1 Partition, sẽ có 1 máy làm **Leader** (Trưởng nhóm) và 2 máy làm **Follower** (Đệ tử).
- Mọi thao tác Ghi/Đọc từ ứng dụng đều nói chuyện với Leader.
- Các Follower âm thầm chép dữ liệu từ Leader.
- **Nếu Leader bị hỏng (Server chết):** Cụm Kafka (thông qua Zookeeper hoặc KRaft) sẽ ngay lập tức tổ chức một cuộc "bầu cử" trong tích tắc để nâng một Follower lên làm Leader mới. Hạ tầng ứng dụng không hề hay biết sự gián đoạn này.

---

## 3. Các hướng triển khai Kafka (Deployment Architectures)

### Cấp độ 1: Triển khai truyền thống (Bare-metal hoặc Virtual Machines)
Cài đặt Kafka và Zookeeper trực tiếp lên các máy chủ Linux ảo (VMWare) hoặc vật lý.
- **Ưu điểm:**
  - Hiệu năng I/O ổ cứng và mạng cao nhất (không có lớp ảo hóa K8s cản trở).
  - Dễ cấu hình và điều chỉnh tham số hạt nhân (kernel) của OS hệ điều hành để tối ưu bộ nhớ.
- **Nhược điểm:**
  - Khó tự động hóa. Nếu cần thêm 1 Broker, bạn phải tự cài HĐH, cấu hình mạng, cấu hình file Kafka.
  - Tốn nhân lực bảo trì (quản trị hệ điều hành, vá lỗi bảo mật).

### Cấp độ 2: Triển khai hiện đại trên Kubernetes (Dùng Operator như Strimzi)
Triển khai nguyên một cụm Kafka trong K8s. Đây đang là xu hướng kiến trúc hiện đại.
- **Ưu điểm:**
  - Quản trị bằng code dễ dàng (Infrastructure as Code). Cần thêm node chỉ cần đổi `replicas: 3` thành `replicas: 5`.
  - Operator (như Strimzi) giống như một con "robot quản trị viên" tự động giám sát sức khỏe, tự động cấp phát ổ cứng (PVC), tự tạo Load Balancer.
  - Đồng bộ hệ sinh thái giám sát (Prometheus/Grafana) với các ứng dụng khác trong K8s.
- **Nhược điểm:**
  - Khó triển khai với người chưa rành Kubernetes.
  - Phải quản lý cực kỳ cẩn thận ổ cứng ảo (Persistent Volumes, Storage Class) vì Kafka là hệ thống dạng Stateful.

#### **Quy trình triển khai chi tiết (Dùng Helm & Operator):**
1. **Cài đặt Operator:** Trước tiên, ta cần cài đặt "Bộ não" quản trị vào Cluster.
   ```powershell
   # Thêm Repo Strimzi
   helm repo add strimzi https://strimzi.io/charts/
   # Cài đặt Operator vào namespace 'kafka'
   helm install strimzi-operator strimzi/strimzi-kafka-operator --namespace kafka --create-namespace
   ```
2. **Triển khai Cụm Kafka:** Dùng file YAML (như `Kafka_Official_K8s_Config.yaml`) để yêu cầu Operator tạo cụm.
   ```powershell
   kubectl apply -f Kafka_Official_K8s_Config.yaml -n kafka
   ```
3. **Kiểm tra sức khỏe:** Đợi vài phút để Operator thực hiện việc cấp phát ổ cứng và khởi động các Pod.
   ```powershell
   # Kiểm tra trạng thái tài nguyên Kafka
   kubectl get kafka -n kafka
   # Theo dõi các Pod đang lên (3 Kafka + 3 Zookeeper)
   kubectl get pods -n kafka -w
   ```

#### **Các bước sau cài đặt (Post-Installation):**
Sau khi cụm Kafka đã Running, bạn cần thực hiện 2 bước quan trọng sau để có thể bắt đầu sử dụng:

1. **Tạo Topic (Kênh dữ liệu):** Trong Kafka, dữ liệu được phân loại theo Topic. Với Strimzi, bạn tạo Topic bằng một file YAML:
   ```yaml
   # my-topic.yaml
   apiVersion: kafka.strimzi.io/v1beta2
   kind: KafkaTopic
   metadata:
     name: dung-logs-topic
     labels:
       strimzi.io/cluster: my-cluster
   spec:
     partitions: 3
     replicas: 3
   ```
   *Lệnh: `kubectl apply -f my-topic.yaml -n kafka`*

2. **Cấu hình ứng dụng Kết nối:**
   * **Địa chỉ kết nối (Bootstrap Server):** `my-cluster-kafka-bootstrap.kafka.svc:9092`
   * Bạn hỗ trợ các ứng dụng (như Fluent Bit) bằng cách điền địa chỉ trên vào phần cấu hình `Output`. Lúc này, luồng dữ liệu mới thực sự được đẩy vào Kafka.

### Cấp độ 3: Dùng Kafka Dịch vụ (Managed/Cloud Kafka)
Sử dụng Confluent Cloud, Amazon MSK (Managed Streaming for Apache Kafka) hoặc Aiven.
- **Ưu điểm:**
  - "Zero-ops" (Không lo bảo trì). Tổ chức chỉ việc trả chi phí sử dụng, phần hạ tầng, sao lưu, nâng cấp do nhà cung cấp (Google/Amazon) đảm nhiệm.
  - Scale lên xuống chỉ sau 1 click chuột.
- **Nhược điểm:**
  - Chi phí cực kỳ đắt đỏ ở Scale lớn.
  - Dữ liệu đi ra khỏi mạng nội bộ (Data Egress) sẽ tốn rất nhiều tiền băng thông.

---

## 4. Các tình huống sử dụng điển hình (Use Cases/Scenarios)

### Tình huống 1: Bộ đệm giảm tải cho Hệ thống Log (Log Aggregation Pipeline)
*(Đặc biệt liên quan đến hệ thống bạn đang làm: Ứng dụng -> Fluent Bit -> Kafka -> Elasticsearch)*
- **Bài toán:** Ngày hội mua sắm (Flash Sale), log ứng dụng sinh ra x100 lần. Elasticsearch lưu không kịp, sập chùm.
- **Giải pháp Kafka:** Kafka làm một bãi đỗ xe trung chuyển. Log sinh ra đẩy thẳng vào Kafka cực nhanh. Elasticsearch cứ túc tắc mà lấy từ Kafka về xử lý. Dù Elasticsearch sập bảo trì nửa ngày, log nằm trong Kafka vẫn còn nguyên.

### Tình huống 2: Kiến trúc Hướng Sự Kiến (Event-Driven Microservices)
- **Bài toán:** Người dùng bấm "Đặt hàng". Dịch vụ Đơn hàng, Dịch vụ Thanh toán, Dịch vụ Kho, Dịch vụ Email phải đồng thời được kích hoạt chung một lúc.
- **Giải pháp Kafka:** Dịch vụ A chỉ cần hét lên vào Kafka: "Có đơn hàng mới!". Các Dịch vụ B, C, D đều đang lắng nghe (Consume) Kafka và sẽ tự nhận thông điệp về xử lý độc lập mà không cần kết nối gạch chéo trực tiếp với nhau (Decoupling).

### Tình huống 3: Đồng bộ luồng (Stream Processing) thời gian thực
- **Bài toán:** Các ngân hàng cần xử lý gian lận thẻ tín dụng. Họ phải phân tích 10.000 giao dịch/giây để xem có ai quẹt thẻ ở 2 quốc gia cách nhau 10 phút hay không.
- **Giải pháp Kafka:** Sử dụng **Kafka Streams** để đọc luồng giao dịch, filter, kết hợp dữ liệu lịch sử ngay trong lúc dữ liệu đang chảy qua, xuất ra cảnh báo vi phạm trước khi giao dịch kịp hoàn tất.

---

## Tóm lược cho Báo Cáo của bạn:
Khi được hỏi về Kafka, cốt lõi lớn nhất bạn cần trình bày gồm 2 điểm:
1. Nó đóng vai trò là một cái **Phao cứu sinh (Buffer)** hấp thụ toàn bộ "cú sốc" lưu lượng dữ liệu tăng đột biến để bảo vệ các hệ thống đích (Database, Elasticsearch).
2. Tách rời sự lệ thuộc (Decoupling): Thay vì dịch vụ A gọi API sang B, giờ A cứ quăng lên Kafka, B rảnh lúc nào thì bốc về xử lý. Máy A và B không cần biết mặt nhau.

## 5. Các thành phần cấu hình trong Kafka (Configuration Components)

Dựa trên tài liệu chính thức của Apache Kafka, các cấu hình được chia thành nhiều nhóm khác nhau. Không phải tất cả đều bắt buộc, tùy vào vai trò của bạn trong hệ thống mà bạn sẽ cần quan tâm đến các nhóm khác nhau:

### 5.1. Nhóm Cấu hình Bắt buộc (Core Configs)
Đây là những thành phần "sống còn" để một cụm Kafka có thể chạy và truyền nhận dữ liệu:
- **Broker Configs (Bắt buộc):** Cấu hình cho các máy chủ Kafka. Nó định nghĩa ID của máy chủ, cổng kết nối, nơi lưu trữ dữ liệu và cách các máy chủ nói chuyện với nhau.
- **Producer Configs (Bắt buộc cho ứng dụng Gửi):** Dành cho các ứng dụng đẩy dữ liệu vào Kafka (như Fluent Bit). Nó định nghĩa việc nén dữ liệu, cách xác nhận (ACKs) đã gửi thành công hay chưa.
- **Consumer Configs (Bắt buộc cho ứng dụng Nhận):** Dành cho các ứng dụng đọc dữ liệu từ Kafka. Nó định nghĩa cách đọc từ đâu, tốc độ đọc và cách quản lý vị trí đã đọc (Offset).
- **Admin Configs:** Dành cho các công cụ quản trị để tạo Topic, thay đổi cấu hình mà không cần khởi động lại Server.

### 5.2. Nhóm Cấu hình Tính năng & Mở rộng (Optional/Ecosystem)
Đây là các thành phần bổ trợ, chỉ cần thiết khi bạn sử dụng các tính năng cao cấp hoặc công cụ đi kèm:
- **Topic Configs:** Dùng để ghi đè (Override) các thiết lập mặc định của Broker cho từng Topic cụ thể (ví dụ: Topic A giữ log 7 ngày, Topic B chỉ giữ 1 ngày).
- **Kafka Connect Configs:** Dùng khi bạn sử dụng Kafka Connect để tự động đổ dữ liệu từ Database (MySQL, MongoDB) vào Kafka hoặc ngược lại.
- **Kafka Streams Configs:** Dùng khi bạn viết các ứng dụng xử lý luồng dữ liệu thời gian thực (như tính tổng, lọc dữ liệu ngay khi đang chảy qua Kafka).
- **MirrorMaker Configs:** Dùng để sao chép dữ liệu giữa hai cụm Kafka khác nhau (ví dụ: chép dữ liệu từ Cluster ở Việt Nam sang Cluster ở Mỹ).
- **Tiered Storage Configs:** Tính năng mới giúp đẩy các dữ liệu log cũ từ ổ cứng Server lên các kho lưu trữ rẻ tiền hơn như Amazon S3 hay Google Cloud Storage.
- **Configuration Providers:** Dùng để nạp các cấu hình bảo mật hoặc mật khẩu từ các nguồn bên ngoài (như Vault hoặc Environment Variables) thay vì ghi trực tiếp vào file.

---

## 6. Tài liệu tham khảo chính thức

Để nghiên cứu sâu hơn và cập nhật các tính năng mới nhất (như KRaft), bạn có thể truy cập:
1. **Apache Kafka Documentation:** [https://kafka.apache.org/documentation/](https://kafka.apache.org/documentation/) - Tài liệu gốc của tổ chức Apache.
2. **Confluent Documentation:** [https://docs.confluent.io/](https://docs.confluent.io/) - Tài liệu hướng dẫn triển khai thực tế cho doanh nghiệp.
3. **Kafka Tutorials:** [https://developer.confluent.io/learn/](https://developer.confluent.io/learn/) - Các khóa học và hướng dẫn thực hành miễn phí từ cơ bản đến nâng cao.
