in the future it would be

gitops-repository/
├── bootstrap/                # Điểm khởi đầu (Root App)
│   ├── cluster-dev.yaml      # Cài đặt cho cluster DEV
│   └── cluster-prod.yaml     # Cài đặt cho cluster PROD
├── apps/                     # Định nghĩa các ứng dụng (Base)
│   ├── guestbook/
│   │   ├── base/             # Manifests gốc (Deployment, Service)
│   │   └── overlays/         # Tùy chỉnh theo môi trường
│   │       ├── dev/          # Patch cho dev (replicas: 1)
│   │       └── prod/         # Patch cho prod (replicas: 5)
├── infrastructure/           # Các công cụ dùng chung cho Cluster
│   ├── networking/           # Ingress-nginx, Cert-manager
│   ├── monitoring/           # Prometheus, Grafana
│   └── security/             # ArgoCD RBAC (file bạn gửi ở trên), Kyverno
└── clusters/                 # Cấu hình cụ thể cho từng Cluster
    ├── dev-cluster/          # Khai báo các ứng dụng sẽ chạy ở Dev
    │   └── apps-list.yaml
    └── prod-cluster/         # Khai báo các ứng dụng sẽ chạy ở Prod
        └── apps-list.yaml


Hãy tìm thêm các folder mở rộng bên trong ^^