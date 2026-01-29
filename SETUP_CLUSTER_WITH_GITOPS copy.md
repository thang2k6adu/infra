# 🚀 HƯỚNG DẪN TRIỂN KHAI K3S CLUSTER (MASTER + WORKER)

## BƯỚC 2: SET IP TĨNH + DISABLE CLOUD-INIT (MASTER)

Disable cloud-init network:
```bash
sudo nano /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

Nội dung:
```yaml
network: {config: disabled}
```

Xóa netplan cũ:
```bash
sudo rm -f /etc/netplan/50-cloud-init.yaml
```

Tạo netplan mới:
```bash
sudo nano /etc/netplan/01-static.yaml
```

Nội dung:
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: no
      addresses:
        - 192.168.0.50/24
      gateway4: 192.168.0.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
```

Apply:
```bash
sudo netplan apply
```

## BƯỚC 1: ĐỔI HOSTNAME (TRÊN NODE MASTER)

Nhớ dùng `ip a` để check **IP / mask / gateway** và thay cho đúng trước khi làm bất cứ điều gì.
```bash
sudo hostnamectl set-hostname k3s-master
sudo nano /etc/hosts
```

Ví dụ nội dung:
```txt
127.0.0.1 localhost
192.168.0.50 k3s-master
```

Reboot:
```bash
sudo reboot
```

Check IP:
```bash
ip a
```

## BƯỚC 3: SCAN IP CÁC SERVER WORKER (TRÊN MASTER)

Cài `nmap`:
```bash
sudo apt install nmap -y
```

Auto generate inventory file

⚠️ Nhớ sửa subnet + port SSH cho đúng môi trường. Sau này thêm server thì nhớ chạy lại cái này là oke.
```bash
SUBNET=192.168.0.0/24
PORT=8022
USER="thang2k6adu"
START_IP=51
MASTER_IP=$(hostname -I | awk '{print $1}')
BASE_IP=$(echo $SUBNET | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3}')

mkdir -p ~/k3s-inventory && cd ~/k3s-inventory

echo -e "[master]\n$MASTER_IP ansible_user=$USER ansible_port=$PORT worker_ip=$MASTER_IP\n\n[workers]" > hosts.ini

sudo nmap -p $PORT --open $SUBNET \
| grep "Nmap scan report" \
| grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" \
| grep -v "^$MASTER_IP$" \
| awk -v USER="$USER" -v PORT="$PORT" -v BASE="$BASE_IP" -v START="$START_IP" \
'{print $0" ansible_user="USER" ansible_port="PORT" worker_ip="BASE"."START+NR-1}' \
>> hosts.ini

cd ~/
```

Check file inventory:
```bash
cat ~/k3s-inventory/hosts.ini
```

Kết quả mong đợi:
```ini
[master]
192.168.0.50 ansible_user=thang2k6adu ansible_port=8022 worker_ip=192.168.0.50

[workers]
192.168.0.108 ansible_user=thang2k6adu ansible_port=8022 worker_ip=192.168.0.51
192.168.0.109 ansible_user=thang2k6adu ansible_port=8022 worker_ip=192.168.0.52
```

## BƯỚC 4: CÀI K3S CONTROL PLANE (MASTER)

Đặt tên node là `k3s-master`:
```bash
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --node-name k3s-master
```

Check:
```bash
kubectl get nodes
```

## BƯỚC 5: MỞ FIREWALL (UFW)

### Master:
```bash
sudo ufw allow 6443/tcp   # worker kết nối về master
sudo ufw allow 8472/udp   # pod giao tiếp
sudo ufw allow 10250/tcp  # lấy log pod
```

### Worker (bằng Ansible):
```bash
sudo ufw allow 8472/udp
sudo ufw allow 10250/tcp
```

## CÀI ANSIBLE TRÊN MASTER
```bash
sudo apt update
sudo apt install ansible -y
```

Lưu ý phải lắp ssh vào master node trước khi ssh

Lấy ssh private key đã bỏ vào các node (lúc setup) rồi bỏ lên master
ở đây chỉ có hướng dẫn window
scp -P 8022 $env:USERPROFILE\.ssh\id_ed25519 thang2k6adu@192.168.0.50
:/home/thang2k6adu/.ssh/id_ed25519

lấy public key bỏ vào
scp -P 8022 $env:USERPROFILE\.ssh\id_ed25519.pub thang2k6adu@192.168.0.50:/home/thang2k6adu/.ssh/id_ed25519.pub

phân quyền
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
```

Test kết nối:
```bash
ansible workers -i ~/k3s-inventory/hosts.ini -m ping
```

## SET SUDO KHÔNG PASSWORD (CHO WORKER)

Tạo file:
```bash
nano ~/k3s-inventory/setup-sudo.yml
```
```yaml
- hosts: workers
  become: yes
  tasks:
    - name: Allow thang2k6adu sudo without password
      copy:
        dest: /etc/sudoers.d/thang2k6adu
        content: |
          thang2k6adu ALL=(ALL) NOPASSWD:ALL
        owner: root
        group: root
        mode: '0440'
```

Run:
```bash
ansible-playbook -i ~/k3s-inventory/hosts.ini ~/k3s-inventory/setup-sudo.yml -K
```

tạo playbook gen card mạng

nano ~/k3s-inventory/gen_iface.yml

- hosts: master,workers
  gather_facts: yes
  vars:
    inventory_file: "{{ playbook_dir }}/hosts.ini"

  tasks:
    - name: Update inventory with iface
      delegate_to: localhost
      lineinfile:
        path: "{{ inventory_file }}"
        regexp: "^{{ inventory_hostname }}\\s"
        line: "{{ inventory_hostname }} ansible_user={{ ansible_user }} ansible_port={{ ansible_port }} worker_ip={{ hostvars[inventory_hostname].worker_ip }} iface={{ ansible_default_ipv4.interface }}"

check
ansible-playbook -i ~/k3s-inventory/hosts.ini ~/k3s-inventory/gen_iface.yml -K

check
cat ~/k3s-inventory/hosts.ini

## SET IP TĨNH CHO WORKER
```bash
nano ~/k3s-inventory/set-static-ip.yml
```
```yaml
- hosts: workers
  become: yes
  vars:
    dns:
      - 8.8.8.8
      - 1.1.1.1

  tasks:
    - name: Disable cloud-init network
      copy:
        dest: /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
        content: |
          network: {config: disabled}

    - name: Remove old netplan config
      file:
        path: /etc/netplan/50-cloud-init.yaml
        state: absent

    - name: Configure static IP
      template:
        src: static.yaml.j2
        dest: /etc/netplan/01-static.yaml
        mode: '0644'

    - name: Apply netplan
      command: netplan apply
      async: 10
      poll: 0
```

```bash
nano ~/k3s-inventory/static.yaml.j2
```

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    {{ hostvars[inventory_hostname].iface }}:
      dhcp4: no
      addresses:
        - {{ hostvars[inventory_hostname].worker_ip }}/24
      routes:
        - to: default
          via: {{ ansible_default_ipv4.gateway }}
      nameservers:
        addresses:
{% for d in dns %}
          - {{ d }}
{% endfor %}
```

Run:
```bash
ansible-playbook -i ~/k3s-inventory/hosts.ini ~/k3s-inventory/set-static-ip.yml
```

gen lại host
```bash
SUBNET=192.168.0.0/24
PORT=8022
USER="thang2k6adu"
START_IP=51
MASTER_IP=$(hostname -I | awk '{print $1}')
BASE_IP=$(echo $SUBNET | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3}')

mkdir -p ~/k3s-inventory && cd ~/k3s-inventory

echo -e "[master]\n$MASTER_IP ansible_user=$USER ansible_port=$PORT worker_ip=$MASTER_IP\n\n[workers]" > hosts.ini

sudo nmap -p $PORT --open $SUBNET \
| grep "Nmap scan report" \
| grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" \
| grep -v "^$MASTER_IP$" \
| awk -v USER="$USER" -v PORT="$PORT" -v BASE="$BASE_IP" -v START="$START_IP" \
'{print $0" ansible_user="USER" ansible_port="PORT" worker_ip="BASE"."START+NR-1}' \
>> hosts.ini

cd ~/

ansible-playbook -i ~/k3s-inventory/hosts.ini ~/k3s-inventory/gen_iface.yml -K
```

Check file inventory:
```bash
cat ~/k3s-inventory/hosts.ini
```

Check:
```bash
ansible workers -i ~/k3s-inventory/hosts.ini -m shell -a \
"echo '=== HOST:' \$(hostname) && ip a | grep inet && ip route | grep default && ping -c 2 8.8.8.8"
```

## MỞ FIREWALL CHO WORKER (ANSIBLE)
```bash
nano ~/k3s-inventory/open-ufw-worker.yml
```
```yaml
- hosts: workers
  become: yes
  tasks:
    - name: Allow flannel VXLAN (8472/udp)
      ufw:
        rule: allow
        port: 8472
        proto: udp

    - name: Allow kubelet API (10250/tcp)
      ufw:
        rule: allow
        port: 10250
        proto: tcp

    - name: Enable UFW
      ufw:
        state: enabled
```

Run:
```bash
ansible-playbook -i ~/k3s-inventory/hosts.ini ~/k3s-inventory/open-ufw-worker.yml
```

đổi tên node trước khi join để tránh trùng tên

nano ~/k3s-inventory/set-hostname.yml

- hosts: workers
  become: yes
  gather_facts: yes

  tasks:
    - name: Set hostname based on last octet of IP
      hostname:
        name: "k3s-worker-{{ ansible_default_ipv4.address.split('.')[-1] }}"

    - name: Update /etc/hosts
      lineinfile:
        path: /etc/hosts
        regexp: "^{{ ansible_default_ipv4.address }}"
        line: "{{ ansible_default_ipv4.address }} k3s-worker-{{ ansible_default_ipv4.address.split('.')[-1] }}"
        state: present

    - name: Reboot to apply hostname
      reboot:
        reboot_timeout: 300

chạy
ansible-playbook -i ~/k3s-inventory/hosts.ini ~/k3s-inventory/set-hostname.yml -K


## LẤY TOKEN TỪ MASTER
```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

Ví dụ:
```
K10a3f9c8c7b2a3b7f9::server:xxxxxxxx
```

## CÀI K3S AGENT (WORKER)
```bash
nano ~/k3s-inventory/install-k3s-worker.yml
```
```yaml
- hosts: workers
  become: yes
  vars:
    k3s_url: "https://192.168.0.50:6443"
    k3s_token: "K10e6dd53c7c99770339ed79f4771c7ded0fbeee5baadfa6ed8224b56a80d5f43ce::server:78b31cbc69888b6ad8603eeb988b07a9"

  tasks:
    - name: Install k3s agent
      shell: |
        curl -sfL https://get.k3s.io | K3S_URL={{ k3s_url }} K3S_TOKEN={{ k3s_token }} sh -
```

Run:
```bash
ansible-playbook -i ~/k3s-inventory/hosts.ini ~/k3s-inventory/install-k3s-worker.yml
```

Uninstall nếu lỗi:
```bash
nano ~/k3s-inventory/uninstall-k3s-worker.yml
```
```yaml
- hosts: workers
  become: yes

  tasks:
    - name: Stop k3s-agent service
      systemd:
        name: k3s-agent
        state: stopped
        enabled: false
      ignore_errors: yes

    - name: Run k3s-agent uninstall script
      shell: |
        if [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
          /usr/local/bin/k3s-agent-uninstall.sh
        fi
      args:
        warn: false
      ignore_errors: yes

    - name: Remove k3s directories
      file:
        path: "{{ item }}"
        state: absent
      loop:
        - /etc/rancher/k3s
        - /var/lib/rancher/k3s
        - /var/lib/kubelet
      ignore_errors: yes
```
```bash
ansible-playbook -i ~/k3s-inventory/hosts.ini ~/k3s-inventory/uninstall-k3s-worker.yml
```

## CHECK NODE ĐÃ JOIN
```bash
kubectl get nodes -o wide
```

Output:
```
NAME         STATUS   ROLES           IP
k3s-master   Ready    control-plane   192.168.0.50
worker1      Ready    <none>          192.168.0.505
worker2      Ready    <none>          192.168.0.506
```

## SET ROLE CHO WORKER
```bash
kubectl get nodes --no-headers | awk '{print $1}' | grep -v master | xargs -I {} kubectl label node {} node-role.kubernetes.io/worker=worker
```

Check:
```bash
kubectl get nodes
```

Output:
```
NAME            STATUS   ROLES    AGE
192.168.0.505   Ready    worker   1d
192.168.0.506   Ready    worker   1d
```

# 🚀 CÀI HELM + KUBERNETES DASHBOARD

## 1️⃣ Cài Helm
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

bắt đầu setup gitops
từ repo gốc tạo repo cluster-XXX (VD: Cluster Dev)

sửa cái phần ở
- core component set
- tenants app set

sau khi xong boostrap ArgoCD vào cluster

kubectl apply -k https://github.com/thang2k6adu/kubernetes-infra/cluster-dev/bootstrap/overlays/default

Ý nghĩa:
- tạo namespace argocd
- cài Argo CD
- tạo ApplicationSet
- Argo CD bắt đầu tự quản lý chính nó
- deploy core + tenants