# Hướng Dẫn Kiểm Thử Tính Sẵn Sàng Cao (High Availability Test Plan)

Tài liệu này hướng dẫn các kịch bản thực nghiệm để chứng minh hệ thống Logging có khả năng chịu lỗi (Fault-Tolerance) và tự phục hồi (Self-healing) ở nhiều cấp độ khác nhau.

---

## 1. Kịch bản 1: Kiểm thử Tự phục hồi Pod (Pod-Level HA)
**Mục tiêu:** Chứng minh Kubernetes luôn duy trì đúng số lượng bản sao ứng dụng dù có sự cố đột ngột.

### Các bước thực hiện:
1. **Kiểm tra trạng thái gốc:**
   ```powershell
   kubectl get pods -n dung-lab -l service=backend
   ```
   *Xác nhận có 3 Pod đang Running.*

2. **Hành động phá hủy:** Xóa đột ngột 2 trong 3 Pod.
   ```powershell
   # Thay thế <pod-name> bằng tên thật từ lệnh trên
   kubectl delete pod <pod-name-1> <pod-name-2> -n dung-lab --force
   ```

3. **Quan sát kết quả:**
   ```powershell
   kubectl get pods -n dung-lab -l service=backend -w
   ```
### Tiêu chí đạt (Success Criteria):
- [ ] Kubernetes lập tức tạo ra 2 Pod mới để bù đắp.
- [ ] Trạng thái hệ thống quay về `3/3 Running` trong thời gian ngắn.
- [ ] Dữ liệu log không bị gián đoạn trong suốt quá trình xóa.

---

## 2. Kịch bản 2: Kiểm thử Truy cập Giao diện (Kibana-Level HA)
**Mục tiêu:** Chứng minh người dùng vẫn có thể xem dashboard khi một phần hạ tầng Kibana gặp sự cố.

### Các bước thực hiện:
1. **Hành động:** Duy trì trình duyệt đang mở Kibana, sau đó xóa Pod mà port-forward đang trỏ tới (hoặc xóa ngẫu nhiên 1 Pod Kibana).
   ```powershell
   kubectl delete pod -n elk -l release=kibana-dung
   ```

2. **Quan sát:** Làm mới (F5) trình duyệt.
   *Lưu ý: Nếu dùng port-forward trực tiếp vào Pod, bạn cần chạy lại lệnh port-forward vào Service.*

### Tiêu chí đạt (Success Criteria):
- [ ] Giao diện Kibana vẫn truy cập bình thường.
- [ ] Các tham số cấu hình, Dashboard đã lưu không bị mất.
- [ ] Hai Pod còn lại vẫn chia sẻ tải mà không bị quá tải.

---

## 3. Kịch bản 3: Kiểm thử An toàn Dữ liệu (Elasticsearch Data HA)
**Mục tiêu:** Chứng minh không mất dữ liệu log ngay cả khi một Node chứa dữ liệu bị sụp đổ.

### Các bước thực hiện:
1. **Ghi nhớ số lượng log hiện tại:** Vào Kibana -> Discover, ghi lại tổng số `hits` của 15 phút gần nhất.
2. **Hành động:** Xóa một Pod Master của Elasticsearch.
   ```powershell
   kubectl delete pod elasticsearch-master-0 -n elk
   ```
3. **Kiểm tra trạng thái Index:**
   ```powershell
   kubectl exec -n elk elasticsearch-master-1 -- curl -sk -u elastic:1qK@B5mQ "https://localhost:9200/_cat/indices/dung-*?v"
   ```

### Tiêu chí đạt (Success Criteria):
- [ ] Cột `health` có thể chuyển sang `yellow` nhưng tuyệt đối không được là `red`.
- [ ] Tổng số `hits` trên Kibana không thay đổi (không mất dữ liệu).
- [ ] Sau khi Pod `elasticsearch-master-0` khởi động lại, trạng thái cụm quay về `green`.

---

## 4. Kịch bản 4: Kiểm thử Phân tán vật lý (Node-Level HA)
**Mục tiêu:** Chứng minh luật Anti-Affinity hoạt động, đảm bảo toàn bộ hệ thống không sập khi 1 máy chủ vật lý bị hỏng.

### Các bước thực hiện:
1. **Kiểm tra phân bổ vật lý:**
   ```powershell
   kubectl get pods -n dung-lab -o wide
   ```
   *Xác nhận 3 Pod của cùng một dịch vụ nằm trên 3 Node khác nhau (wk01, wk02, wk03).*

2. **Hành động (Giả lập lỗi Node):** Dùng lệnh `drain` để đuổi toàn bộ Pod ra khỏi 1 Node (giả lập Node đó bị bảo trì hoặc hỏng).
   ```powershell
   kubectl drain wk03 --ignore-daemonsets --delete-emptydir-data
   ```

### Tiêu chí đạt (Success Criteria):
- [ ] Toàn bộ log của dịch vụ vẫn đổ về Elasticsearch bình thường từ 2 Node còn lại.
- [ ] Kubernetes tự động tìm chỗ trống trên `wk01` hoặc `wk02` để chạy lại các Pod bị đuổi (nếu còn tài nguyên).
- [ ] Trình trạng "Single Point of Failure" (Điểm chết duy nhất) đã bị loại bỏ hoàn toàn.

---

## 5. Tổng kết checklist nghiệm thu HA

| STT | Thành phần | Trạng thái Check | Kết luận |
|:--- |:--- |:---: |:--- |
| 1 | Microservices (FE/BE/DB/WEB) | [ ] | Đạt 3 replicas, tự phục hồi |
| 2 | Fluent Bit (Log Agent) | [ ] | Chạy trên mọi Node (DaemonSet) |
| 3 | Elasticsearch (Log Storage) | [ ] | Có bản sao (Replicas Index = 1) |
| 4 | Kibana (Visualization) | [ ] | 3 replicas, phân tán Node |
| 5 | Chống chịu lỗi Node vật lý | [ ] | Hệ thống vẫn sống khi mất 1 Node |

---
**Người thực hiện kiểm thử:** [Tên của bạn]
**Ngày thực hiện:** 09/04/2026
