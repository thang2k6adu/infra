## ArgoCD Image Updater – Git PAT & Sealed Secrets

- `argocd-image-updater` cần **Git Personal Access Token (PAT)** với quyền **repo**.
- Nếu PAT hết hạn:
  - Tạo PAT mới.
  - Cập nhật lại field `password` trong **SealedSecret**.

---

## Sealed Secrets Certificate

- Để seal secret, cần **public certificate key** của Sealed Secrets controller.
- Nếu chưa có:
  - Lấy certificate từ cluster.

---

## Cluster Configuration

- Phải có file `cluster-config.yaml` ở root của thư mục `cluster-*`.
- Trước khi làm bất kỳ thao tác nào, hãy kiểm tra file này.

---

## Create New Tenant

- Nếu muốn tạo tenant mới:
  - Mở file `README.md`.
  - Làm theo các bước hướng dẫn trong đó.

Add xong ingress nhớ lên reverse proxy add domain đó vào