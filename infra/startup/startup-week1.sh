      #!/bin/bash
      set -e
      exec > /var/log/startup-script.log 2>&1

      # ---- First Boot Check ----
      INIT_FLAG="/var/lib/startup-complete"
      if [ -f "$INIT_FLAG" ]; then
        echo "Already initialized — starting services only"
        systemctl start free5gc || true
        exit 0
      fi

      echo "=== Starting 5G Core VM setup ==="

      # ---- System Updates ----
      apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y \
        git \
        curl \
        wget \
        wireguard \
        wireguard-tools \
        net-tools \
        iproute2 \
        iptables \
        linux-headers-$(uname -r) \
        build-essential \
        gcc-12 \
        jq

      # ---- Docker (official repo — includes compose plugin) ----
      curl -fsSL https://get.docker.com | sh
      apt-get install -y docker-compose-plugin
      systemctl enable docker
      systemctl start docker
      usermod -aG docker ubuntu

      # ---- Go 1.25.5 ----
      wget -q https://go.dev/dl/go1.25.5.linux-amd64.tar.gz -O /tmp/go.tar.gz
      tar -C /usr/local -xzf /tmp/go.tar.gz
      echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/ubuntu/.bashrc
      echo 'export GOPATH=/home/ubuntu/go' >> /home/ubuntu/.bashrc
      echo 'export GOROOT=/usr/local/go' >> /home/ubuntu/.bashrc
      rm /tmp/go.tar.gz

      # ---- IP Forwarding ----
      echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
      echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
      sysctl -p

      # ---- TUN Device (required for UPF) ----
      mkdir -p /dev/net
      mknod /dev/net/tun c 10 200 || true
      chmod 666 /dev/net/tun

      # ---- gtp5g Kernel Module (required for UPF data plane) ----
      git clone -b v0.9.14 https://github.com/free5gc/gtp5g /tmp/gtp5g
      cd /tmp/gtp5g
      make
      make install
      echo "gtp5g" >> /etc/modules-load.d/gtp5g.conf
      modprobe gtp5g || true
      echo "gtp5g install status: $?" >> /var/log/startup-script.log

      # ---- Clone Free5GC Compose ----
      git clone https://github.com/free5gc/free5gc-compose /home/ubuntu/free5gc-compose
      chown -R ubuntu:ubuntu /home/ubuntu/free5gc-compose

      # ---- Disable built-in UERANSIM container (using external VM) ----
      cd /home/ubuntu/free5gc-compose
      # Add profile so ueransim container only starts when explicitly called
      sed -i '/container_name: ueransim/{n; s/^/    profiles:\n      - local-ran\n/}' docker-compose.yaml || true

      # ---- Host iptables for UPF data plane ----
      iptables -t nat -A POSTROUTING -o ens4 -j MASQUERADE || true
      iptables -A FORWARD -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1400 || true

      # ---- WireGuard Keys ----
      mkdir -p /etc/wireguard
      wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
      chmod 600 /etc/wireguard/private.key
      CORE_PUBLIC_KEY=$(cat /etc/wireguard/public.key)
      echo "5g-core WireGuard public key: $CORE_PUBLIC_KEY" > /home/ubuntu/wireguard-keys.txt
      chown ubuntu:ubuntu /home/ubuntu/wireguard-keys.txt

      # ---- Systemd Service — Free5GC ----
      cat > /etc/systemd/system/free5gc.service << 'SVCEOF'
[Unit]
Description=Free5GC 5G Core Network Functions
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/ubuntu/free5gc-compose
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
User=ubuntu
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable free5gc

echo "=== 5G Core VM setup complete (Week 1) ===" | tee -a /home/ubuntu/ready.txt
cat >> /home/ubuntu/ready.txt << 'READYEOF'

Next steps:
1. Get WireGuard public key: cat ~/wireguard-keys.txt
2. Configure WireGuard peer on OCI bastion
3. Create /etc/wireguard/wg0.conf on this VM
4. sudo wg-quick up wg0
5. Configure Free5GC: ~/free5gc-compose/config/
6. docker compose -f ~/free5gc-compose/docker-compose.yaml up -d
READYEOF

chown ubuntu:ubuntu /home/ubuntu/ready.txt
touch "$INIT_FLAG"
echo "=== Startup script complete at $(date) ==="
