# GitOps trên máy ảo (VM GitOps)

Thư mục này giúp máy ảo tự động đồng bộ (reconcile) hệ thống logging cục bộ từ Git:

```text
Kho chứa GitHub (GitHub repo)
  -> Được clone về máy ảo tại thư mục /opt/bocao-gitops
  -> 4 bộ giả lập sinh log bằng Python chạy dưới dạng systemd services
  -> Cấu hình Fluent Bit nằm ở thư mục /etc/fluent-bit
  -> Fluent Bit liên tục đọc log tại /var/log/dung-lab/*.log
  -> Fluent Bit in các log đã được phân tích ra màn hình (stdout) để kiểm tra
```

Cài đặt lần đầu tiên trên máy ảo:

```bash
sudo apt-get update
sudo apt-get install -y git
sudo git clone https://github.com/caotuandungg/BaoCao.git /opt/bocao-gitops
cd /opt/bocao-gitops
sudo bash yaml_conf/vm-gitops/install-gitops-puller.sh
```

Cập nhật mã nguồn thủ công (Kéo code bằng tay):

```bash
sudo systemctl start bocao-vm-gitops.service
```

Xem nhật ký quá trình tự động kéo code:

```bash
journalctl -u bocao-vm-gitops.service -f
```

Kiểm tra trạng thái bộ đếm giờ (Timer):

```bash
systemctl status bocao-vm-gitops.timer
systemctl list-timers bocao-vm-gitops.timer
```

Kiểm tra log do các ứng dụng giả lập sinh ra:

```bash
tail -f /var/log/dung-lab/fe.log
tail -f /var/log/dung-lab/be.log
tail -f /var/log/dung-lab/db.log
tail -f /var/log/dung-lab/web.log
```

Kiểm tra trạng thái Fluent Bit:

```bash
systemctl status fluent-bit
journalctl -u fluent-bit -f
```

## Quản lý cơ chế GitOps tự động kéo code

Để vô hiệu hóa hoàn toàn (TẮT) cơ chế GitOps tự động kéo code:

```bash
sudo systemctl stop bocao-vm-gitops.timer
sudo systemctl stop bocao-vm-gitops.service
sudo systemctl disable bocao-vm-gitops.timer
```

Để kích hoạt lại (BẬT) cơ chế GitOps tự động kéo code:

```bash
sudo systemctl enable --now bocao-vm-gitops.timer
sudo systemctl start bocao-vm-gitops.service
```
