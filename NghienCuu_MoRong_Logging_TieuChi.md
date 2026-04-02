# Báo Cáo Nghiên Cứu Chuyên Sâu: Mở Rộng Hệ Thống Logging

Tài liệu này giải quyết 3 yêu cầu nghiên cứu nâng cao về việc mở rộng và chuẩn hóa hệ thống log, không chỉ gói gọn trong Kubernetes mà còn mở rộng ra toàn bộ hạ tầng công nghệ.

---

## 1. Xử Lý Format Log Từ Các Hệ Thống Khác Nhau
> *"Log từ Pod, log System, log Nginx, Java Stacktrace... mỗi cái một kiểu, làm sao để Kibana hiểu được?"*

Bản chất của các dòng log là các chuỗi văn bản (Plain Text) không có cấu trúc. Để Kibana có thể tìm kiếm thông minh được (ví dụ tìm `status_code: 500`), ta phải biến các chuỗi văn bản lộn xộn này thành một chuẩn chung (thường là định dạng JSON). 

Trong Fluent Bit, công việc này do **Parser (Bộ phân tích cú pháp)** đảm nhiệm.

### Các loại định dạng (Format) thường gặp:
*   **Log K8s Pod (Docker/Containerd):** Thường đã được gói sẵn trong JSON (có chứa thông tin `time`, `stream`, `log`).
*   **Log System (Syslog / Journald):** Thường có dạng: `Oct 11 22:14:15 mymachine su: 'su root' failed...`
*   **Log Web Server (Nginx/Apache):** Thường có dạng: `127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326`
*   **Log Ứng dụng (Java/NodeJS):** Có thể là nhiều dòng dính liền nhau (Multiline) như Stacktrace lỗi.

### Cách xử lý:
Fluent Bit cho phép định nghĩa các `[PARSER]` bằng **Regex (Biểu thức chính quy)**. Bạn sẽ cấu hình Fluent Bit nhận diện xem log thuộc loại nào và gọi đúng Parser để "bóc tách" nó thành các cột (Fields) riêng biệt trước khi gởi đi.

Ví dụ bóc tách log Nginx:
```text
(Văn bản thô)  ▶️ [PARSER Nginx] ▶️ (JSON có cấu trúc: IP, Method, Status...)
```
Lợi ích: Sau khi phân tích, khi lên Kibana, thay vì bạn phải gõ chữ tìm toàn văn, bạn có thế gõ: `method: GET AND status: 200` rất dễ dàng.

---

## 2. Xử Lý Tập Trung Log (Centralized Logging)
> *"Xử lý tập trung nghĩa là gì?"*

Hãy tưởng tượng công cụ của bạn có:
- 10 máy chủ (Node) chạy Kubernetes.
- 5 máy ảo (VM) chạy Database kiểu cũ.
- 2 thiết bị mạng (Switch/Router).

Nếu một ngày hệ thống bị lỗi, bạn không thể SSH gõ lệnh mở thủ công từng máy một để lục tìm lỗi (việc này gọi là **Logging Phân Tán**).

**Xử Lý Tập Trung (Centralized Processing)** giải quyết bài toán này:
*   **Thu gom tất cả về một mối:** Mọi thiết bị, mọi ứng dụng dù chạy ở đâu đều phải "bơm" log về chung một "Hồ chứa" (Data Lake), trong trường hợp của bạn chính là kho **Elasticsearch**.
*   **Một cửa duy nhất (One Pane of Glass):** Người quản trị (Admin) chỉ cần ngồi 1 chỗ mở **Kibana** lên là có thể tìm kiếm, truy vết lỗi xuyên suốt qua tất cả các hệ thống. 
*   **Ví dụ Khắc Phục Sự Cố:** Bạn có thể kết chuỗi sự kiện dễ dàng: *Phát hiện lỗi thanh toán ở Web K8s -> Tra ngược qua chuỗi thời gian (timestamp) -> Phát hiện chính xác thời điểm đó Database trên máy ảo (VM) cũng đang báo lỗi quá tải.*.

Hệ thống bạn đang làm (Fluent Bit + ES + Kibana) CHÍNH LÀ một hệ thống kiến trúc xử lý log tập trung điển hình!

---

## 3. Luồng Nhận Trong - Nhận Ngoài (Internal vs External Ingestion)
> *"Nếu tôi có web chạy trong K8s, và một cái Database chạy máy ảo ngoài K8s, làm sao gom chung log lại?"*

Hệ thống Elasticsearch của bạn nằm **Bên Trong** cụm K8s. Việc thu thập log của công ty thường chia thành 2 luồng rõ rệt:

### A. Luồng Nhận Trong (Internal Kubernetes Ingestion)
*   **Nguồn Sinh Log:** Các ứng dụng chạy trên chính cụm K8s đó (VD: Argocd, Web portal).
*   **Cách Hoạt Động:** Dùng **Fluent Bit dạng DaemonSet** (như bạn đang cấu hình). Nó tự động chạy trên mọi máy chủ Worker, đọc tự động thư mục `/var/log/containers/`, dán nhãn tự động từ K8s và gửi thẳng vào Elasticsearch qua mạng nội bộ tốc độ cao của cụm. 

### B. Luồng Nhận Ngoài (External Systems Ingestion)
*   **Nguồn Sinh Log:** Các máy chủ ảo (VM), Máy chủ vật lý cũ (Legacy Server), Thiết bị mạng, Firewall, hay các cụm K8s khác...
*   **Cách Hoạt Động:** Có 2 hướng tiếp cận chính:
    1.  **Cài Agent Tận Nơi:** Giống như trong K8s, bạn tiến hành tự cài đặt phần mềm Fluent Bit hoặc Filebeat lên CÁC MÁY ẢO BÊN NGOÀI đó. Cấu hình để các Agent này gửi log xuyên qua mạng LAN đi vào cổng ngoài (NodePort/Ingress) của cụm Elasticsearch bên trong Kubernetes của bạn.
    2.  **Mở Cổng Nhận Thụ Động (Syslog Server / Log Aggregator):** 
        - Ta sẽ dựng thêm một con Logstash hoặc Fluentd chuyên dụng đứng ở "vùng biên" cụm K8s.
        - Với các thiết bị mạng cũ (Switch, Router), mạng nội bộ hiếm khi cho cài Agent. Nhưng mặc định thiết bị nào cũng hỗ trợ giao thức Syslog chuẩn công nghiệp (UDP/TCP cổng 514). Bạn cấu hình Switch tự động "bắn" log về con "lính gác" này.
        - Con "lính gác" Logstash sẽ hứng trọn giao thức Syslog này, biên dịch chuẩn hoá lại format (xử lý format theo Yêu cầu số 1), rồi mới "bơm" đẩy tiếp kết quả dọn dẹp xong vào Elasticsearch gốc.

**Mô Hình Tổng Quan Khuyến Nghị:**
```text
[ Máy chủ VM Database ]──(Cài Agent Filebeat)──┐
                                               │
                                               ▼
[ Thiết bị Router/Switch ]──-(Giao thức Syslog)─┼──▶ [ Cổng INGRESS K8s ] ──▶ [ ELASTICSEARCH (K8s) ]
                                               ▲       (Load Balancer)               (Kho Lưu Trữ)
                                               │
[ Máy chủ Legacy cũ ] ───(Cài Agent FluentBit)─┘
```
