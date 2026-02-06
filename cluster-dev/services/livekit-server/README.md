# Lưu ý trước khi deploy LiveKit

## Cấu hình mạng
```yaml
rtc:
  use_external_ip: true
  external_ip: "13.212.50.46"  # Phải sửa thành Public IP thật của server
```

## API Keys
- Sửa `LIVEKIT_KEYS` trong file .env với format: `api_key_thật:api_secret_thật`
- Không dùng placeholder `api_key:api_secret`

## Redis và Replicas
- Nếu dùng 2 replicas trở lên: Redis phải hoạt động
  - Tạo Redis password trong .env
  - Sửa `address`, `passwordSecret` và `passwordSecretKey` trong values.yaml
- Nếu chỉ 1 replica: Có thể tạm tắt Redis

## Cấu hình hiện tại
- Phù hợp với môi trường có reverse proxy/LB trước cluster
- Để dùng trực tiếp trên cloud: Đổi `service.type` thành `LoadBalancer`

## Production checklist
**Hiện tại (dev/test):**
- 1 replica
- Redis disabled (chưa High Availability)
- Resources: 500MB RAM (đủ cho dev/test)
- LiveKit cần CPU nhiều hơn RAM

**Chuẩn production cần:**
- Tăng replicas (ít nhất 2 cho HA)
- Bật Redis cho state sharing
- Bật HPA (Horizontal Pod Autoscaling)
- Bật autoscaling
- Tăng resources (CPU quan trọng hơn RAM)
- Bật TURN server để hỗ trợ 4G, mạng công ty, NAT strict

## TURN Server
- Cần thiết cho các mạng restrictive (4G, corporate networks)
- Cấu hình domain, TLS port, UDP port, secret
- Yêu cầu LoadBalancer hoặc NodePort cho TURN traffic