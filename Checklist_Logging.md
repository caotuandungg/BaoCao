# ✅ Checklist Tiến Độ Xây Dựng Logging System

> Cập nhật file này mỗi khi hoàn thành 1 bước.
> Sáng hôm sau vào, mở file này ra xem mình đang ở đâu.

---

## Kiểm tra nhanh mỗi sáng

```bash
kubectl cluster-info            # Kết nối OK?
helm list -n monitoring         # Đã cài gì?
kubectl get pods -n monitoring  # Pods đang chạy?
```

---

## Tiến độ

### Chuẩn bị
- [ ] Kết nối vào cụm K8s thành công
- [ ] Helm đã cài (`helm version`)
- [ ] Tạo namespace `log-monitoring`

### Cài đặt
- [ ] Thêm Helm repo Grafana (`helm repo add grafana ...`)
- [ ] Tạo file `loki-values.yaml`
- [ ] Cài Loki → pod Running
- [ ] Tạo file `promtail-values.yaml`  
- [ ] Cài Promtail → pods Running trên mỗi Node
- [ ] Tạo file `grafana-values.yaml`
- [ ] Cài Grafana → pod Running

### Kiểm tra
- [ ] Port-forward Grafana (`kubectl port-forward svc/grafana 3000:80 -n monitoring`)
- [ ] Đăng nhập Grafana (admin / admin123)
- [ ] Vào Explore → chọn Loki datasource
- [ ] Chạy query `{namespace="default"}` → thấy log
- [ ] Chạy query tìm "error" → hoạt động
- [ ] Chụp screenshot kết quả

### Hoàn thiện
- [ ] Viết báo cáo kết quả triển khai
- [ ] Push code (values.yaml files) lên Git

---

## Ghi chú cá nhân

_(Ghi lại bất kỳ vấn đề gặp phải hoặc ghi nhớ ở đây)_

- ...
- ...
