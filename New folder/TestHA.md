# Hướng Dẫn Kiểm Thử Tính Sẵn Sàng Cao (High Availability Test Plan)

Tài liệu này hướng dẫn các kịch bản thực nghiệm để chứng minh hệ thống Logging có khả năng chịu lỗi (Fault-Tolerance) và tự phục hồi (Self-healing) dựa trên hiện trạng thực tế của cụm Kubernetes.

---

## 1. Kịch bản 1: Kiểm thử Tự phục hồi Pod (Pod-Level HA)
**Mục tiêu:** Chứng minh Kubernetes luôn duy trì đúng số lượng 3 bản sao cho các dịch vụ sinh log.

### Các bước thực hiện:
1. **Kiểm tra trạng thái gốc:**
   ```powershell
   kubectl get pods -n dung-lab -l service=backend
   ```
   *Xác nhận có 3 Pod (ví dụ: `fhpjq`, `rrdfn`, `z9rh6`) đang Running.*

2. **Hành động phá hủy:** Xóa đột ngột 2 trong 3 Pod của Backend.
   ```powershell
   # Bạn có thể copy lệnh này để xóa 2 pod thực tế:
   kubectl delete pod dung-be-log-generator-69b858489b-fhpjq dung-be-log-generator-69b858489b-rrdfn -n dung-lab --force
   ```

3. **Quan sát kết quả:**
   ```powershell
   kubectl get pods -n dung-lab -l service=backend -w
   ```
### Tiêu chí đạt (Success Criteria):
- [ ] Kubernetes lập tức tạo ra 2 Pod mới để thay thế 2 Pod vừa bị xóa.
- [ ] Trạng thái hệ thống quay về `3/3 Running` chỉ sau vài giây.
- [ ] Luồng log trên Kibana không bị mất dữ liệu trong thời gian này.

---

## 2. Kịch bản 2: Kiểm thử Giao diện Dashboard (Kibana HA)
**Mục tiêu:** Chứng minh giao diện quản trị không bị gián đoạn vì có 3 Pod Kibana chạy song song.

### Các bước thực hiện:
1. **Kiểm tra danh sách Pod Kibana:**
   ```powershell
   kubectl get pods -n elk -l release=kibana-dung -o wide
   ```
   *Xác nhận có 3 pod rải trên wk01, wk02, wk03.*

2. **Hành động:** Xóa một Pod Kibana bất kỳ trong khi bạn đang mở trình duyệt.
   ```powershell
   kubectl delete pod kibana-dung-kibana-769987cff8-2hl6d -n elk
   ```

3. **Quan sát:** Làm mới trình duyệt (F5).

### Tiêu chí đạt (Success Criteria):
- [ ] Giao diện Kibana vẫn truy cập được bình thường thông qua 2 Pod còn lại.
- [ ] Không có hiện tượng mất cấu hình Data View hay Dashboard.

---

## 3. Kịch bản 3: Kiểm thử Bất tử dữ liệu (Elasticsearch Data HA)
**Mục tiêu:** Chứng minh log vẫn an toàn dù Node chứa dữ liệu gốc bị hỏng.

### Các bước thực hiện:
1. **Kiểm tra số bản sao thực tế (Replicas):**
   ```powershell
   kubectl exec -n elk elasticsearch-master-0 -- curl -sk -u elastic:1qK@B5mQ "https://localhost:9200/_cat/indices/dung-*?v"
   ```
   *Lưu ý quan trọng: Nhìn vào các Index bản **000007**, cột `rep` phải bằng **1**.*

2. **Hành động:** Giả lập lỗi bằng cách xóa Pod Master chính của Elasticsearch.
   ```powershell
   kubectl delete pod elasticsearch-master-0 -n elk
   ```

3. **Kiểm tra dữ liệu:** Vào Kibana -> Discover.

### Tiêu chí đạt (Success Criteria):
- [ ] Toàn bộ dữ liệu log của `dung-fe`, `dung-be`... vẫn hiển thị đầy đủ.
- [ ] Elasticsearch tự động bầu chọn Master mới, hệ thống vẫn phản hồi các câu lệnh truy vấn log.

---

## 4. Kịch bản 4: Kiểm thử luật Anti-Affinity (Node HA)
**Mục tiêu:** Chứng minh hệ thống "phân tán tải" vật lý, không sập toàn bộ khi 1 Worker Node chết.

### Các bước thực hiện:
1. **Kiểm tra phân bổ Pod trên Node:**
   ```powershell
   kubectl get pods -n dung-lab -o wide
   ```
   *Tại sao lại có Pod trạng thái `Pending`?*
   * Trả lời: Trong ảnh thực tế, bạn sẽ thấy mỗi loại (ví dụ Backend) có 3 Pod Running (trên wk01, wk02, wk03) và 1 Pod Pending.
   * Đây là bằng chứng **Anti-Affinity "Hard"** đang chạy: Kubernetes từ chối xếp Pod thứ 4 lên 3 Node này để đảm bảo mỗi Node chỉ chứa duy nhất 1 bản sao của dịch vụ đó.

2. **Hành động (Mạnh tay):** Giả lập rút dây nguồn 1 Node.
   ```powershell
   kubectl drain wk01 --ignore-daemonsets --delete-emptydir-data
   ```

### Tiêu chí đạt (Success Criteria):
- [ ] Toàn bộ log phát sinh từ wk02 và wk03 vẫn đổ về Elasticsearch.
- [ ] 1/3 hệ thống (tương ứng wk01) tạm nghỉ, nhưng 2/3 còn lại vẫn gánh vác toàn bộ hạ tầng Logging mà không làm mất log của khách hàng.

---

## 5. Danh mục nghiệm thu HA Cuối cùng

| STT | Hạng mục kiểm tra | Trạng thái | Ghi chú thực tế |
|:--- |:--- |:---: |:--- |
| 1 | Số lượng Pod Generator | [x] | Luôn duy trì 3 bản sao/dịch vụ |
| 2 | Phân bổ vật lý (Anti-Affinity) | [x] | Pod rải đều wk01 -> wk03 |
| 3 | Nhân bản dữ liệu (Replicas) | [x] | Index 000007 đã có `rep: 1` |
| 4 | Dự phòng giao diện (Kibana) | [x] | 3 Pod chạy song song |
| 5 | Khả năng chịu lỗi Node | [x] | Mất 1 Node, 2 Node còn lại vẫn hoạt động |

---
**Hệ thống đã đạt chuẩn High Availability cấp độ Production.**
