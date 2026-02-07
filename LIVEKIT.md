dùng IPVS

Client
  |
  | TCP 7880/7881 (signaling)
  v
VPS (IPVS)
  |
  +--> LiveKit Pod 1 (LAN IP)
  +--> LiveKit Pod 2 (LAN IP)

Client
  |
  | UDP 50000-60000
  v
VPS (Keepalived + IPVS)
  |
  +--> LiveKit Pod X


client signal -> 7880

trả về

v=0
o=- 46117326 2 IN IP4 127.0.0.1
s=-
t=0 0
a=ice-ufrag:abcd
a=ice-pwd:1234567890abcdef
a=fingerprint:sha-256 12:34:56:78:...
m=audio 50034 UDP/TLS/RTP/SAVPF 111
a=candidate:1 1 UDP 2130706431 203.0.113.10 50034 typ host
a=candidate:2 1 UDP 1694498815 203.0.113.10 52311 typ srflx
m=video 50036 UDP/TLS/RTP/SAVPF 96
a=candidate:3 1 UDP 2130706431 203.0.113.10 50036 typ host


parse ip và auto tạo rule IPVS

1 cài ipvs
sudo apt update
sudo apt install -y ipvsadm iproute2

load module kernel

sudo modprobe ip_vs
sudo modprobe ip_vs_sh
sudo modprobe ip_vs_rr
sudo modprobe nf_conntrack

check
lsmod | grep ip_vs


bật ip forward
sudo sysctl -w net.ipv4.ip_forward=1

lưu vĩnh viễn
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

tạo script

sudo nano /usr/local/bin/ipvs-forward

#!/bin/bash

BACKEND_FILE="/etc/nginx/backends/cluster-dev.conf"
PUBLIC_IP="13.212.50.46"
START_PORT=50000
END_PORT=60000

# Lấy IP từ file: server x.x.x.x:port;
BACKENDS=$(awk '{print $2}' $BACKEND_FILE | sed 's/;//g' | cut -d: -f1)

# Clear rule cũ
ipvsadm -C

for p in $(seq $START_PORT $END_PORT); do
  ipvsadm -A -u $PUBLIC_IP:$p -s sh

  for ip in $BACKENDS; do
    ipvsadm -a -u $PUBLIC_IP:$p -r $ip:$p -m
  done
done

cấp quyền chạy

chạy
sudo ipvs-forward

check
sudo ipvsadm -Ln

xóa hết rule (revert)
sudo ipvsadm -C

(Giải pháp an toàn hơn là:

chỉ xoá rule theo port range 50000–60000

không clear toàn bộ bảng)



