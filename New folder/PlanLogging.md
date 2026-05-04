# Plan Nâng Cấp Hệ Thống Logging Trên Kubernetes

## 1. Mục tiêu

Tài liệu này trả lời câu hỏi: với hệ thống hiện tại đang có `Fluent Bit -> Elasticsearch -> Kibana`, liệu có thể nâng cấp lên một mô hình logging "đúng bài" hơn để phục vụ demo, test, và tiến tới production hay không.

Kết luận ngắn gọn: **hoàn toàn thực hiện được**. Sáu tiêu chí bạn nêu ra đều có thể triển khai trên nền cụm Kubernetes hiện có. Tuy nhiên nên làm theo từng lớp, không làm dồn một lúc, để vừa kiểm soát rủi ro vừa dễ chứng minh kết quả trong báo cáo.

---

## 2. Kết luận tính khả thi theo từng tiêu chí

### 2.1. Thu thập log từ một hệ thống K8s hoàn chỉnh gồm FE, BE, DB, Webserver

**Làm được.**

Ý tưởng phù hợp nhất là dựng một môi trường mô phỏng mini trong Kubernetes gồm 4 workload:

- `frontend`: một Pod hoặc Deployment rất đơn giản, có thể là Nginx static hoặc một container Node/BusyBox in log định kỳ
- `backend`: một Pod sinh log ứng dụng, có cả log info và error
- `database`: không cần DB "thật" nặng nề; có thể dùng `postgres`, `mysql`, hoặc một container giả lập sinh log theo format DB
- `webserver-nginx`: một Pod Nginx riêng để sinh access log và error log

Mục tiêu của nhóm Pod này không phải làm ứng dụng thật, mà là:

- tạo đủ loại log khác nhau
- có cả log text thường, log JSON, log access/error
- có lỗi có chủ đích để test pipeline, mapping, alert

Khuyến nghị triển khai:

- Tạo namespace riêng, ví dụ `dung-lab`
- Mỗi thành phần dùng `Deployment` 1 replica để dễ quản lý
- Gắn label chuẩn như:
  - `app.kubernetes.io/part-of: dung-lab`
  - `app.kubernetes.io/component: frontend|backend|database|webserver`
  - `log_type: app|nginx|db`

Như vậy Fluent Bit sẽ lấy được log từ đủ 4 loại nguồn trong cùng cụm, rất phù hợp cho việc test toàn bộ pipeline.

### 2.2. Quản lý dung lượng Elasticsearch bằng Lifecycle

**Làm được và nên làm.**

Đây là cách đúng để tránh Elasticsearch phình vô hạn.

Giải pháp là áp dụng **ILM - Index Lifecycle Management** cho log index:

- Giai đoạn `hot`: index mới, đang ghi nhiều
- Giai đoạn `warm`: ít ghi, chủ yếu đọc
- Giai đoạn `delete`: xóa sau số ngày nhất định

Với môi trường lab hoặc demo, có thể dùng chính sách đơn giản:

- giữ log 7 ngày hoặc 14 ngày
- rollover khi đạt:
  - kích thước ví dụ `5gb`
  - hoặc tuổi index ví dụ `1d`
- xóa sau `7d` hoặc `14d`

Lợi ích:

- kiểm soát dung lượng
- tránh 1 index quá lớn
- dễ mở rộng lên production sau này

### 2.3. Có Index Design

**Làm được, và đây là điểm rất nên làm trước khi đổ thêm log thật.**

Thay vì để Fluent Bit đẩy toàn bộ về một prefix chung kiểu `fluent-bit-*`, nên thiết kế index theo mục tiêu truy vấn.

Có 2 hướng:

#### Hướng 1: Tách theo loại nguồn log

- `logs-fe-*`
- `logs-be-*`
- `logs-db-*`
- `logs-nginx-*`

Ưu điểm:

- dễ nhìn, dễ demo
- mapping từng loại rõ ràng hơn
- alert và retention có thể khác nhau theo từng nguồn

Nhược điểm:

- số lượng template/index nhiều hơn

#### Hướng 2: Gom theo chuẩn data stream hoặc nhóm ứng dụng

- `logs-app-*`
- `logs-infra-*`
- `logs-nginx-*`

Ưu điểm:

- gần mô hình production hơn
- dễ quản trị dài hạn

Nhược điểm:

- khi demo có thể kém trực quan hơn hướng 1

**Khuyến nghị cho đồ án/báo cáo:** dùng Hướng 1 trước, vì dễ giải thích và dễ chứng minh.

### 2.4. Có Mapping, không sử dụng dynamic

**Làm được, nhưng cần chuẩn hóa log đầu vào.**

Đây là tiêu chí quan trọng nhất về mặt chất lượng dữ liệu.

Nếu tắt `dynamic mapping`, Elasticsearch sẽ không tự đoán field nữa. Khi đó bạn phải:

- xác định trước field nào sẽ có
- gán kiểu dữ liệu cụ thể
- tạo index template trước khi ingest log

Ví dụ mapping nên định nghĩa trước:

- `@timestamp`: `date`
- `message`: `text`
- `level`: `keyword`
- `service.name`: `keyword`
- `event.dataset`: `keyword`
- `http.response.status_code`: `integer`
- `kubernetes.namespace_name`: `keyword`
- `kubernetes.pod_name`: `keyword`
- `trace_id`: `keyword`

Lưu ý rất quan trọng:

- Nếu log đầu vào quá lộn xộn, việc không dùng dynamic sẽ làm document bị reject
- Vì vậy phải chuẩn hóa parser/filter ngay từ Fluent Bit

Khuyến nghị:

- backend và frontend nên sinh log JSON có cấu trúc
- nginx dùng parser tách field rõ ràng
- database chỉ chọn một số field cốt lõi

### 2.5. Dùng Buffer của Fluent Bit trước khi gửi vào Elasticsearch

**Làm được, và rất nên làm.**

Đây là điểm nâng cấp quan trọng để pipeline ổn định hơn.

Fluent Bit hỗ trợ buffering theo hai lớp:

- `memory buffer`
- `filesystem storage buffer`

Khuyến nghị dùng kết hợp:

- `Mem_Buf_Limit` để chặn việc ăn RAM quá mức
- bật `storage.path` để có disk buffer
- output Elasticsearch dùng retry phù hợp

Lợi ích:

- nếu Elasticsearch chậm hoặc tạm thời lỗi, log không mất ngay
- tránh nghẽn toàn bộ pipeline khi backend ingest gặp vấn đề
- phù hợp để demo tình huống mất kết nối tạm thời

Đây là cấu hình rất nên có trong báo cáo vì nó thể hiện tính "production-minded".

### 2.6. Có Alert theo số lượng error trong một khoảng thời gian

**Làm được.**

Có 3 hướng khả thi:

#### Hướng 1: Alert ngay trong Kibana / Elasticsearch

- tạo rule đếm số log có `level=error`
- hoặc đếm số `http.response.status_code >= 500`
- cửa sổ thời gian ví dụ 5 phút
- ngưỡng ví dụ lớn hơn 10 bản ghi

Ưu điểm:

- tận dụng stack đang có
- demo dễ

Nhược điểm:

- phụ thuộc license/tính năng sẵn có của bản Elastic đang chạy

#### Hướng 2: Dùng ElastAlert hoặc công cụ ngoài

- query Elasticsearch theo chu kỳ
- gửi email/webhook/Telegram

Ưu điểm:

- tách riêng logic cảnh báo
- linh hoạt

Nhược điểm:

- thêm thành phần mới để vận hành

#### Hướng 3: Dùng Prometheus + exporter/log metrics trung gian

- chuyển số lượng error log thành metric
- alert bằng Alertmanager

Ưu điểm:

- chuẩn theo hệ monitoring hiện đại

Nhược điểm:

- phức tạp hơn nhu cầu hiện tại

**Khuyến nghị cho giai đoạn này:** bắt đầu với alert ngay trong Kibana/Elastic nếu stack hiện tại hỗ trợ; nếu bị giới hạn tính năng thì chuyển sang `ElastAlert 2`.

---

## 3. Kiến trúc đề xuất

Kiến trúc nâng cấp nên đi theo hướng sau:

```text
[ frontend pod ] -----\
[ backend pod ] ------+--> stdout/stderr --> [ Fluent Bit DaemonSet ]
[ database pod ] -----/                           |
[ nginx pod ] --------/                           |
                                                  v
                                   parse + enrich + buffer(memory+disk)
                                                  |
                                                  v
                                  [ Elasticsearch ]
                                   |      |      |
                                   |      |      +--> Index Template + Mapping tĩnh
                                   |      +---------> ILM Policy + Rollover
                                   +----------------> Alert Rule / ElastAlert
                                                  |
                                                  v
                                             [ Kibana ]
```

Kiến trúc này vừa đáp ứng test end-to-end, vừa đủ chặt chẽ để viết báo cáo kỹ thuật.

---

## 4. Thiết kế chi tiết được khuyến nghị

### 4.1. Nhóm workload sinh log

Nên tạo 4 workload tối giản như sau:

#### Frontend

- Có thể dùng container Nginx static hoặc container Node nhỏ
- Sinh log truy cập bình thường và thỉnh thoảng sinh warning
- Nếu muốn mapping đẹp, nên sinh JSON log

#### Backend

- Dùng container Python/Node/BusyBox đơn giản
- In log định kỳ theo các mức `INFO`, `WARN`, `ERROR`
- Có thể chủ động tạo lỗi giả mỗi 30 giây để test alert

#### Database

- Nếu muốn nhẹ: dùng container giả lập ghi log kiểu DB
- Nếu muốn thật hơn: dùng `postgres` hoặc `mysql` với cấu hình log cơ bản
- Chỉ cần mục tiêu có log connect, query lỗi, hoặc auth failed

#### Webserver Nginx

- Pod Nginx riêng
- Bật access log và error log
- Có thể tạo request 404/500 giả để test parser và alert

### 4.2. Thiết kế index

Đề xuất ban đầu:

- `logs-fe-000001`
- `logs-be-000001`
- `logs-db-000001`
- `logs-nginx-000001`

Mỗi nhóm có:

- alias ghi, ví dụ `logs-fe-write`
- index template riêng
- ILM policy chung hoặc riêng

Nếu muốn trình bày chuẩn hơn theo Elasticsearch hiện đại, có thể dùng rollover alias:

- `logs-fe-write -> logs-fe-000001`
- `logs-be-write -> logs-be-000001`
- `logs-db-write -> logs-db-000001`
- `logs-nginx-write -> logs-nginx-000001`

Fluent Bit sẽ route theo tag hoặc field để đẩy vào alias tương ứng.

### 4.3. Mapping tĩnh

Nên dùng nguyên tắc:

- `dynamic: false`
- chỉ khai báo field thực sự cần truy vấn
- giữ cấu trúc field thống nhất giữa các service nếu có thể

Ví dụ field chuẩn chung:

- `@timestamp`
- `message`
- `level`
- `service.name`
- `service.component`
- `environment`
- `kubernetes.namespace_name`
- `kubernetes.pod_name`
- `event.dataset`

Ví dụ field riêng:

- FE/BE:
  - `request_id`
  - `user_id`
  - `path`
- Nginx:
  - `client.ip`
  - `url.path`
  - `http.request.method`
  - `http.response.status_code`
- DB:
  - `db.operation`
  - `db.statement`
  - `db.user`
  - `error.code`

### 4.4. ILM policy

Có thể dùng chính sách đơn giản nhưng đúng tư duy:

- rollover sau `1d` hoặc `5gb`
- giữ hot 3 ngày
- xóa sau 7 ngày

Nếu cluster nhỏ:

- chỉ cần `hot + delete`, chưa cần `warm`

Nếu muốn đẹp trong báo cáo:

- mô tả đủ `hot/warm/delete`
- nhưng triển khai thật có thể chỉ bật `hot/delete`

### 4.5. Buffer Fluent Bit

Thiết kế buffer nên bao gồm:

- `storage.path` để bật filesystem buffering
- `storage.sync normal`
- `storage.checksum off` hoặc theo nhu cầu
- input có `Mem_Buf_Limit`
- output có retry hợp lý

Ngoài ra nên xác định:

- thư mục buffer nằm trong `hostPath` hay `emptyDir`
- nếu cần chống mất log khi pod Fluent Bit restart, nên cân nhắc `hostPath`

Khuyến nghị:

- lab/demo: có thể dùng `hostPath` rõ ràng để chứng minh buffer trên node
- nếu ngại phức tạp: dùng `emptyDir` trước, nhưng giá trị báo cáo sẽ thấp hơn

### 4.6. Alert

Luật cảnh báo mẫu:

- Điều kiện: số log có `level=ERROR` từ `backend` lớn hơn 10 trong 5 phút
- Điều kiện: số log Nginx có `status_code >= 500` lớn hơn 20 trong 5 phút
- Điều kiện: số log DB chứa `authentication failed` lớn hơn 5 trong 10 phút

Đầu ra cảnh báo:

- hiển thị trên Kibana
- gửi email
- hoặc webhook tới Telegram/Slack nếu muốn demo bắt mắt hơn

---

## 5. Thứ tự triển khai khuyến nghị

Nên làm theo 6 pha:

### Pha 1. Dựng workload sinh log

Mục tiêu:

- có 4 pod FE/BE/DB/Nginx
- xác nhận log xuất hiện đều và có phân biệt loại

Kết quả mong đợi:

- `kubectl logs` thấy log sinh ra đúng ý
- Fluent Bit đọc được toàn bộ

### Pha 2. Chuẩn hóa parser và tag

Mục tiêu:

- phân loại log rõ ràng theo service
- route được về index mong muốn

Kết quả mong đợi:

- mỗi nguồn log có tag riêng
- document trong Elasticsearch có field chung thống nhất

### Pha 3. Tạo index template + mapping tĩnh

Mục tiêu:

- chặn dynamic mapping
- kiểm soát kiểu dữ liệu ngay từ đầu

Kết quả mong đợi:

- index được tạo theo template
- field đúng kiểu
- không bị nổ mapping linh tinh

### Pha 4. Bật ILM

Mục tiêu:

- rollover tự động
- xóa log cũ theo chính sách

Kết quả mong đợi:

- alias ghi hoạt động đúng
- policy được gắn vào index template

### Pha 5. Bật buffer Fluent Bit

Mục tiêu:

- chống mất log khi Elasticsearch chậm hoặc tạm thời lỗi

Kết quả mong đợi:

- Fluent Bit có buffer memory + disk
- test ngắt kết nối Elasticsearch ngắn hạn mà log vẫn không mất ngay

### Pha 6. Tạo alert

Mục tiêu:

- giám sát được error count theo thời gian

Kết quả mong đợi:

- tạo được ít nhất 1 rule cảnh báo backend error
- test bằng cách sinh lỗi giả và thấy rule kích hoạt

---

## 6. Những điểm cần lưu ý trước khi triển khai thật

### 6.1. Mapping tĩnh sẽ làm lộ ra vấn đề dữ liệu bẩn

Đây không phải nhược điểm, mà là tác dụng phụ tích cực. Nó buộc hệ thống log phải được thiết kế nghiêm túc. Tuy nhiên khi mới bắt đầu, bạn nên giới hạn số field, không tham quá nhiều.

### 6.2. Database pod không nhất thiết phải là database thật

Nếu mục tiêu là kiểm thử logging, có thể dùng container mô phỏng log DB thay vì dựng DB đầy đủ. Cách này nhẹ hơn, dễ kiểm soát log hơn, và vẫn đáp ứng mục tiêu bài toán.

### 6.3. Alert phụ thuộc khả năng của bản Elastic hiện tại

Nếu cluster Elastic/Kibana của bạn đang chạy bản có đủ tính năng rule/alert thì làm rất đẹp. Nếu không, cần chuẩn bị phương án dự phòng là `ElastAlert 2`.

### 6.4. Buffer đĩa cần tính đến dung lượng node

Khi bật filesystem buffer trên Fluent Bit, phải giới hạn rõ:

- tổng kích thước buffer tối đa
- vị trí lưu buffer
- hành vi khi buffer đầy

Nếu không, Elasticsearch nghẽn kéo dài có thể làm đầy disk node.

### 6.5. ILM cần khớp với index alias

ILM không chỉ là tạo policy. Muốn chạy đúng còn cần:

- index template
- rollover alias
- index khởi tạo ban đầu đúng tên

Đây là điểm hay bị sai nếu làm vội.

---

## 7. Đề xuất phương án thực hiện tốt nhất cho project này

Nếu mục tiêu là vừa học, vừa demo, vừa viết báo cáo đẹp, thì phương án tối ưu là:

1. Dựng namespace `dung-lab` với 4 workload sinh log
2. Chuẩn hóa log theo 4 nhóm `fe`, `be`, `db`, `nginx`
3. Thiết kế 4 nhóm index riêng
4. Tạo mapping tĩnh, `dynamic: false`
5. Gắn ILM policy giữ log ngắn ngày
6. Bật memory + filesystem buffer cho Fluent Bit
7. Tạo ít nhất 2 cảnh báo:
   - backend error count
   - nginx 5xx count

Đây là phương án đủ mạnh để chứng minh rằng hệ thống logging không chỉ "gom log lên Kibana", mà đã tiến gần tư duy production:

- có nguồn log đa dạng
- có chuẩn hóa dữ liệu
- có quản lý vòng đời lưu trữ
- có cơ chế chống nghẽn ingestion
- có cảnh báo chủ động

---

## 8. Kết luận cuối cùng

Về mặt ý tưởng, **toàn bộ yêu cầu đều khả thi** và phù hợp để triển khai tiếp trên hệ thống hiện tại của bạn.

Đây không phải là một bước nâng cấp nhỏ, mà là chuyển từ mô hình:

- "gom log để xem"

sang mô hình:

- "thiết kế một nền tảng logging có quy hoạch"

Nếu triển khai đầy đủ, hệ thống của bạn sẽ có các đặc điểm rất đáng giá trong báo cáo:

- có môi trường test sinh log đa tầng FE/BE/DB/Webserver
- có index design rõ ràng
- có mapping tĩnh, không phụ thuộc dynamic
- có ILM để kiểm soát dung lượng Elasticsearch
- có Fluent Bit buffer để tăng độ bền pipeline
- có alert để giám sát chủ động

Nói ngắn gọn: **làm được, làm đúng hướng, và rất đáng làm.**

---

## 9. Báo cáo bổ sung: Cách tạo 4 Pod Python chuyên dùng để sinh log

### 9.1. Mục tiêu

Phần này mô tả cách tạo 4 Pod rất nhẹ trong Kubernetes để chuyên dùng cho mục đích sinh log phục vụ kiểm thử hệ thống logging.

Mục tiêu của 4 Pod này không phải chạy ứng dụng thật, mà là:

- tạo nhiều loại log khác nhau
- tạo được log định kỳ và có chủ đích
- dễ kiểm soát nội dung log để test parser, mapping, index, alert
- nhẹ, dễ xóa, dễ dựng lại

Giải pháp được đề xuất là dùng **Python** để giả lập 4 vai trò:

- `fe-log-generator`
- `be-log-generator`
- `db-log-generator`
- `web-log-generator`

Tất cả đều ghi log ra `stdout`, để Kubernetes ghi ra file container log, sau đó Fluent Bit sẽ thu thập.

### 9.2. Có nên dùng Python không?

**Có, rất phù hợp.**

Python là lựa chọn tốt vì:

- viết script sinh log rất nhanh
- dễ tạo log text hoặc JSON
- dễ tạo lỗi giả lập
- không cần cài hệ thống nặng
- dễ thay đổi chu kỳ log, nội dung log, mức độ lỗi

So với việc dựng frontend thật, backend thật, database thật:

- nhẹ hơn rất nhiều
- ít tốn CPU/RAM hơn
- không phải cấu hình service phức tạp
- rất phù hợp cho môi trường lab và báo cáo

### 9.3. Ý tưởng thiết kế 4 Pod

#### Pod FE

Vai trò:

- giả lập frontend
- sinh log truy cập người dùng
- sinh warning khi request chậm

Loại log nên tạo:

- `INFO` khi người dùng truy cập trang
- `WARN` khi thời gian phản hồi cao
- `ERROR` giả lập lỗi tải tài nguyên tĩnh

Ví dụ nội dung:

```json
{
  "service": "frontend",
  "level": "INFO",
  "event": "page_view",
  "path": "/home",
  "user_id": "u001"
}
```

#### Pod BE

Vai trò:

- giả lập backend API
- sinh log nghiệp vụ
- thỉnh thoảng sinh lỗi 500 để test alert

Loại log nên tạo:

- `INFO` request xử lý bình thường
- `WARN` request chậm
- `ERROR` exception giả lập

Ví dụ nội dung:

```json
{
  "service": "backend",
  "level": "ERROR",
  "event": "api_failure",
  "endpoint": "/api/orders",
  "status_code": 500,
  "error_code": "ORDER_TIMEOUT"
}
```

#### Pod DB

Vai trò:

- giả lập database log
- không cần chạy PostgreSQL/MySQL thật
- chỉ cần sinh log giống kiểu DB

Loại log nên tạo:

- `INFO` kết nối thành công
- `WARN` query chậm
- `ERROR` lỗi xác thực hoặc deadlock giả lập

Ví dụ nội dung:

```json
{
  "service": "database",
  "level": "WARN",
  "event": "slow_query",
  "duration_ms": 1820,
  "db_name": "appdb",
  "query_type": "SELECT"
}
```

#### Pod WEB

Vai trò:

- giả lập webserver
- nếu muốn thuần Python thì có thể tạo log kiểu access/error
- nếu muốn thật hơn thì sau này thay bằng Nginx

Loại log nên tạo:

- access log kiểu HTTP
- error log kiểu webserver
- status 200, 404, 500

Ví dụ nội dung:

```json
{
  "service": "webserver",
  "level": "INFO",
  "event": "access_log",
  "method": "GET",
  "path": "/images/logo.png",
  "status_code": 404,
  "client_ip": "10.42.0.15"
}
```

### 9.4. Tại sao nên ghi log ra stdout?

Trong Kubernetes, cách đúng và đơn giản nhất là để container ghi log ra:

- `stdout`
- `stderr`

Lý do:

- Kubernetes tự gom log container
- Fluent Bit đang đọc trực tiếp từ `/var/log/containers/*.log`
- không cần mount file log riêng
- triển khai rất gọn

Vì vậy các script Python chỉ cần dùng `print(...)` hoặc `logging.StreamHandler(sys.stdout)`.

### 9.5. Cách tổ chức triển khai trong Kubernetes

Khuyến nghị tạo một namespace riêng:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dung-lab
```

Sau đó triển khai 4 `Deployment`, mỗi Deployment 1 replica.

Lý do dùng `Deployment` thay vì `Pod` thuần:

- dễ xóa và tạo lại
- tự restart nếu container lỗi
- đúng cách triển khai K8s hơn
- có thể scale lên khi cần test tải

Mỗi Deployment nên gắn label rõ ràng:

- `app: fe-log-generator`
- `app: be-log-generator`
- `app: db-log-generator`
- `app: web-log-generator`

và thêm:

- `tier: fe|be|db|web`
- `project: dung-lab`

Những label này sẽ rất hữu ích cho Fluent Bit, Kibana, và alert rule.

### 9.6. Cách viết script Python sinh log

Mỗi Pod chỉ cần một file Python rất ngắn, chạy vòng lặp vô hạn:

1. sinh dữ liệu log
2. in ra màn hình theo dạng JSON
3. ngủ vài giây
4. lặp lại

Ý tưởng chung:

```python
import json
import random
import time
from datetime import datetime, timezone

SERVICE = "frontend"

while True:
    log = {
        "@timestamp": datetime.now(timezone.utc).isoformat(),
        "service": SERVICE,
        "level": random.choice(["INFO", "INFO", "WARN", "ERROR"]),
        "message": "demo log from frontend"
    }
    print(json.dumps(log), flush=True)
    time.sleep(2)
```

Điểm quan trọng:

- nên in log dạng JSON để dễ mapping
- luôn có `@timestamp`
- luôn có `service`
- luôn có `level`
- luôn có `message`
- thêm field riêng cho từng loại Pod

### 9.7. Thiết kế log chuẩn cho 4 Pod

Để sau này dễ làm mapping tĩnh, nên thống nhất bộ field chung.

#### Field chung

Tất cả 4 Pod nên có:

- `@timestamp`
- `service`
- `level`
- `message`
- `event`
- `environment`

#### Field riêng theo từng Pod

FE:

- `path`
- `user_id`
- `session_id`
- `response_time_ms`

BE:

- `endpoint`
- `request_id`
- `status_code`
- `error_code`

DB:

- `db_name`
- `query_type`
- `duration_ms`
- `db_user`

WEB:

- `method`
- `path`
- `status_code`
- `client_ip`

Nhờ đó sau này khi tắt `dynamic mapping`, việc định nghĩa schema sẽ dễ và sạch hơn.

### 9.8. Có thể làm nhẹ tới mức nào?

Có thể làm rất nhẹ.

#### Phương án nhẹ nhất

- dùng image `python:3.11-alpine`
- mỗi Pod chỉ chạy 1 script Python
- không cần mở port
- không cần Service
- chỉ cần Deployment

Đây là lựa chọn phù hợp nhất nếu mục tiêu là chỉ sinh log.

#### Phương án trung bình

- tự build image Python nhỏ hơn
- có ConfigMap chứa script
- mount script vào container

Ưu điểm:

- không cần build nhiều image khác nhau
- dễ sửa script ngay trong manifest

Khuyến nghị cho project hiện tại:

- dùng `ConfigMap + python:3.11-alpine`

Vì:

- nhanh làm
- dễ đọc trong báo cáo
- dễ đổi nội dung log mà không phải build lại image liên tục

### 9.9. Cấu trúc triển khai được khuyến nghị

Nên dùng mô hình:

- `1 Namespace`
- `4 ConfigMap`
- `4 Deployment`

Hoặc gọn hơn:

- `1 Namespace`
- `1 ConfigMap` chứa 4 script
- `4 Deployment` dùng chung image Python

Mô hình tối ưu nhất cho bài toán này là:

```text
dung-lab/
  - namespace.yaml
  - configmap-log-scripts.yaml
  - deploy-fe.yaml
  - deploy-be.yaml
  - deploy-db.yaml
  - deploy-web.yaml
```

### 9.10. Cách test sau khi tạo

Sau khi triển khai, có thể kiểm tra theo thứ tự:

#### Kiểm tra Pod chạy

```bash
kubectl get pods -n dung-lab
```

#### Kiểm tra log từng Pod

```bash
kubectl logs -n dung-lab deploy/fe-log-generator
kubectl logs -n dung-lab deploy/be-log-generator
kubectl logs -n dung-lab deploy/db-log-generator
kubectl logs -n dung-lab deploy/web-log-generator
```

#### Kiểm tra Fluent Bit đã đọc được chưa

```bash
kubectl logs -n elk -l app.kubernetes.io/name=fluent-bit --tail=100
```

#### Kiểm tra trên Kibana

Tìm theo:

- `kubernetes.namespace_name: "dung-lab"`
- `service: "frontend"`
- `service: "backend"`
- `level: "ERROR"`

### 9.11. Ưu điểm và hạn chế của phương án 4 Pod Python

#### Ưu điểm

- rất nhẹ
- cực dễ tạo
- dễ chủ động nội dung log
- dễ sinh lỗi giả
- dễ kiểm tra alert
- phù hợp để nghiên cứu parser, mapping, index design

#### Hạn chế

- không phải log "thật" của hệ thống production
- log webserver và DB chỉ là log mô phỏng
- nếu muốn sát thực tế hơn thì sau này nên thay Pod web bằng Nginx thật và Pod DB bằng PostgreSQL/MySQL thật

Điều này không phải vấn đề lớn ở giai đoạn hiện tại, vì mục tiêu của bạn đang là:

- kiểm thử pipeline logging
- kiểm chứng thiết kế
- làm báo cáo kỹ thuật

### 9.12. Kết luận

Việc tạo 4 Pod Python chuyên dùng để sinh log là **hoàn toàn khả thi, nhẹ, dễ làm và rất phù hợp** với project hiện tại.

Đây là lựa chọn tốt vì:

- triển khai nhanh
- ít tốn tài nguyên
- dễ kiểm soát dữ liệu đầu vào
- hỗ trợ rất tốt cho các bước nâng cao phía sau như:
  - index design
  - mapping tĩnh
  - ILM
  - buffer Fluent Bit
  - alert theo error count

Nếu cần mức độ thực tế cao hơn, sau này có thể nâng cấp dần:

- giữ `frontend` và `backend` là Python
- thay `webserver` bằng Nginx thật
- thay `database` bằng PostgreSQL hoặc MySQL thật

Nhưng cho giai đoạn hiện tại, phương án **4 Pod Python sinh log** là đủ tốt, hợp lý và tiết kiệm nhất.

---

## 10. Hướng dẫn triển khai thực tế 4 Pod Python sinh log

Phần này viết theo hướng có thể mang đi triển khai luôn. Cách làm được khuyến nghị là:

- tạo `namespace` riêng
- tạo `ConfigMap` chứa 4 file Python
- tạo 4 `Deployment`
- tất cả dùng chung image `python:3.11-alpine`

Ưu điểm của cách này:

- không cần build image riêng
- sửa nội dung sinh log rất nhanh
- nhẹ, dễ rollback, dễ demo

### 10.1. Tạo Namespace

Manifest:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dung-lab
```

Lệnh tạo nhanh:

```bash
kubectl create namespace dung-lab
```

Lệnh áp dụng:

```bash
kubectl apply -f namespace.yaml
```

Lệnh kiểm tra lại:

```bash
kubectl get namespace dung-lab
```

### 10.2. Tạo ConfigMap chứa 4 script Python

Tạo file `configmap-log-scripts.yaml` với nội dung sau:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: log-generator-scripts
  namespace: dung-lab
data:
  fe.py: |
    import json
    import random
    import time
    from datetime import datetime, timezone

    paths = ["/", "/home", "/login", "/products", "/cart"]

    while True:
        payload = {
            "@timestamp": datetime.now(timezone.utc).isoformat(),
            "service": "frontend",
            "level": random.choice(["INFO", "INFO", "INFO", "WARN", "ERROR"]),
            "event": random.choice(["page_view", "asset_load", "ui_action"]),
            "environment": "lab",
            "path": random.choice(paths),
            "user_id": f"u{random.randint(1, 20):03}",
            "session_id": f"s{random.randint(1000, 9999)}",
            "response_time_ms": random.randint(20, 1500),
            "message": "frontend generated log"
        }
        print(json.dumps(payload), flush=True)
        time.sleep(2)

  be.py: |
    import json
    import random
    import time
    from datetime import datetime, timezone

    endpoints = ["/api/login", "/api/orders", "/api/profile", "/api/payment"]

    while True:
        status_code = random.choice([200, 200, 200, 201, 400, 500, 503])
        level = "ERROR" if status_code >= 500 else ("WARN" if status_code >= 400 else "INFO")
        if status_code >= 500:
            error_code = random.choice(["ORDER_TIMEOUT", "DB_CONN_FAIL", "INTERNAL_ERROR"])
        elif status_code >= 400:
            error_code = "BAD_REQUEST"
        else:
            error_code = None
        payload = {
            "@timestamp": datetime.now(timezone.utc).isoformat(),
            "service": "backend",
            "level": level,
            "event": "api_request",
            "environment": "lab",
            "endpoint": random.choice(endpoints),
            "request_id": f"req-{random.randint(10000, 99999)}",
            "status_code": status_code,
            "message": "backend generated log"
        }
        if error_code:
            payload["error_code"] = error_code
        print(json.dumps(payload), flush=True)
        time.sleep(3)

  db.py: |
    import json
    import random
    import time
    from datetime import datetime, timezone

    query_types = ["SELECT", "INSERT", "UPDATE", "DELETE"]
    events = ["connection_ok", "slow_query", "auth_failed", "deadlock_detected"]

    while True:
        event = random.choice(events)
        level = "INFO"
        if event == "slow_query":
            level = "WARN"
        elif event in ["auth_failed", "deadlock_detected"]:
            level = "ERROR"

        payload = {
            "@timestamp": datetime.now(timezone.utc).isoformat(),
            "service": "database",
            "level": level,
            "event": event,
            "environment": "lab",
            "db_name": "appdb",
            "query_type": random.choice(query_types),
            "duration_ms": random.randint(5, 3000),
            "db_user": random.choice(["app_user", "report_user", "admin"]),
            "message": "database generated log"
        }
        print(json.dumps(payload), flush=True)
        time.sleep(4)

  web.py: |
    import json
    import random
    import time
    from datetime import datetime, timezone

    methods = ["GET", "POST"]
    paths = ["/", "/index.html", "/healthz", "/images/logo.png", "/api/proxy"]

    while True:
        status_code = random.choice([200, 200, 200, 404, 500, 502])
        level = "ERROR" if status_code >= 500 else ("WARN" if status_code == 404 else "INFO")
        payload = {
            "@timestamp": datetime.now(timezone.utc).isoformat(),
            "service": "webserver",
            "level": level,
            "event": "access_log",
            "environment": "lab",
            "method": random.choice(methods),
            "path": random.choice(paths),
            "status_code": status_code,
            "client_ip": f"10.42.0.{random.randint(2, 254)}",
            "message": "web generated log"
        }
        print(json.dumps(payload), flush=True)
        time.sleep(2)
```

Lệnh áp dụng:

```bash
kubectl apply -f configmap-log-scripts.yaml
```

### 10.3. Tạo Deployment cho Pod FE

Tạo file `deploy-fe.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fe-log-generator
  namespace: dung-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fe-log-generator
  template:
    metadata:
      labels:
        app: fe-log-generator
        tier: fe
        project: dung-lab
    spec:
      containers:
      - name: fe
        image: python:3.11-alpine
        command: ["python", "/scripts/fe.py"]
        env:
        - name: PYTHONUNBUFFERED
          value: "1"
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: scripts
        configMap:
          name: log-generator-scripts
```

### 10.4. Tạo Deployment cho Pod BE

Tạo file `deploy-be.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: be-log-generator
  namespace: dung-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: be-log-generator
  template:
    metadata:
      labels:
        app: be-log-generator
        tier: be
        project: dung-lab
    spec:
      containers:
      - name: be
        image: python:3.11-alpine
        command: ["python", "/scripts/be.py"]
        env:
        - name: PYTHONUNBUFFERED
          value: "1"
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: scripts
        configMap:
          name: log-generator-scripts
```

### 10.5. Tạo Deployment cho Pod DB

Tạo file `deploy-db.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db-log-generator
  namespace: dung-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db-log-generator
  template:
    metadata:
      labels:
        app: db-log-generator
        tier: db
        project: dung-lab
    spec:
      containers:
      - name: db
        image: python:3.11-alpine
        command: ["python", "/scripts/db.py"]
        env:
        - name: PYTHONUNBUFFERED
          value: "1"
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: scripts
        configMap:
          name: log-generator-scripts
```

### 10.6. Tạo Deployment cho Pod WEB

Tạo file `deploy-web.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-log-generator
  namespace: dung-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-log-generator
  template:
    metadata:
      labels:
        app: web-log-generator
        tier: web
        project: dung-lab
    spec:
      containers:
      - name: web
        image: python:3.11-alpine
        command: ["python", "/scripts/web.py"]
        env:
        - name: PYTHONUNBUFFERED
          value: "1"
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: scripts
        configMap:
          name: log-generator-scripts
```

### 10.7. Thứ tự chạy lệnh triển khai

Sau khi tạo các file YAML bên trên, chạy lần lượt:

```bash
kubectl apply -f namespace.yaml
kubectl apply -f configmap-log-scripts.yaml
kubectl apply -f deploy-fe.yaml
kubectl apply -f deploy-be.yaml
kubectl apply -f deploy-db.yaml
kubectl apply -f deploy-web.yaml
```

Hoặc nếu gom chung vào một file lớn thì chỉ cần:

```bash
kubectl apply -f dung-lab.yaml
```

### 10.8. Kiểm tra 4 Pod đã chạy

```bash
kubectl get pods -n dung-lab
```

Kết quả mong đợi:

- có 4 pod
- trạng thái `Running`
- mỗi pod `1/1`

### 10.9. Kiểm tra log từng Pod

```bash
kubectl logs -n dung-lab deploy/fe-log-generator --tail=20
kubectl logs -n dung-lab deploy/be-log-generator --tail=20
kubectl logs -n dung-lab deploy/db-log-generator --tail=20
kubectl logs -n dung-lab deploy/web-log-generator --tail=20
```

Bạn sẽ thấy log JSON được in ra liên tục.

### 10.10. Kiểm tra Fluent Bit đã thu được log chưa

```bash
kubectl logs -n elk -l app.kubernetes.io/name=fluent-bit --tail=100
```

Sau đó vào Kibana và tìm:

- `kubernetes.namespace_name: "dung-lab"`
- `service: "frontend"`
- `service: "backend"`
- `service: "database"`
- `service: "webserver"`

### 10.11. Khuyến nghị thực tế khi tạo 4 Pod này

- Nên để toàn bộ log ở dạng JSON ngay từ đầu
- Nên thống nhất field `@timestamp`, `service`, `level`, `event`, `message`
- Nên cố tình sinh một phần log lỗi để test alert
- Nên để chu kỳ sinh log khác nhau giữa các Pod để dữ liệu trông tự nhiên hơn

### 10.12. Kết luận triển khai

Đây là cách tạo 4 Pod đơn giản nhất nhưng vẫn đủ tốt để phục vụ toàn bộ các bước tiếp theo:

- kiểm tra Fluent Bit ingest
- thiết kế index riêng
- tạo mapping tĩnh
- thử ILM
- test buffer
- tạo alert theo số lượng error

Nếu cần mức sát thực tế cao hơn ở bước sau, có thể giữ nguyên `fe` và `be` bằng Python, rồi thay `web` bằng Nginx thật và `db` bằng PostgreSQL/MySQL thật.

---

## 11. Cách triển khai 4 Pod sao cho cô lập, dễ xóa tạo lại, không ảnh hưởng tài nguyên khác

Đây là cách nên làm nhất trong môi trường công ty, vì mục tiêu của bạn không phải chỉ "chạy được", mà còn phải:

- dễ kiểm soát phạm vi ảnh hưởng
- dễ dọn dẹp sạch
- dễ tạo lại nhiều lần
- không đụng vào namespace và workload đang chạy thật

### 11.1. Nguyên tắc tổng thể

Phương án an toàn nhất là:

1. tạo **namespace riêng hoàn toàn**
2. đặt **tên tài nguyên có prefix riêng**
3. gom toàn bộ manifest vào **một thư mục riêng**
4. gắn **label thống nhất** cho toàn bộ tài nguyên
5. nếu cần thì giới hạn tài nguyên bằng `ResourceQuota` và `LimitRange`

Nhờ đó:

- khi cần xóa, chỉ cần xóa đúng namespace hoặc đúng bộ label
- không đụng vào `elk`, `argocd`, `keycloak`, hay workload công ty
- dễ chứng minh trong báo cáo là hệ thống test của bạn được cô lập

### 11.2. Nên dùng namespace riêng

Khuyến nghị tạo namespace riêng, ví dụ:

- `dung-lab`

Không nên tạo 4 pod này trong:

- `default`
- `elk`
- hoặc bất kỳ namespace production nào

Lợi ích của namespace riêng:

- tài nguyên của bạn tách biệt hoàn toàn
- `kubectl get pods -n dung-lab` là thấy đúng đồ của bạn
- xóa sạch chỉ cần:

```bash
kubectl delete namespace dung-lab
```

Đây là cách dọn dẹp sạch nhất.

### 11.3. Nên dùng Deployment thay vì Pod thuần

Không nên tạo `Pod` trần nếu bạn định test lâu dài.

Nên dùng:

- `Deployment` cho từng thành phần `fe`, `be`, `db`, `web`

Lý do:

- pod chết sẽ tự lên lại
- dễ sửa image/command/config
- dễ xóa tạo lại từng nhóm
- đúng kiểu quản trị K8s hơn

Ví dụ:

- `dung-fe-log-generator`
- `dung-be-log-generator`
- `dung-db-log-generator`
- `dung-web-log-generator`

### 11.4. Đặt tên có prefix riêng của bạn

Rất nên thêm prefix riêng, ví dụ `dung-` hoặc `lab-dung-`.

Ví dụ:

- namespace: `dung-lab`
- configmap: `dung-log-generator-scripts`
- deployment: `dung-fe-log-generator`
- deployment: `dung-be-log-generator`
- deployment: `dung-db-log-generator`
- deployment: `dung-web-log-generator`

Lợi ích:

- tránh trùng tên với tài nguyên người khác
- nhìn vào là biết tài nguyên của ai
- xóa chọn lọc rất dễ

### 11.5. Gắn label thống nhất cho toàn bộ tài nguyên

Mỗi tài nguyên nên có bộ label chung như sau:

```yaml
labels:
  owner: dung
  project: dung-lab
  purpose: log-testing
```

Ngoài ra mỗi pod nên có label riêng theo loại:

```yaml
labels:
  component: fe
```

hoặc:

```yaml
labels:
  component: be
```

Lợi ích:

- lọc tài nguyên dễ
- Fluent Bit/Kibana có thể dựa vào label
- xóa nhanh bằng label selector

Ví dụ:

```bash
kubectl get all -n dung-lab -l owner=dung
kubectl delete all -n dung-lab -l owner=dung
```

### 11.6. Gom manifest vào một thư mục riêng

Nên tạo một thư mục riêng trong repo, ví dụ:

```text
k8s-dung-lab/
  namespace.yaml
  configmap-log-scripts.yaml
  deploy-fe.yaml
  deploy-be.yaml
  deploy-db.yaml
  deploy-web.yaml
  quota.yaml
```

Khi đó:

- triển khai:

```bash
kubectl apply -f k8s-dung-lab/
```

- xóa:

```bash
kubectl delete -f k8s-dung-lab/
```

Đây là cách rất sạch và dễ quản lý vòng đời test.

### 11.7. Nếu muốn cực gọn, dùng 1 file tổng

Ngoài cách chia nhiều file, bạn có thể gom toàn bộ vào một file:

- `dung-lab.yaml`

Rồi:

```bash
kubectl apply -f dung-lab.yaml
kubectl delete -f dung-lab.yaml
```

Cách này tiện khi demo nhanh, nhưng về lâu dài thì thư mục nhiều file sẽ dễ đọc hơn.

### 11.8. Giới hạn tài nguyên để tránh ảnh hưởng cluster

Đây là điểm rất nên có trong môi trường công ty.

Bạn nên giới hạn tài nguyên mỗi pod:

- `cpu: 50m - 100m`
- `memory: 64Mi - 128Mi`

Ngoài ra có thể tạo thêm `ResourceQuota` cho namespace:

- tổng CPU tối đa
- tổng RAM tối đa
- tổng số pod tối đa

Ví dụ tư duy:

- namespace này chỉ được tối đa 6 pod
- tổng RAM tối đa 1Gi
- tổng CPU tối đa 500m hoặc 1 core

Nhờ đó nếu cấu hình sai, workload của bạn cũng khó ảnh hưởng lên cluster chung.

### 11.9. Có thể thêm LimitRange

`LimitRange` giúp ép mỗi container phải có request/limit mặc định.

Lợi ích:

- tránh quên khai báo resources
- tránh pod ăn tài nguyên quá đà

Nếu làm bài bản, namespace của bạn nên có:

- `Namespace`
- `ResourceQuota`
- `LimitRange`
- `ConfigMap`
- `4 Deployment`

### 11.10. Không nên tạo PVC nếu chưa cần

4 pod sinh log kiểu Python chỉ cần:

- image Python
- ConfigMap mount script

Không nên thêm:

- PVC
- Service
- Ingress
- NodePort

trừ khi thật sự cần.

Lý do:

- càng ít tài nguyên phụ, càng dễ cô lập
- xóa càng sạch
- giảm nguy cơ ảnh hưởng hệ thống khác

### 11.11. Cách xóa và tạo lại an toàn

Có 3 mức xóa nên dùng:

#### Mức 1. Xóa từng deployment

```bash
kubectl delete deployment dung-fe-log-generator -n dung-lab
```

Phù hợp khi chỉ muốn thay 1 pod.

#### Mức 2. Xóa toàn bộ theo manifest

```bash
kubectl delete -f k8s-dung-lab/
```

Phù hợp khi muốn reset cả lab của bạn nhưng vẫn giữ namespace nếu manifest không chứa namespace.

#### Mức 3. Xóa cả namespace

```bash
kubectl delete namespace dung-lab
```

Đây là cách sạch nhất khi muốn dọn toàn bộ mọi thứ của bạn.

Sau đó tạo lại:

```bash
kubectl apply -f k8s-dung-lab/
```

### 11.12. Phương án khuyến nghị mạnh nhất

Trong bối cảnh cụm công ty, mình khuyên bạn dùng đúng mô hình này:

1. Tạo namespace riêng `dung-lab`
2. Tạo 1 ConfigMap chứa 4 script Python
3. Tạo 4 Deployment có prefix `dung-`
4. Gắn label chung `owner=dung`, `project=dung-lab`
5. Gắn resource requests/limits nhỏ
6. Thêm `ResourceQuota` cho namespace
7. Triển khai bằng một thư mục manifest riêng

Đây là mô hình vừa an toàn vừa chuyên nghiệp.

### 11.13. Kết luận

Nếu mục tiêu là dễ kiểm soát và cô lập hoàn toàn phần lab của riêng bạn, thì cách tốt nhất là:

- **namespace riêng**
- **Deployment thay vì Pod thuần**
- **label thống nhất**
- **manifest riêng**
- **quota tài nguyên**

Nói ngắn gọn:

- tạo riêng
- quản lý riêng
- xóa riêng
- không đụng tới tài nguyên chung

Đó là cách phù hợp nhất để làm trên cụm công ty.

---

## 11. Cấu hình Fluent Bit: Parser JSON và Routing theo service

### 11.1. Vấn đề cần giải quyết

Khi 4 Pod Python ghi log JSON ra stdout, Kubernetes sẽ lưu vào file `/var/log/containers/*.log` dưới dạng:

```json
{"log":"{\"service\":\"frontend\",\"level\":\"INFO\",...}\n","stream":"stdout","time":"2026-04-03T..."}
```

Nghĩa là toàn bộ JSON log của script Python nằm BÊN TRONG field `log` dưới dạng chuỗi. Fluent Bit cần:

1. **Parse** field `log` từ chuỗi thành các field riêng biệt
2. **Route** log theo giá trị field `service` vào các index Elasticsearch tương ứng

### 11.2. Cấu hình Parser

Thêm parser JSON vào file `parsers.conf` của Fluent Bit:

```ini
[PARSER]
    Name        json_log
    Format      json
    Time_Key    @timestamp
    Time_Format %Y-%m-%dT%H:%M:%S.%L%z
    Time_Keep   On
```

Giải thích:

- `Format json`: parse chuỗi JSON thành các field
- `Time_Key @timestamp`: lấy field `@timestamp` trong JSON làm timestamp chính
- `Time_Keep On`: giữ lại field `@timestamp` trong document sau khi parse

### 11.3. Cấu hình Filter để parse log từ namespace dung-lab

Trong file cấu hình Fluent Bit chính, thêm filter:

```ini
[FILTER]
    Name         parser
    Match        kube.var.log.containers.*dung-lab*
    Key_Name     log
    Parser       json_log
    Reserve_Data On
    Preserve_Key Off
```

Giải thích:

- `Match kube.var.log.containers.*dung-lab*`: chỉ áp dụng cho log từ namespace `dung-lab`
- `Key_Name log`: parse nội dung field `log`
- `Reserve_Data On`: giữ lại các field khác như metadata Kubernetes
- `Preserve_Key Off`: bỏ field `log` gốc sau khi đã parse xong

Sau khi filter này chạy, một record sẽ có dạng:

```json
{
  "service": "frontend",
  "level": "INFO",
  "event": "page_view",
  "message": "frontend generated log",
  "kubernetes": {
    "namespace_name": "dung-lab",
    "pod_name": "fe-log-generator-xxx"
  }
}
```

### 11.4. Cấu hình Routing theo service

Để đẩy log từ mỗi service vào index riêng, dùng `rewrite_tag` filter kết hợp với nhiều output:

```ini
# --- Bước 1: Rewrite tag dựa trên field service ---

[FILTER]
    Name          rewrite_tag
    Match         kube.var.log.containers.*dung-lab*
    Rule          $service ^(frontend)$   logs.fe   false
    Rule          $service ^(backend)$    logs.be   false
    Rule          $service ^(database)$   logs.db   false
    Rule          $service ^(webserver)$  logs.web  false
    Emitter_Name  re_emitted_logs

# --- Bước 2: Output riêng cho từng nhóm ---

[OUTPUT]
    Name              es
    Match             logs.fe
    Host              elasticsearch-master
    Port              9200
    HTTP_User         elastic
    HTTP_Passwd       ${ES_PASSWORD}
    Index             logs-fe-write
    Suppress_Type_Name On
    Retry_Limit       5
    tls               Off

[OUTPUT]
    Name              es
    Match             logs.be
    Host              elasticsearch-master
    Port              9200
    HTTP_User         elastic
    HTTP_Passwd       ${ES_PASSWORD}
    Index             logs-be-write
    Suppress_Type_Name On
    Retry_Limit       5
    tls               Off

[OUTPUT]
    Name              es
    Match             logs.db
    Host              elasticsearch-master
    Port              9200
    HTTP_User         elastic
    HTTP_Passwd       ${ES_PASSWORD}
    Index             logs-db-write
    Suppress_Type_Name On
    Retry_Limit       5
    tls               Off

[OUTPUT]
    Name              es
    Match             logs.web
    Host              elasticsearch-master
    Port              9200
    HTTP_User         elastic
    HTTP_Passwd       ${ES_PASSWORD}
    Index             logs-nginx-write
    Suppress_Type_Name On
    Retry_Limit       5
    tls               Off
```

Giải thích:

- `rewrite_tag` đọc field `service` trong mỗi record
- Nếu `service=frontend` → tag mới là `logs.fe`
- Mỗi output `Match` theo tag mới để ghi vào đúng index alias
- `Suppress_Type_Name On` cần thiết cho Elasticsearch 8.x
- `false` ở cuối mỗi Rule nghĩa là: KHÔNG giữ lại record gốc, chỉ giữ record đã rewrite tag

### 11.5. Lưu ý quan trọng về thứ tự filter

Fluent Bit xử lý filter theo thứ tự khai báo. Phải đảm bảo:

1. **Parser filter** chạy TRƯỚC rewrite_tag (để field `service` đã được extract)
2. **Kubernetes filter** nếu có, chạy trước parser
3. **Rewrite_tag** chạy sau cùng

Thứ tự đúng:

```text
INPUT → kubernetes_filter → parser_filter → rewrite_tag → OUTPUT
```

---

## 12. Elasticsearch: Tạo ILM Policy, Index Template và Rollover Alias

### 12.1. Mục tiêu

Phần này cung cấp các API call cụ thể cần chạy trên Elasticsearch TRƯỚC KHI Fluent Bit bắt đầu gửi log vào các index mới. Thứ tự thực hiện:

1. Tạo ILM policy
2. Tạo index template (chứa mapping tĩnh + gắn ILM)
3. Tạo bootstrap index + write alias

### 12.2. Tạo ILM Policy

Chính sách giữ log phù hợp cho môi trường lab:

```bash
PUT _ilm/policy/logs-lab-policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_age": "1d",
            "max_primary_shard_size": "5gb"
          }
        }
      },
      "delete": {
        "min_age": "7d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

Giải thích:

- `hot` phase: index hiện tại đang nhận log
- `rollover` sẽ kích hoạt khi index đạt 1 ngày tuổi HOẶC primary shard đạt 5GB
- `delete` phase: xóa index sau 7 ngày tính từ khi rollover
- Không cần `warm` phase cho cluster nhỏ, tiết kiệm tài nguyên

Kiểm tra policy đã tạo:

```bash
GET _ilm/policy/logs-lab-policy
```

### 12.3. Tạo Index Template cho Frontend

```bash
PUT _index_template/logs-fe-template
{
  "index_patterns": ["logs-fe-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "logs-fe-write"
    },
    "mappings": {
      "dynamic": false,
      "properties": {
        "@timestamp":      { "type": "date" },
        "service":          { "type": "keyword" },
        "level":            { "type": "keyword" },
        "event":            { "type": "keyword" },
        "environment":      { "type": "keyword" },
        "message":          { "type": "text" },
        "path":             { "type": "keyword" },
        "user_id":          { "type": "keyword" },
        "session_id":       { "type": "keyword" },
        "response_time_ms": { "type": "integer" },
        "kubernetes": {
          "properties": {
            "namespace_name": { "type": "keyword" },
            "pod_name":       { "type": "keyword" },
            "container_name": { "type": "keyword" },
            "host":           { "type": "keyword" }
          }
        }
      }
    }
  },
  "priority": 200
}
```

Giải thích:

- `index_patterns`: template áp dụng cho mọi index có tên bắt đầu bằng `logs-fe-`
- `number_of_replicas: 0`: cluster lab thường chỉ có 1 node ES, không cần replica
- `dynamic: false`: KHÔNG tự tạo field mới, chỉ index những field đã khai báo
- `priority: 200`: ưu tiên cao hơn template mặc định
- Field riêng cho FE: `path`, `user_id`, `session_id`, `response_time_ms`

### 12.4. Tạo Index Template cho Backend

```bash
PUT _index_template/logs-be-template
{
  "index_patterns": ["logs-be-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "logs-be-write"
    },
    "mappings": {
      "dynamic": false,
      "properties": {
        "@timestamp":   { "type": "date" },
        "service":       { "type": "keyword" },
        "level":         { "type": "keyword" },
        "event":         { "type": "keyword" },
        "environment":   { "type": "keyword" },
        "message":       { "type": "text" },
        "endpoint":      { "type": "keyword" },
        "request_id":    { "type": "keyword" },
        "status_code":   { "type": "integer" },
        "error_code":    { "type": "keyword" },
        "kubernetes": {
          "properties": {
            "namespace_name": { "type": "keyword" },
            "pod_name":       { "type": "keyword" },
            "container_name": { "type": "keyword" },
            "host":           { "type": "keyword" }
          }
        }
      }
    }
  },
  "priority": 200
}
```

### 12.5. Tạo Index Template cho Database

```bash
PUT _index_template/logs-db-template
{
  "index_patterns": ["logs-db-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "logs-db-write"
    },
    "mappings": {
      "dynamic": false,
      "properties": {
        "@timestamp":   { "type": "date" },
        "service":       { "type": "keyword" },
        "level":         { "type": "keyword" },
        "event":         { "type": "keyword" },
        "environment":   { "type": "keyword" },
        "message":       { "type": "text" },
        "db_name":       { "type": "keyword" },
        "query_type":    { "type": "keyword" },
        "duration_ms":   { "type": "integer" },
        "db_user":       { "type": "keyword" },
        "kubernetes": {
          "properties": {
            "namespace_name": { "type": "keyword" },
            "pod_name":       { "type": "keyword" },
            "container_name": { "type": "keyword" },
            "host":           { "type": "keyword" }
          }
        }
      }
    }
  },
  "priority": 200
}
```

### 12.6. Tạo Index Template cho Nginx/Webserver

```bash
PUT _index_template/logs-nginx-template
{
  "index_patterns": ["logs-nginx-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "logs-nginx-write"
    },
    "mappings": {
      "dynamic": false,
      "properties": {
        "@timestamp":   { "type": "date" },
        "service":       { "type": "keyword" },
        "level":         { "type": "keyword" },
        "event":         { "type": "keyword" },
        "environment":   { "type": "keyword" },
        "message":       { "type": "text" },
        "method":        { "type": "keyword" },
        "path":          { "type": "keyword" },
        "status_code":   { "type": "integer" },
        "client_ip":     { "type": "ip" },
        "kubernetes": {
          "properties": {
            "namespace_name": { "type": "keyword" },
            "pod_name":       { "type": "keyword" },
            "container_name": { "type": "keyword" },
            "host":           { "type": "keyword" }
          }
        }
      }
    }
  },
  "priority": 200
}
```

Lưu ý: field `client_ip` dùng kiểu `ip` thay vì `keyword` để hỗ trợ truy vấn CIDR range nếu cần.

### 12.7. Tạo Bootstrap Index + Write Alias

Sau khi có template, cần tạo index đầu tiên có gắn write alias. ILM chỉ hoạt động khi có alias:

```bash
# Frontend
PUT /logs-fe-000001
{
  "aliases": {
    "logs-fe-write": {
      "is_write_index": true
    }
  }
}

# Backend
PUT /logs-be-000001
{
  "aliases": {
    "logs-be-write": {
      "is_write_index": true
    }
  }
}

# Database
PUT /logs-db-000001
{
  "aliases": {
    "logs-db-write": {
      "is_write_index": true
    }
  }
}

# Nginx
PUT /logs-nginx-000001
{
  "aliases": {
    "logs-nginx-write": {
      "is_write_index": true
    }
  }
}
```

Giải thích:

- Tên index phải khớp với pattern trong template, ví dụ `logs-fe-000001` khớp `logs-fe-*`
- `is_write_index: true` cho ES biết đây là index đang nhận dữ liệu ghi
- Khi ILM rollover, ES tự tạo `logs-fe-000002` và chuyển write alias sang index mới
- Fluent Bit luôn ghi vào alias `logs-fe-write`, không cần biết index thật đang là gì

### 12.8. Kiểm tra mọi thứ đã đúng

Sau khi tạo xong, chạy lần lượt để xác nhận:

```bash
# Kiểm tra ILM policy
GET _ilm/policy/logs-lab-policy

# Kiểm tra templates
GET _index_template/logs-fe-template
GET _index_template/logs-be-template
GET _index_template/logs-db-template
GET _index_template/logs-nginx-template

# Kiểm tra index + alias
GET _cat/indices/logs-*?v
GET _cat/aliases/logs-*?v

# Kiểm tra ILM status của index
GET logs-fe-000001/_ilm/explain
```

Kết quả mong đợi:

- 4 index ở trạng thái `hot`
- Mỗi index có write alias tương ứng
- ILM policy `logs-lab-policy` được gắn đúng

### 12.9. Thứ tự thực hiện

Quan trọng: phải làm ĐÚNG thứ tự, nếu không ILM sẽ không hoạt động:

1. Tạo ILM policy trước
2. Tạo 4 index template (template tham chiếu đến policy)
3. Tạo 4 bootstrap index (index tự áp dụng template)
4. Sau đó mới cấu hình Fluent Bit gửi log vào alias

Nếu tạo sai thứ tự, ví dụ tạo index trước template, index sẽ không có mapping/ILM. Lúc đó phải xóa index và tạo lại.

---

## 13. Cấu hình Buffer nâng cao cho Fluent Bit

### 13.1. Mục tiêu

Đảm bảo Fluent Bit không mất log khi Elasticsearch chậm hoặc tạm thời lỗi. Cấu hình kết hợp memory buffer và filesystem buffer.

### 13.2. Cấu hình SERVICE section

```ini
[SERVICE]
    Flush                  5
    Grace                  30
    Log_Level              info
    Daemon                 Off
    Parsers_File           parsers.conf
    HTTP_Server            On
    HTTP_Listen            0.0.0.0
    HTTP_Port              2020
    storage.path           /var/fluent-bit/state
    storage.sync           normal
    storage.checksum       off
    storage.max_chunks_up  128
```

Giải thích:

- `storage.path`: thư mục lưu buffer trên disk; khi memory buffer đầy, Fluent Bit sẽ ghi chunk ra đây
- `storage.sync normal`: ghi buffer theo cơ chế async bình thường, cân bằng giữa hiệu suất và an toàn
- `storage.checksum off`: tắt checksum cho chunk để giảm CPU overhead; bật nếu cần chống corrupt
- `storage.max_chunks_up 128`: số chunk tối đa được nạp vào memory cùng lúc; giới hạn RAM usage

### 13.3. Cấu hình INPUT section

```ini
[INPUT]
    Name              tail
    Tag               kube.*
    Path              /var/log/containers/*.log
    Parser            cri
    DB                /var/fluent-bit/state/tail-db
    DB.locking        true
    Mem_Buf_Limit     10MB
    Skip_Long_Lines   On
    Refresh_Interval  5
    storage.type      filesystem
```

Giải thích:

- `Mem_Buf_Limit 10MB`: giới hạn memory buffer cho input này; nếu Elasticsearch chậm, input sẽ tạm dừng đọc thêm log khi đạt 10MB trong memory
- `storage.type filesystem`: kích hoạt filesystem buffer cho input này; chunk sẽ được ghi ra `storage.path` khi cần
- `DB /var/fluent-bit/state/tail-db`: lưu vị trí đọc file; nếu Fluent Bit restart, nó sẽ tiếp tục từ vị trí cũ thay vì đọc lại từ đầu
- `DB.locking true`: khóa file DB để tránh race condition khi có nhiều process
- `Skip_Long_Lines On`: bỏ qua dòng log quá dài thay vì crash

### 13.4. Cấu hình OUTPUT section có retry

```ini
[OUTPUT]
    Name                    es
    Match                   logs.*
    Host                    elasticsearch-master
    Port                    9200
    HTTP_User               elastic
    HTTP_Passwd             ${ES_PASSWORD}
    Suppress_Type_Name      On
    Retry_Limit             5
    storage.total_limit_size 500MB
    net.keepalive           On
    net.keepalive_idle_timeout 10
    Buffer_Size             5MB
```

Giải thích:

- `Retry_Limit 5`: thử gửi lại tối đa 5 lần nếu Elasticsearch trả lỗi; mỗi lần retry sẽ đợi lâu hơn (exponential backoff)
- `storage.total_limit_size 500MB`: giới hạn tổng dung lượng filesystem buffer cho output này; khi đạt 500MB, chunk cũ nhất sẽ bị drop
- `Buffer_Size 5MB`: kích thước buffer cho mỗi kết nối HTTP tới Elasticsearch
- `net.keepalive On`: giữ kết nối TCP sống để tránh overhead tạo kết nối mới mỗi lần flush

### 13.5. Volume mount trong DaemonSet

Thêm volume vào DaemonSet manifest của Fluent Bit:

```yaml
# Trong spec.template.spec.containers[].volumeMounts
volumeMounts:
- name: fluent-bit-state
  mountPath: /var/fluent-bit/state

# Trong spec.template.spec.volumes
volumes:
- name: fluent-bit-state
  hostPath:
    path: /var/fluent-bit/state
    type: DirectoryOrCreate
```

Giải thích:

- Dùng `hostPath` thay vì `emptyDir` để buffer tồn tại ngay cả khi Pod Fluent Bit bị xóa và tạo lại
- `DirectoryOrCreate`: tự tạo thư mục trên node nếu chưa có
- Khi Fluent Bit restart, nó sẽ đọc lại buffer từ disk và tiếp tục gửi

### 13.6. Cách test buffer hoạt động

Kịch bản test:

1. Đảm bảo 4 Pod dung-lab đang chạy và sinh log
2. Scale Elasticsearch xuống 0 replica để giả lập mất kết nối:
   ```bash
   kubectl scale statefulset elasticsearch-master -n elk --replicas=0
   ```
3. Đợi 1-2 phút, kiểm tra Fluent Bit log:
   ```bash
   kubectl logs -n elk -l app.kubernetes.io/name=fluent-bit --tail=50
   ```
   Mong đợi thấy retry error nhưng Fluent Bit vẫn chạy, không crash
4. Kiểm tra buffer disk đã có dữ liệu (exec vào Fluent Bit pod):
   ```bash
   kubectl exec -n elk <fluent-bit-pod> -- ls -la /var/fluent-bit/state/
   ```
5. Bật lại Elasticsearch:
   ```bash
   kubectl scale statefulset elasticsearch-master -n elk --replicas=1
   ```
6. Đợi Elasticsearch sẵn sàng, sau đó kiểm tra Kibana xem log trong khoảng thời gian ES bị tắt có được gửi lại không

Kết quả mong đợi:

- Fluent Bit retry và gửi thành công log đã buffer
- Không mất log trong khoảng thời gian ES tạm nghỉ (miễn là không vượt quá `storage.total_limit_size`)

---

## 14. Cấu hình Alert: Cảnh báo theo số lượng error

### 14.1. Hướng 1: Alert trong Kibana (Elasticsearch Alerting)

Nếu cluster Elasticsearch đang chạy bản có hỗ trợ Alerting (Basic license trở lên cho ES 7.x/8.x):

#### Tạo rule trong Kibana UI

1. Vào **Kibana → Stack Management → Rules**
2. Chọn **Create rule**
3. Chọn loại rule: **Elasticsearch query**
4. Cấu hình:
   - Name: `Backend Error Alert`
   - Check every: `1 minute`
   - Index: `logs-be-*`
   - Condition: Count of documents where `level` is `ERROR` is above `10` for the last `5 minutes`
5. Action: chọn Log (ghi vào Kibana log) hoặc Email/Webhook nếu đã cấu hình connector

#### Tạo rule bằng API (nếu muốn scripted)

```bash
POST kbn:/api/alerting/rule
{
  "name": "Backend Error Count > 10 in 5min",
  "consumer": "alerts",
  "rule_type_id": ".es-query",
  "schedule": {
    "interval": "1m"
  },
  "params": {
    "index": ["logs-be-*"],
    "timeField": "@timestamp",
    "esQuery": "{\"bool\":{\"filter\":[{\"term\":{\"level\":\"ERROR\"}}]}}",
    "threshold": [10],
    "thresholdComparator": ">",
    "timeWindowSize": 5,
    "timeWindowUnit": "m",
    "size": 100
  },
  "actions": []
}
```

Lưu ý: API Kibana Alerting có thể khác tùy phiên bản. Nên dùng UI để tạo rule cho chắc chắn.

### 14.2. Hướng 2: ElastAlert 2 (phương án dự phòng)

Nếu Kibana Alerting bị hạn chế hoặc muốn tách logic cảnh báo riêng, dùng ElastAlert 2.

#### Cài đặt ElastAlert 2 trên Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elastalert2
  namespace: elk
spec:
  replicas: 1
  selector:
    matchLabels:
      app: elastalert2
  template:
    metadata:
      labels:
        app: elastalert2
    spec:
      containers:
      - name: elastalert2
        image: jertel/elastalert2:latest
        volumeMounts:
        - name: config
          mountPath: /opt/elastalert/config.yaml
          subPath: config.yaml
        - name: rules
          mountPath: /opt/elastalert/rules
      volumes:
      - name: config
        configMap:
          name: elastalert-config
      - name: rules
        configMap:
          name: elastalert-rules
```

#### File cấu hình chính `config.yaml`

```yaml
es_host: elasticsearch-master
es_port: 9200
es_username: elastic
es_password: "your-password"

rules_folder: /opt/elastalert/rules
run_every:
  minutes: 1
buffer_time:
  minutes: 10

writeback_index: elastalert_status
alert_time_limit:
  days: 1
```

#### Rule 1: Backend Error Count

File `backend-error-alert.yaml`:

```yaml
name: "Backend Error Count Alert"
type: frequency
index: logs-be-*

num_events: 10
timeframe:
  minutes: 5

filter:
- term:
    level: "ERROR"

alert:
- debug

alert_text: |
  Backend service has generated more than 10 ERROR logs in the last 5 minutes.
  Number of errors: {0}
  Check Kibana for details.
alert_text_args:
- num_matches
```

Giải thích:

- `type: frequency`: đếm số document khớp điều kiện trong khoảng thời gian
- `num_events: 10`: ngưỡng kích hoạt cảnh báo
- `timeframe: 5 minutes`: cửa sổ thời gian đếm
- `filter`: chỉ đếm document có `level=ERROR`
- `alert: debug`: ghi log cảnh báo ra stdout; có thể thay bằng `email`, `slack`, `telegram`

#### Rule 2: Nginx 5xx Count

File `nginx-5xx-alert.yaml`:

```yaml
name: "Nginx 5xx Error Alert"
type: frequency
index: logs-nginx-*

num_events: 20
timeframe:
  minutes: 5

filter:
- range:
    status_code:
      gte: 500

alert:
- debug

alert_text: |
  Webserver has returned more than 20 responses with status >= 500 in the last 5 minutes.
  Number of 5xx errors: {0}
alert_text_args:
- num_matches
```

#### Rule 3: Database Auth Failed

File `db-auth-failed-alert.yaml`:

```yaml
name: "Database Auth Failed Alert"
type: frequency
index: logs-db-*

num_events: 5
timeframe:
  minutes: 10

filter:
- term:
    event: "auth_failed"

alert:
- debug

alert_text: |
  Database has logged more than 5 authentication failures in the last 10 minutes.
  This may indicate unauthorized access attempts.
  Number of failures: {0}
alert_text_args:
- num_matches
```

### 14.3. Cách test alert

Để test alert hoạt động:

1. Tăng tần suất sinh error trong BE Pod bằng cách sửa ConfigMap:
   - Đổi tỉ lệ status_code để 500/503 xuất hiện nhiều hơn
   - Giảm `time.sleep()` để sinh log nhanh hơn
2. Apply lại ConfigMap và restart Deployment:
   ```bash
   kubectl apply -f configmap-log-scripts.yaml
   kubectl rollout restart deployment/be-log-generator -n dung-lab
   ```
3. Đợi 5 phút rồi kiểm tra:
   - Nếu dùng Kibana Alerting: vào **Stack Management → Rules** xem rule có kích hoạt không
   - Nếu dùng ElastAlert 2: kiểm tra log của Pod elastalert2
     ```bash
     kubectl logs -n elk deploy/elastalert2 --tail=50
     ```
4. Sau khi test xong, đổi ConfigMap về tỉ lệ error bình thường

### 14.4. Mở rộng: Gửi cảnh báo qua Telegram

Nếu muốn demo bắt mắt hơn, cấu hình ElastAlert 2 gửi qua Telegram:

```yaml
# Thêm vào file rule
alert:
- telegram

telegram_bot_token: "<bot_token>"
telegram_room_id: "<chat_id>"
```

Cách lấy bot token và chat ID:

1. Tạo bot qua @BotFather trên Telegram
2. Lấy `bot_token` từ BotFather
3. Gửi tin nhắn cho bot
4. Gọi API `https://api.telegram.org/bot<token>/getUpdates` để lấy `chat_id`

---

## 15. Tổng kết bổ sung

Với các phần bổ sung từ mục 11 đến 14, tài liệu này đã bao gồm đầy đủ:

| STT | Nội dung | Mục |
|-----|---------|-----|
| 1 | Phân tích khả thi 6 tiêu chí | Mục 2 |
| 2 | Kiến trúc tổng quan | Mục 3 |
| 3 | Thiết kế chi tiết | Mục 4 |
| 4 | Thứ tự triển khai 6 pha | Mục 5 |
| 5 | Lưu ý trước khi triển khai | Mục 6 |
| 6 | Đề xuất phương án tối ưu | Mục 7 |
| 7 | 4 Pod Python sinh log (ý tưởng) | Mục 9 |
| 8 | 4 Pod Python sinh log (triển khai) | Mục 10 |
| 9 | Cấu hình Fluent Bit parser + routing | Mục 11 |
| 10 | Elasticsearch ILM + Template + Alias | Mục 12 |
| 11 | Cấu hình buffer Fluent Bit | Mục 13 |
| 12 | Cấu hình alert + cách test | Mục 14 |

Tài liệu giờ đã có thể dùng như một **runbook triển khai đầy đủ**: từ ý tưởng, thiết kế, code, manifest, cấu hình, đến cách kiểm tra kết quả.

---

## 16. Trạng thái triển khai thực tế trên cụm ngày 2026-04-03

Các hạng mục đã được triển khai thật bằng `kubectl` và `helm` trên cụm công ty:

### 16.1. Workload sinh log

Đã tạo namespace riêng:

- `dung-lab`

Đã deploy thành công 4 workload sinh log:

- `dung-fe-log-generator`
- `dung-be-log-generator`
- `dung-db-log-generator`
- `dung-web-log-generator`

Trạng thái:

- tất cả pod `Running`
- các script Python đang sinh log JSON ra `stdout`

### 16.2. Fluent Bit

Đã nâng cấp release `fluent-bit` trong namespace `elk` bằng Helm.

Các chức năng đã áp dụng:

- parse JSON log của `dung-lab`
- route theo field `service`
- ghi vào index riêng theo từng nhóm
- bật filesystem buffer tại `/var/fluent-bit/state`
- giữ generic output cho các workload khác của cluster

Lưu ý triển khai thực tế:

- do cụm Elasticsearch hiện có template `logs` kiểu data stream, không thể dùng pattern `logs-*` như thiết kế ban đầu
- để tránh xung đột với tài nguyên sẵn có của công ty, phần triển khai thực tế dùng prefix riêng:
  - `dung-fe-*`
  - `dung-be-*`
  - `dung-db-*`
  - `dung-web-*`

### 16.3. Elasticsearch

Đã tạo thành công:

- ILM policy: `logs-lab-policy`
- index template:
  - `dung-fe-template`
  - `dung-be-template`
  - `dung-db-template`
  - `dung-web-template`
- bootstrap index:
  - `dung-fe-000001`
  - `dung-be-000001`
  - `dung-db-000001`
  - `dung-web-000001`
- write alias:
  - `dung-fe-write`
  - `dung-be-write`
  - `dung-db-write`
  - `dung-web-write`

Xác nhận thực tế:

- ILM đang ở phase `hot`
- mapping tĩnh hoạt động
- log của `backend`, `database`, `webserver` và `frontend` đều đã đi vào index riêng

### 16.4. Alert

Đã deploy thành công:

- `elastalert2` trong namespace `elk`

Đã nạp 3 rule:

- `Backend Error Count Alert`
- `Database Auth Failed Alert`
- `Nginx 5xx Error Alert`

Kết quả thực tế:

- ElastAlert đã load đủ 3 rule
- log của pod `elastalert2` đã ghi nhận alert thật cho:
  - backend error count
  - database auth failed
  - webserver 5xx count

### 16.5. Điểm chưa hoàn hảo

- Elasticsearch hiện đang khá tải, có xuất hiện `HTTP 429` ở Fluent Bit khi flush về index generic `fluent-bit-*`
- tuy nhiên buffer filesystem và cơ chế retry đang hoạt động, Fluent Bit không crash
- phần alert hiện đang dùng `ElastAlert 2` thay vì Kibana rule nội bộ, vì đây là cách dễ kiểm chứng và triển khai ổn định hơn trên cụm hiện tại

### 16.6. Kết luận triển khai thực tế

Tính đến thời điểm triển khai này, các yêu cầu cốt lõi đã đạt được trên cụm thật:

- có 4 workload sinh log riêng của `dung-lab`
- có index design riêng
- có mapping tĩnh
- có ILM
- có buffer Fluent Bit
- có alert theo số lượng error trong khoảng thời gian

Phần khác biệt duy nhất so với bản thiết kế gốc là tên index prefix đã được đổi từ `logs-*` sang `dung-*` để tránh xung đột với template có sẵn trong hệ thống hiện hữu.
