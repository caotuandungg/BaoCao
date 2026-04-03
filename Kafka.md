# Kafka Thay Cho Buffer Cục Bộ

## 1. Mục tiêu

Tài liệu này trình bày ý tưởng dùng **Kafka** như một lớp đệm trung gian cho hệ thống logging, thay vì phụ thuộc chủ yếu vào buffer cục bộ của Fluent Bit.

Mục tiêu là trả lời:

- Kafka có thể thay cho buffer được không?
- Nếu có thì kiến trúc nên đổi như thế nào?
- Cách triển khai thực tế sẽ ra sao?
- Có phù hợp với bài toán hiện tại của bạn không?

Kết luận ngắn gọn:

- **Có thể**
- nhưng Kafka không chỉ là “buffer lớn hơn”
- nó là một **message backbone** trung gian giữa tầng thu thập log và tầng lưu trữ log

---

## 2. Hiểu đúng: Kafka không phải chỉ là buffer

Buffer cục bộ của Fluent Bit có nhiệm vụ:

- giữ log tạm trong RAM hoặc disk
- retry khi Elasticsearch chậm hoặc lỗi
- giảm mất log trong thời gian ngắn

Kafka thì mạnh hơn nhiều:

- nhận log từ producer
- lưu log theo topic/partition
- giữ log trong một khoảng thời gian cấu hình trước
- cho phép consumer đọc lại
- tách rời tầng ingest khỏi tầng indexing

Vì vậy, nếu đổi sang Kafka, kiến trúc sẽ chuyển từ:

```text
Pods -> Fluent Bit -> Elasticsearch
```

thành:

```text
Pods -> Fluent Bit -> Kafka -> Consumer -> Elasticsearch
```

---

## 3. Khi nào nên dùng Kafka

Kafka phù hợp khi bạn muốn:

- chống nghẽn tốt hơn khi Elasticsearch chậm
- tách log ingestion khỏi log indexing
- scale lớn hơn về sau
- có khả năng replay log
- có nhiều consumer cho cùng một nguồn log

Ví dụ:

- một consumer đẩy vào Elasticsearch
- một consumer khác đẩy vào object storage
- một consumer khác tạo metric hoặc stream processing

Nếu chỉ cần lab nhỏ, Fluent Bit buffer là đủ.

Nếu muốn mô hình “gần production” hơn, Kafka là hướng rất đáng làm.

---

## 4. Kiến trúc đề xuất

### 4.1. Kiến trúc hiện tại

```text
Pods (dung-lab)
   |
   v
Fluent Bit
   |
   v
Elasticsearch
   |
   v
Kibana / Alert
```

### 4.2. Kiến trúc khi thêm Kafka

```text
Pods (dung-lab)
   |
   v
Fluent Bit
   |
   v
Kafka
   |
   v
Log Consumer
   |
   v
Elasticsearch
   |
   v
Kibana / Alert
```

### 4.3. Các thành phần chính

1. `Fluent Bit`
- vẫn đọc log từ `/var/log/containers/*.log`
- vẫn parse JSON
- nhưng output không còn đi thẳng vào Elasticsearch
- thay vào đó đẩy vào Kafka topic

2. `Kafka`
- giữ log như một hàng đợi bền vững
- absorb burst traffic
- bảo vệ hệ thống khi Elasticsearch tạm chậm

3. `Consumer`
- có thể là Logstash, Kafka Connect, Fluent Bit khác, hoặc custom consumer
- lấy log từ Kafka
- đẩy vào Elasticsearch theo đúng index/template/mapping

4. `Elasticsearch`
- vẫn là nơi index và search

5. `Kibana`
- vẫn là nơi kiểm tra và phân tích log

---

## 5. Kafka thay buffer như thế nào

### 5.1. Với buffer cục bộ của Fluent Bit

Fluent Bit chỉ giữ log ở:

- RAM
- filesystem trên node

Giới hạn:

- phụ thuộc node local
- nếu node có vấn đề nặng, rủi ro vẫn còn
- không có khả năng fan-out hoặc replay mạnh

### 5.2. Với Kafka

Kafka giữ log ở:

- cluster Kafka
- nhiều partition
- có replication nếu cấu hình

Ưu điểm:

- durable hơn buffer node-local
- dễ scale
- decouple producer và consumer
- có thể replay

Nói đơn giản:

- buffer Fluent Bit là “đệm gần nguồn”
- Kafka là “hàng đợi log tập trung”

---

## 6. Cách triển khai thực tế

Có 2 hướng chính.

### Hướng 1. Fluent Bit -> Kafka -> Logstash -> Elasticsearch

Đây là hướng dễ hiểu và khá thực tế.

Luồng:

```text
Fluent Bit -> Kafka -> Logstash -> Elasticsearch
```

Ưu điểm:

- Logstash mạnh về xử lý pipeline
- dễ enrich, transform, route theo topic
- quen thuộc với hệ ELK

Nhược điểm:

- thêm một thành phần nặng
- Logstash tốn RAM/CPU hơn

### Hướng 2. Fluent Bit -> Kafka -> Kafka Connect Elasticsearch Sink

Luồng:

```text
Fluent Bit -> Kafka -> Kafka Connect -> Elasticsearch
```

Ưu điểm:

- chuẩn kiểu data pipeline
- đỡ phải tự viết consumer

Nhược điểm:

- Kafka Connect cũng là một hệ riêng cần vận hành
- cấu hình sink connector cần hiểu kỹ

### Hướng 3. Fluent Bit -> Kafka -> Fluent Bit consumer / custom consumer

Luồng:

```text
Fluent Bit -> Kafka -> consumer khác -> Elasticsearch
```

Ưu điểm:

- linh hoạt

Nhược điểm:

- tốn công tự quản lý hơn

---

## 7. Phương án phù hợp nhất cho project của bạn

Nếu mục tiêu là:

- dễ trình bày
- dễ demo
- vẫn có giá trị kiến trúc

thì mình khuyên:

```text
Fluent Bit -> Kafka -> Logstash -> Elasticsearch
```

Vì:

- bạn đã có Elasticsearch/Kibana
- bạn cũng đã từng làm với Logstash
- Logstash làm consumer từ Kafka khá hợp lý
- dễ giải thích trong báo cáo

---

## 8. Thiết kế topic Kafka

Bạn nên thiết kế topic có quy hoạch, không đẩy tất cả vào một topic duy nhất nếu muốn mở rộng sạch.

### Phương án 1. Một topic cho mỗi service

- `dung-fe-log`
- `dung-be-log`
- `dung-db-log`
- `dung-web-log`

Ưu điểm:

- dễ route
- dễ scale consumer theo loại log
- dễ phân quyền

### Phương án 2. Một topic chung cho lab

- `dung-lab-log`

Ưu điểm:

- đơn giản

Nhược điểm:

- consumer phải tự phân loại bên trong payload

Khuyến nghị:

- nếu làm bài bản: dùng 4 topic riêng
- nếu làm demo nhanh: 1 topic chung vẫn được

---

## 9. Fluent Bit sẽ đổi như thế nào

Hiện tại Fluent Bit của bạn đang:

- parse JSON
- rewrite tag theo `service`
- output sang Elasticsearch alias riêng

Nếu dùng Kafka, phần output đổi thành:

- output tới Kafka broker
- topic theo tag hoặc theo service

Ý tưởng:

```text
INPUT -> kubernetes filter -> parser -> rewrite_tag -> Kafka output
```

Ví dụ:

- `frontend` -> topic `dung-fe-log`
- `backend` -> topic `dung-be-log`
- `database` -> topic `dung-db-log`
- `webserver` -> topic `dung-web-log`

Phần parse JSON vẫn nên giữ nguyên ở Fluent Bit để payload vào Kafka đã sạch và có cấu trúc.

---

## 10. Consumer sẽ làm gì

Consumer có nhiệm vụ:

- đọc log từ Kafka
- đẩy vào Elasticsearch
- gắn đúng index/alias

Nếu dùng Logstash:

- input là `kafka`
- filter có thể nhẹ hoặc không cần nếu payload đã đẹp
- output là `elasticsearch`

Ví dụ tư duy:

- topic `dung-fe-log` -> index `dung-fe-write`
- topic `dung-be-log` -> index `dung-be-write`
- topic `dung-db-log` -> index `dung-db-write`
- topic `dung-web-log` -> index `dung-web-write`

Như vậy:

- ILM
- template
- mapping tĩnh

vẫn được giữ nguyên như hiện tại.

---

## 11. Cách test khi dùng Kafka

Khi chuyển sang Kafka, bạn cần test theo nhiều lớp hơn.

### 11.1. Test producer

Kiểm tra Fluent Bit có đẩy được log vào Kafka:

- log Fluent Bit không lỗi output Kafka
- topic có message mới

### 11.2. Test topic

Kiểm tra Kafka có thật sự giữ log:

- dùng kafka-console-consumer
- kiểm tra offset tăng

### 11.3. Test consumer

Kiểm tra Logstash/Kafka Connect có đọc được:

- consumer group hoạt động
- offset được commit

### 11.4. Test Elasticsearch

Kiểm tra:

- log cuối cùng vẫn vào đúng `dung-*`
- mapping vẫn đúng
- ILM vẫn hoạt động

### 11.5. Test tình huống nghẽn

Kịch bản rất hay để demo:

1. cho 4 pod sinh log bình thường
2. dừng consumer hoặc làm Elasticsearch chậm
3. Kafka vẫn tiếp tục nhận log
4. khi consumer bật lại, log được tiêu thụ tiếp

Đây là điểm Kafka thắng buffer cục bộ rất rõ.

---

## 12. Ưu điểm của việc dùng Kafka

- tách rời ingestion và indexing
- chịu tải burst tốt hơn
- replay log được
- dễ mở rộng nhiều consumer
- bền vững hơn buffer cục bộ
- hợp với kiến trúc production hơn

---

## 13. Nhược điểm và chi phí

- thêm nhiều thành phần phải vận hành
- Kafka không nhẹ
- phải quản lý broker, topic, retention, partition
- nếu làm chuẩn còn phải tính:
  - replication factor
  - storage
  - consumer group
  - monitoring Kafka

Nói ngắn gọn:

- Kafka mạnh hơn
- nhưng phức tạp hơn đáng kể

---

## 14. So sánh nhanh: Buffer Fluent Bit và Kafka

### Buffer Fluent Bit

Ưu điểm:

- đơn giản
- đủ cho lab nhỏ
- ít thành phần

Nhược điểm:

- chỉ là buffer cục bộ
- replay kém
- phụ thuộc node nhiều hơn

### Kafka

Ưu điểm:

- hàng đợi log tập trung
- durable hơn
- replay tốt
- scale tốt

Nhược điểm:

- phức tạp
- tốn tài nguyên
- tăng chi phí vận hành

---

## 15. Khuyến nghị cho bạn

Nếu mục tiêu hiện tại là:

- hoàn thiện đồ án
- có demo rõ ràng
- không quá nặng vận hành

thì có 2 lựa chọn:

### Lựa chọn A. Giữ Fluent Bit buffer như hiện tại

Phù hợp nếu:

- muốn hệ thống gọn
- muốn ít rủi ro
- muốn tập trung vào ILM, mapping, alert

### Lựa chọn B. Nâng lên Kafka ở phiên bản 2

Phù hợp nếu:

- muốn kiến trúc đẹp hơn
- muốn nhấn mạnh tính production
- chấp nhận thêm độ phức tạp

Mình khuyên:

- với bài hiện tại, giữ buffer Fluent Bit là đủ
- nếu muốn mở rộng nâng cấp tiếp, thêm Kafka như một phase nâng cao riêng

---

## 16. Lộ trình triển khai nếu quyết định dùng Kafka

Nên đi theo thứ tự:

1. dựng Kafka cluster riêng trong namespace riêng
2. tạo topic cho `fe`, `be`, `db`, `web`
3. đổi Fluent Bit output sang Kafka
4. dựng consumer Logstash đọc từ Kafka
5. đẩy vào Elasticsearch alias `dung-*`
6. test end-to-end
7. test tình huống consumer down / Elasticsearch chậm

---

## 17. Kết luận

Nếu dùng Kafka thay cho buffer, hệ thống của bạn sẽ chuyển từ mô hình:

- log ship trực tiếp sang Elasticsearch

thành:

- log ship qua một hàng đợi trung gian bền vững

Đây là hướng:

- mạnh hơn
- sạch hơn về kiến trúc
- phù hợp với production hơn

Nhưng đổi lại:

- khó hơn
- nặng hơn
- vận hành phức tạp hơn

Vì vậy, về mặt chiến lược:

- **Fluent Bit buffer** phù hợp cho phiên bản hiện tại
- **Kafka** phù hợp cho phiên bản mở rộng nâng cao

Nếu bạn muốn, bước tiếp theo mình có thể viết tiếp cho bạn một file nữa kiểu:

- `Kafka_DeployPlan.md`

trong đó chia rất cụ thể:

- cần những manifest gì
- Kafka namespace nào
- topic nào
- Logstash consumer cấu hình ra sao
- cách chuyển từ kiến trúc hiện tại sang Kafka từng bước một
