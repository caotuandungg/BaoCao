# Giải Thích Các Khái Niệm Cốt Lõi Trong Hệ Thống Log K8s

Tài liệu này giải thích chi tiết các thuật ngữ nền tảng được trích xuất từ cấu trúc giải pháp thu thập nhật ký hệ thống (Logging).

---

## 1. Fluent Bit là gì? Tại sao lại sử dụng nó?

**Fluent Bit** là một bộ thu thập, lọc và chuyển tiếp dữ liệu log (Log Agent) siêu nhẹ mã nguồn mở. Nó được phát triển để phục vụ cho các môi trường Cloud-Native như Kubernetes.

**Lý do lựa chọn sử dụng:**
1. **Trọng lượng vô cùng nhẹ:** Fluent Bit được viết bằng ngôn ngữ C, tiêu thụ chỉ vài Megabytes RAM và cực ít CPU, rất lý tưởng để triển khai dưới dạng DaemonSet (chạy nền trên mọi Node) mà không làm tốn tài nguyên chạy ứng dụng.
2. **Khả năng tương thích gốc với K8s:** Nó có sẵn các bộ lọc cấu hình (Filter) dành riêng cho Kubernetes, tự động hiểu cách container runtime (như containerd, docker) lưu trữ file log.
3. **Kết nối linh hoạt:** Dù rất nhẹ, Fluent Bit hỗ trợ đẩy log đi hàng chục hệ thống lưu trữ khác nhau, trong đó có Elasticsearch.

**Các giải pháp thay thế phổ biến:**
* **Fluentd:** Là "đàn anh", hỗ trợ cực nhiều plugin nhưng tiêu tốn tài nguyên RAM gấp 10-20 lần Fluent Bit. Chỉ nên dùng khi cần xử lý log cực kỳ phức tạp.
* **Vector:** Viết bằng Rust, hiệu năng cực cao, đôi khi nhanh hơn cả Fluent Bit nhưng cấu hình phức tạp hơn.
* **Promtail:** Thường đi kèm với hệ thống Grafana Loki, cực kỳ đơn giản nhưng chỉ dùng tốt nhất trong hệ sinh thái Grafana.

## 2. Metadata (Siêu dữ liệu) là gì và tại sao cần thiết?

**Metadata** được hiểu đơn giản là "dữ liệu mô tả về nguồn gốc của một đối tượng dữ liệu". 

Trong bối cảnh hệ thống Kubernetes, nếu một ứng dụng báo lỗi ra stdout, dòng log thô chỉ ghi: `[Error] Database connection refused`. Hệ thống sẽ lưu dòng log này, nhưng điều đó là không đủ.

**Tại sao cực kỳ cần thiết?**
Trong cụm K8s có thể có hàng trăm Pod chạy cùng lúc. Khi có dòng lỗi `Database connection refused`, nếu không có Metadata, người quản trị hoàn toàn mù tịt không biết: 
* Lỗi từ Pod nào? 
* Ở Namespace (`dev` hay `production`) nào? 
* Ứng dụng tên là gì?

Fluent Bit tự động bắt dòng log kia và **nhúng thêm Metadata vào**, biến thành bảng thông tin dạng JSON:
```json
{
  "log": "[Error] Database connection refused",
  "metadata": {
      "namespace": "production",
      "pod_name": "backend-api-7db5x",
      "container_name": "app-core",
      "labels": {"app": "backend", "team": "alpha"}
  }
}
```
Nhờ có Metadata, người quản trị mới có thể tra cứu chính xác sự cố tới từng Pod riêng biệt.

**Cách tiếp cận thay thế:**
Thay vì để Agent tự "nhặt" Metadata, lập trình viên có thể sử dụng **Structured Logging** (Ghi log có cấu trúc JSON). Ứng dụng sẽ tự nhúng sẵn ServiceName, Version vào dòng log. Tuy nhiên, cách này đòi hỏi phải sửa code ứng dụng, còn Metadata tự động thì không cần can thiệp code.

## 3. ELK Là Gì?

**ELK** không phải là tên một phần mềm, mà là **một chuỗi giải pháp (stack)** bao gồm 3 phần mềm mã nguồn mở rất nổi tiếng thường được cài đặt chung với nhau, tạo thành viết tắt E-L-K:
* **E - Elasticsearch:** Trái tim hệ thống, hoạt động như một cơ sở dữ liệu phi quan hệ (NoSQL) cực độ tối ưu cho việc tiếp nhận, lập chỉ mục (index) và tìm kiếm toàn văn bản dữ liệu khổng lồ với tốc độ mili-giây.
* **L - Logstash:** Bộ xử lý và đẩy dữ liệu (thường đi kèm, nhưng trong mô hình cụm vừa và nhỏ, người ta thường lược bỏ Logstash và thay bằng Fluent Bit vì Logstash viết bằng Java nên rất tốn RAM).
* **K - Kibana:** Giao diện đồ hoạ cho người dùng.

**Hệ thống thay thế tiêu biểu (PLG Stack):**
Ngoài ELK, một đối thủ lớn khác là **PLG** (Promtail - Loki - Grafana).
* **Ưu điểm của PLG:** Rất tiết kiệm ổ cứng (không đánh chỉ mục toàn bộ nội dung), chạy cực nhẹ.
* **Nhược điểm so với ELK:** Tìm kiếm nội dung chi tiết chậm hơn. ELK mạnh hơn về khả năng phân tích và tìm kiếm "bới lông tìm vết" trên dữ liệu cực lớn.

## 4. Kibana Là Gì? Tại Sao Lại Dùng Nó?

**Kibana** là ứng dụng nền web (Dashboard) cung cấp hình thức biểu diễn dữ liệu và giao diện tương tác người dùng cho hệ thống Elasticsearch.

**Lý do bắt buộc cần Kibana:**
1. **Elasticsearch không có giao diện:** Elasticsearch chỉ là một CSDL backend. Nếu muốn xem log, quản trị viên sẽ phải gõ các lệnh API/cURL phức tạp dưới Terminal.
2. **Tìm kiếm (Log Search) trực quan:** Kibana giải quyết vấn đề bằng cách cung cấp giao diện điền từ khoá trực quan, thanh trượt thời gian, tự động tô đậm (highlight) từ khoá tìm kiếm.
3. **Thống kê / Bảng điều khiển (Dashboard):** Kibana cho phép vẽ các biểu đồ (Hình tròn, hình cột) phân tích cấu trúc dữ liệu. Ví dụ: dễ dàng hiển thị theo thời gian thực xem dịch vụ nào đang sinh ra số lượng chữ `Error` hoặc `503 Bad Gateway` nhiều nhất trong ngày.

---

## 5. Các Combo Logging Toàn Diện Có Thể Thay Thế (Full-Stack)

Nếu trong dự án này không muốn sử dụng bộ **Fluent-Bit + Elasticsearch + Kibana**, quản trị viên có cấu trúc lại toàn bộ hệ thống bằng các "Combo" sau tùy thuộc vào bài toán kinh tế và kỹ thuật:

### 5.1. PLG Stack (Promtail + Loki + Grafana)
Đây là giải pháp hiện đại được cộng đồng Kubernetes cực kỳ ưa chuộng vì triết lý "nhẹ nhàng và tiết kiệm".
*   **Promtail (vị trí của Fluent Bit):** Agent đi thu gom log.
*   **Loki (vị trí của Elasticsearch):** Kho lưu trữ log tập trung. Loki thay đổi hoàn toàn cách tính toán: Nó **không đánh chỉ mục toàn bộ text** mà chỉ đánh chỉ mục các Metadata (nhãn). Giống như việc một cuốn sách chỉ có mục lục chương bài chứ không có bảng tra cứu từng từ. Do đó Loki chạy siêu nhẹ và tốn cực ít ổ cứng.
*   **Grafana (vị trí của Kibana):** Chuyên gia vẽ Dashboard, nay tích hợp luôn màn hình xem log từ Loki.
*   **Khi nào nên dùng:** Phù hợp với cụm hệ thống có tài nguyên vừa và nhỏ, muốn tiết kiệm tối đa chi phí phần cứng và không có nhu cầu khắt khe về tìm kiếm "full-text chuyên sâu".

### 5.2. Giải pháp SaaS Đám Mây Mướn Ngoài (Datadog, Splunk, Dynatrace)
Thay vì tự xây nhà, tự mua tủ (Elasticsearch) để cất đồ, hệ thống sẽ thuê một công ty chuyên nghiệp giữ hộ log.
*   **Kiến trúc:** Cài đặt một Agent độc quyền (Ví dụ: Datadog Agent, Splunk Universal Forwarder) lên K8s. Agent này sẽ hút toàn bộ log và đẩy thẳng qua Internet lên Server của hãng.
*   **Khi nào nên dùng:**
    *   *Ưu điểm:* Không tốn một chút công sức nào để thiết lập và vận hành DB. Giao diện (UI/UX) của họ là đỉnh cao, hỗ trợ cả AI tự phát hiện lỗi.
    *   *Nhược điểm:* **Cực kỳ tốn kém** nếu hệ thống xả ra quá nhiều log, và mắc phải rào cản pháp lý (Compliance) vì dữ liệu hệ thống bị tuồn ra máy chủ ngoài quốc gia.

### 5.3. EFK Stack Cổ Điển (Elasticsearch + Fluentd + Kibana)
Về cơ bản giống hệt hệ thống hiện tại, nhưng thay lõi thu thập **Fluent Bit** bằng người anh **Fluentd**.
*   **Khi nào nên dùng:** Khi bạn có những dòng log cực kỳ dị biệt, cần viết những script logic phức tạp (bằng ngôn ngữ Ruby) để bẻ gãy, tách ghép log trước khi gửi đi.
*   **Nhược điểm:** Tốn quá nhiều RAM trên mỗi Node của K8s, đi ngược lại triết lý tối giản của Cloud-Native.
