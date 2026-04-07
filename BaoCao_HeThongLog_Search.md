# Báo Cáo Nghiên Cứu và Triển Khai Hệ Thống Log Tập Trung, Log Search trên Kubernetes

## 1. Tổng Quan Kiến Trúc Logging Khuyến Nghị
Kubernetes mặc định không cung cấp giải pháp lưu trữ log lâu dài. Log của ứng dụng thường được container runtime (như containerd) ghi ra file tại đường dẫn `/var/log/pods/` trên từng node. Do đặc tính vòng đời ngắn (ephemeral) của Pod, khi Pod bị xóa hoặc khởi động lại, lượng dữ liệu log cục bộ này sẽ bị mất vĩnh viễn. 

Để giải quyết triệt để vấn đề này, kiến trúc tiêu chuẩn áp dụng là mô hình **Node-level Logging Agent**.
Cơ chế cốt lõi bao gồm:
- Một tiến trình (Agent) dạng DaemonSet khởi chạy trên mọi Node thuộc cụm.
- Agent thực thi nhiệm vụ thu thập, tổng hợp bộ log đẩy ra qua kênh `stdout/stderr` từ vùng chứa (container).
- Bổ sung siêu dữ liệu (metadata) hữu ích như Tên Pod, Tên Namespace, Nhãn (Labels) gắn kết với từng dòng log.
- Chuyển tiếp bản ghi về hệ thống lưu trữ độc lập (Log Backend) phục vụ phân tích, lập chỉ mục và tìm kiếm.

![Mô hình Topology Hệ Thống Log Search](LogSearch.png)

## 2. Giải Pháp Quy Hoạch & Thiết Kế
Khảo sát hiện trạng cụm Kubernetes ghi nhận hệ thống đang vận hành kiến trúc lưu trữ **Elasticsearch** và giao diện tìm kiếm đồ hoạ **Kibana** (thuộc giải pháp ELK) nằm tại không gian định danh (namespace) `elk`. 

Để bảo toàn mô hình hiện tại và tối ưu tài nguyên, giải pháp lý tưởng là duy trì cụm xử lý Backend và thiết lập thêm dịch vụ tác tử (Log Agent) gửi nguồn: **Fluent Bit**.

**Lộ trình xử lý dòng chảy dữ liệu (Log Pipeline cấp độ Production):**

```text
  [ Namespace: dung-lab - Nguồn phát sinh Log ]
  ┌─────────────────────────────────────────────────────────┐
  │  1. Các Ứng dụng Giả lập (Microservices Pods)           │
  │  [Frontend]   [Backend]   [Database]   [Webserver]      │
  │         │           │          │             │          │
  │         ▼ Xuất log JSON qua stdout/stderr               │
  │  2. /var/log/containers/*.log                           │
  └─────────┼───────────────────────────────────────────────┘
            │
            ▼ Đọc file log liên tục (Tail)
  [ DaemonSet: Fluent Bit - Tác tử xử lý Log ]
  ┌─────────▼───────────────────────────────────────────────┐
  │  3. Tiền Xử Lý (Processing Pipeline)                    │
  │   ├─ Filter: Gắn nhãn Kubernetes (Pod, Namespace...)    │
  │   ├─ Parser: Bóc tách JSON log                          │
  │   ├─ Rewrite Tag: Phân luồng theo dịch vụ phát sinh     │
  │   └─ Buffer: Lưu đệm trên RAM (10MB) & Disk (500MB)     │
  └─────────┼───────────────────────────────────────────────┘
            │ 
            ▼ Truyền tải HTTP Bulk/TLS tới Cổng 9200
            │
  [ Namespace: elk - Trung tâm Lưu trữ, Phân tích & Báo động]
  ┌─────────▼───────────────────────────────────────────────┐
  │  4. Elasticsearch (Lưu trữ tập trung)                   │
  │   ├─ Index Design: dung-fe-*, dung-be-*, dung-db-*...   │
  │   ├─ Static Mapping: Ràng buộc chặt chẽ kiểu dữ liệu    │
  │   └─ Lifecycle (ILM): Luân chuyển sổ và Tự xóa sau 7d   │
  │         │                                 │             │
  │         ▼ Try vấn phân tích               ▼ Quét lỗi    │
  │  5. Kibana Dashboard                6. ElastAlert       │
  └─────────┼─────────────────────────────────┼─────────────┘
            │                                 │
            ▼ Cổng Dịch vụ: 5601              ▼ Tín hiệu Webhook
   [ Bảng Điều Khiển Kỹ Sư ]         [ Thông báo Telegram ]
```

1. **Nguồn Log (Log Generators):** Các cụm ứng dụng giả lập tách biệt liên tục xuất log định dạng JSON ra hệ thống.
2. **Tiêu thụ & Tiền xử lý (Fluent Bit):** Hệ thống đọc log tĩnh, tiến hành lọc gắn nhãn K8s, phân luồng (Rewrite Tag) và liên tục lưu đệm xuống đĩa vật lý (Filesystem Buffer) để đề phòng thảm họa rớt mạng.
3. **Lưu trữ & Quản trị Vòng đời (Elasticsearch):** Dữ liệu được trút vào từng vùng chứa (Index) riêng biệt dưới chế độ Mapping tĩnh và bị quản lý tuổi thọ giới hạn nghiêm ngặt bởi ILM để tiết kiệm dung lượng.
4. **Trực quan hoá (Kibana):** Kỹ sư dùng Kibana truy vấn khối lượng dữ liệu được tổ chức lớp lang.
5. **Cảnh báo (ElastAlert):** Máy quét độc lập liên tục đếm số lượng lỗi dựa theo luật và tự động nối tín hiệu gửi thông báo theo thời gian thực về kênh Telegram của nhóm kỹ sư.

## 3. Triển Khai Hệ Thống Mô Phỏng Giả Lập 
Nhằm phục vụ quá trình đo lường, kiểm thử sức chịu tải và độ chính xác của luồng ống dẫn dữ liệu (Pipeline), báo cáo đề xuất đưa vào vận hành một hệ sinh thái giả lập phát sinh log (**Log Generator**). 

Hệ thống giả lập được thiết lập tại một namespace riêng biệt (ví dụ: `dung-lab`), bao gồm 4 thành phần thiết yếu, đại diện cho kiến trúc Microservices điển hình:
- **Frontend (FE):** Giả lập nhật ký tương tác người dùng, truy xuất hành vi mở trang và nhấp chuột định kỳ.
- **Backend (BE):** Chạy quy trình giả lập phản hồi API, trong đó cố tình xuất hiện ngẫu nhiên các mã lỗi phổ biến (`500 Internal Server Error`, `400 Bad Request`) để đo lường cơ chế cảnh báo.
- **Database (DB):** Sinh log hệ thống phản ánh trạng thái câu lệnh truy vấn SQL, cảnh báo `slow_query` hoặc thông báo lỗi ủy quyền `auth_failed`.
- **Webserver:** Đại diện cổng giao tiếp (Nginx/Proxy) sinh ra các định dạng chuẩn access log và error log liên tục.

Tất cả các dịch vụ này xuất log đồng nhất theo định dạng JSON thông qua `stdout`, tạo điều kiện thuận lợi cho công tác đối soát Metadata tại máy chủ nhận (Backend). Quá trình cài đặt chỉ yêu cầu một `ConfigMap` lưu trữ các khối mã thực thi (Scripts) và vài file `YAML` cấu trúc `Deployment` rất nhẹ cho từng thành phần.

## 4. Thiết Kế Chuyên Sâu Tối Ưu Hóa Dữ Liệu
Kiến trúc cấp độ Production đòi hỏi hệ thống lưu trữ phải thông minh để không gặp tình trạng cạn kiệt tài nguyên hoặc tìm kiếm chậm trễ. Các giải pháp quy hoạch sau đã được thiết lập:

### 4.1 Index Design (Thiết Kế Chỉ Mục)
Thay vì đẩy toàn bộ dòng dữ liệu của cả hệ thống đổ chung vào một Index cồng kềnh duy nhất (như `fluent-bit-*`), hệ thống áp dụng chiến lược phân tách Index theo định danh dịch vụ:
- Định tuyến Frontend: `dung-fe-write`
- Định tuyến Backend: `dung-be-write`
- Định tuyến Database: `dung-db-write`
- Định tuyến Cổng Web: `dung-web-write`

Cách tiếp cận này mang lại khả năng quản trị độc lập: Có khả năng áp dụng chính sách ưu tiên hiệu năng hoặc thời gian lưu trữ khác nhau cho từng phân hệ, đồng thời tăng tốc độ truy vấn Elasticsearch khi kỹ sư chỉ cần tra cứu tập log khoanh vùng của Backend riêng biệt thay vì rà soát toàn bộ.

### 4.2 Mapping Tĩnh (Static Mapping - Không Sử Dụng Dynamic)
Chức năng tự động đoán kiểu dữ liệu (Dynamic Mapping) của Elasticsearch thường gây lãng phí tài nguyên và rủi ro cấu trúc bảng đã bị vô hiệu hóa (`dynamic: false`). Hệ thống áp dụng hoàn toàn **Mapping tĩnh** bằng cách định nghĩa một bộ khung dữ liệu chuẩn trước khi log được đẩy vào:
- Chỉ định rõ thuộc tính thời gian `@timestamp` quy đổi về hệ chuẩn đối soát (`date`).
- Các trường định dạng phân nhóm, ID, đánh giá cảnh báo như `level`, `service` được chuyển về ngôn ngữ tìm kiếm tối ưu (`keyword`).
- Ngoại trừ các trường thông báo chi tiết chứa nhiều nội dung ngẫu nhiên như `message` được gắn định dạng toàn văn bản (`text`).

Việc làm này đóng vai trò như cửa kiểm duyệt nghiêm ngặt: Loại bỏ những tệp log rác hoặc không tuân thủ mẫu thiết kế Json gốc, giúp tiết kiệm đáng kể năng lực CPU và bộ nhớ của Cụm.

### 4.3 Quản Lý Dung Lượng Thông Qua Lifecycle (ILM)
Để giải quyết bài toán cạn kiệt dung lượng đĩa cứng sau một thời gian vận hành dài hạn, giải pháp kiểm soát vòng đời **Index Lifecycle Management (ILM)** đã được sử dụng. Một tập chính sách mang tên `logs-lab-policy` quy định tự động hoạt động 2 pha vòng đời quản trị chính:
- **Giai đoạn Hot:** Dữ liệu mới liên tục tiếp nhận. Lệnh luân chuyển vòng lặp (`rollover`) sẽ tự động đóng chỉ mục cũ và mở một chỉ mục mới tinh khôi nối tiếp ngay khi "cuốn sổ" hiện tại vượt mức sử dụng trong `1 ngày`, hoặc khi file đạt kích cỡ chuẩn `5GB`.
- **Giai đoạn Delete:** Kích hoạt chức năng dọn dẹp hệ thống khi tuổi thọ của cuốn sổ log đạt quá `7 ngày`, tự động thanh lý và xóa sạch hoàn toàn để trả lại diện tích ổ đĩa.

Yêu cầu thực thi này rất gọn thông qua kịch bản thiết lập chạy PowerShell cùng những tệp lệnh gọi cấu trúc Index Templates và ILM Policies chuyên biệt đi kèm.

## 5. Quy Trình Kỹ Thuật: Thu Thập & Pipeline (Fluent Bit)
Trong kiến trúc này, tiến trình Agent phụ trách khâu dẫn xuất đóng vai trò cốt lõi. Việc cài đặt hoàn thiện tuân thủ việc áp dụng một file cấu hình tập lệnh tập trung (`fluent-bit-values.yaml`) thông qua công cụ phân phối `Helm`. Yêu cầu có hai cấu trúc cốt yếu:

### 5.1 Xử Lý Bộ Lọc (Filter) Đa Lớp
Tệp cấu hình của Agent xây dựng nhiều lưới lọc trước khi dữ liệu được đóng gói gửi đi:
- **Filter Kubernetes:** Gắn nhãn tự động mọi loại thông tin vật lý (Tên Pod, IP, Node) lên dòng log.
- **Filter Parser:** Biến đoạn mã text xuất thô thành đối tượng JSON có thuộc tính mạch lạc.
- **Filter Rewrite Tag:** Mô hình ứng dụng một quy tắc thông minh giúp tiến trình tự động xác định thẻ đích bằng cách dò thuộc tính dịch vụ. Nhờ thế, log của Webserver có thể bị phân luồng dẫn hướng về đúng chỉ mục lưu trữ của Webserver, đảm bảo mục tiêu thiết kế ban đầu.

### 5.2 Bộ Đệm Chống Nghẽn Trạm Chuyển Tiếp (Buffer)
Để đề phòng thảm họa sập mạng cục bộ hoặc máy chủ Elasticsearch bị bão hòa truy xuất báo lỗi `Too Many Requests`, đường ống được gia cố bằng định mức 2 lớp đệm:
- **Bộ Đệm RAM (Memory Buffer):** Tiến trình Pod bị khóa mức trần sử dụng (mặc định cấu hình ở con số cứng `10MB` trên một luồng) nhằm chặn đứng rủi ro rò rỉ RAM gây sụp đổ Node (OOMKill).
- **Bộ đệm Đĩa Từ (Filesystem Buffer):** Mượn không gian vật lý để kích hoạt tính năng bộ nhớ trung gian khẩn cấp (`storage.type filesystem`). Việc này giúp thiết lập cầu lưu trữ dự phòng cất giữ lượng log đang ùn tắc thẳng xuống thư mục nội bộ. Sau sự cố gián đoạn, Agent lập tức dò và đẩy toàn bộ tồn đọng lên máy chủ một cách nguyên vẹn.

## 6. Hệ Thống Cảnh Báo Chủ Động (Alerting)
Giải pháp thay đổi văn hóa đọc tìm lỗi thủ công, hệ thống đã ứng dụng nền tảng **ElastAlert** để liên tục rà soát dữ liệu định kỳ tạo các chỉ báo xử lý sự cố lập tức. Nền tảng được cài đặt độc lập với tệp Manifest `Deployment` đi kèm tham số luật (`elastalert-rules-configmap`).

- **Bắt Lỗi Theo Tần Suất:** Khảo sát dựa trên các luồng cảnh báo đỏ. Ví dụ: Phát lệnh báo động nếu tập phản hồi Webserver của 5 phút gần nhất xuất hiện số lượng lỗi status `500` lặp lại trên 20 lần; hoặc khi ghi nhận sự kiện Database bị từ chối xác thực liên tục vọt lên (cảnh báo nguy cơ xâm nhập trái phép).
- **Khuyến Nghị Mở Rộng Hệ Thống Cảnh Báo:** Hiện tại mức độ Alert báo cáo nằm trong phạm vi theo dõi (Debug), in thông báo cảnh báo qua Console nội tại. Việc này tối đa hóa để làm tài liệu đối chiếu nền tảng, nhưng hệ thống hoàn chỉnh nên được triển khai móc nối Webhooks mở rộng qua các kênh nhắn tin phổ biến như **Telegram** để đảm bảo thông báo nóng tới kỹ sư trực chiến nhanh chóng, trực quan.

## 7. Đặc tả Tiện Ích Giao Diện Tìm Kiếm Log (Log Search via Kibana)
Hệ thống Elasticsearch sau khi thu thập thành công có thể hiển thị kết quả thông qua cửa sổ thao tác lập tức.

### 7.1 Xây Dựng Bản Ánh Xạ Dữ Liệu (Data View Configuration)
1. Khởi chạy cầu kết nối máy chủ tới Local bằng giao thức Port-forward (Sử dụng cổng 5602):
`kubectl port-forward svc/kibana-dung-kibana 5602:5601 -n elk`
2. Tiến hành duyệt địa chỉ dịch vụ tại: `http://localhost:5602`.
3. Tìm tới chỉ mục hệ thống: **Management** -> **Stack Management**.
4. Chọn danh mục **Data Views** (các ấn bản cũ được gọi là Index Patterns).
5. Thiết lập Data View mới, lựa chọn kết hợp các luồng đích (Ví dụ: `dung-be-*` để khoanh vùng hiển thị Log Backend).
6. Thông số đối chiếu thời gian thiết lập thành chỉ số `@timestamp`.

### 7.2 Thao Tác Thực Thi Truy Vấn Tìm Kiếm 
Thực hiện quá trình truy vết, sàng lọc dữ liệu đã thu thập:
1. Điều hướng danh mục về chuyên trang: **Analytics** -> **Discover**.
2. Kiểm tra bộ chọn ở trên cùng bên trái màn hình đảm bảo luồng đối chiếu trỏ tới Data View chỉ định.
3. Rà soát bằng từ khoá hoặc dùng chỉ định KQL (Kibana Query Language). Cú pháp ví dụ nhắm vào cụm lọc: 
   `service: "webserver" AND status_code >= 500`
4. Dựa vào thông số để phỏng định cấu trúc biểu đồ sinh bởi sự kiện log.

## 8. Định Hướng Nghiên Cứu Mở Rộng Hệ Thống

### 8.1 Triển Khai Phiên Phiên Bản Kibana Độc Lập 
Để không xáo trộn không gian làm việc của Kibana hiện tại, báo cáo đề xuất triển khai song song một bản sao Kibana độc lập chuyên dụng cho việc quản trị biến động Log (cấu hình Multi-instance qua `kibana-logging-values.yaml`). Yêu cầu duy nhất khi vận hành là sử dụng Màn hình Duyệt Web Ẩn danh (Incognito Window) và kết nối qua cổng **5602** để tránh xung đột định danh phiên bản Cookie nội bộ.

### 8.2 Tích hợp Message Broker (Apache Kafka) Định Hình Chuẩn Sự Kiện
Mặc dù hệ thống hiện tại đã cấu hình bộ đệm nội trú (Filesystem Buffer) cho tiến trình Fluent Bit nhằm chống rơi vãi rớt log, giải pháp này mang tính chất cục bộ, giới hạn bởi dung lượng ổ cứng Node và khá cồng kềnh với tiến trình Agent. 

Đối với tải trọng hệ thống cấp độ doanh nghiệp (Enterprise), định hướng kiến trúc tiệm cận chuẩn Production đòi hỏi thiết lập một hàng chờ Message Broker - như **Apache Kafka** - đứng làm trung gian, phân tách đường ống dữ liệu thành mô hình: 

`Dịch vụ (Log Generators) -> Fluent Bit -> Kafka -> Logstash -> Elasticsearch`.

**Lợi thế quản trị cốt lõi mang lại:**
- **Giải Phóng Tải Trọng (Decoupling):** Kafka trở thành siêu trạm thu dung (Ingestion), tiếp nhận sự kiện với tốc độ cực cao. Nó giúp triệt tiêu nhu cầu cấp Buffer cục bộ nặng nề trên mạng lưới Fluent Bit, giúp Agent trên máy chủ tiêu tốn cấu hình siêu nhỏ (Lightweight).
- **Tính Bền Bỉ Kháng Lỗi (Fault-Tolerance):** Bất chấp việc Elasticsearch sập, ngắt kết nối hoặc bảo trì trong thời gian dài hạn, dữ liệu khổng lồ vẫn được xếp hàng nguyên vẹn, tuần tự và an toàn trong khối Cluster Kafka để truy xuất lại sau đó.
