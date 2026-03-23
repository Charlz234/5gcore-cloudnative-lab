# ============================================
# GCP Compute — Spot VMs
# ============================================

locals {
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))
}

# ============================================
# 5G Core VM
# t2d-standard-4 spot | 4 vCPU | 16GB | 50GB
# Runs: Free5GC, WireGuard peer, Prometheus,
#       Grafana, k3s, Cilium, ArgoCD
# ============================================
resource "google_compute_instance" "core_5g" {
  name           = "core-5g"
  machine_type   = var.core_machine_type
  zone           = var.gcp_zone
  can_ip_forward = true
  tags           = ["lab-vm"]

  scheduling {
    preemptible         = true
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    provisioning_model  = "SPOT"
  }

  boot_disk {
    initialize_params {
      image = var.ubuntu_image
      size  = var.core_disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.id
    network_ip = var.core_5g_ip
    # No public IP — access via OCI WireGuard bastion and IAP(ssh on console)
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${local.ssh_public_key}"
    startup-script = <<-EOF
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
        gcc-12
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

      echo "=== 5G Core VM setup complete ===" | tee -a /home/ubuntu/ready.txt
      chown ubuntu:ubuntu /home/ubuntu/ready.txt
      touch "$INIT_FLAG"
    EOF
  }

  labels = {
    role = "5g-core"
    lab  = "telecom-5g"
  }

  service_account {
    scopes = ["cloud-platform"]
  }
}

# ============================================
# UERANSIM VM
# t2d-standard-2 spot | 2 vCPU | 8GB | 30GB
# Runs: UERANSIM gNB + UE, WireGuard peer
# ============================================
resource "google_compute_instance" "ueransim" {
  name           = "ueransim"
  machine_type   = var.ueransim_machine_type
  zone           = var.gcp_zone
  can_ip_forward = true
  tags           = ["lab-vm"]

  scheduling {
    preemptible         = true
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    provisioning_model  = "SPOT"
  }

  boot_disk {
    initialize_params {
      image = var.ubuntu_image
      size  = var.ueransim_disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.id
    network_ip = var.ueransim_ip
    # No public IP — access via OCI WireGuard bastion and and IAP(ssh on console)
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${local.ssh_public_key}"
    startup-script = <<-EOF
      #!/bin/bash
      set -e
      exec > /var/log/startup-script.log 2>&1

      # ---- First Boot Check ----
      INIT_FLAG="/var/lib/startup-complete"
      if [ -f "$INIT_FLAG" ]; then
        echo "Already initialized — starting services only"
        systemctl start ueransim-gnb || true
        systemctl start ueransim-ue || true
        exit 0
      fi

      echo "=== Starting UERANSIM VM setup ==="

      # ---- System Updates ----
      apt-get update -y
      apt-get install -y \
        make \
        gcc \
        g++ \
        libsctp-dev \
        lksctp-tools \
        iproute2 \
        git \
        curl \
        wget \
        wireguard \
        wireguard-tools \
        net-tools \
        cmake

      # ---- Load SCTP module (required for NGAP N2 interface) ----
      modprobe sctp
      echo "sctp" >> /etc/modules-load.d/sctp.conf

      # ---- Build UERANSIM ----
      git clone https://github.com/aligungr/UERANSIM /home/ubuntu/UERANSIM
      cd /home/ubuntu/UERANSIM
      make -j$(nproc)
      chown -R ubuntu:ubuntu /home/ubuntu/UERANSIM

      # ---- WireGuard Keys ----
      mkdir -p /etc/wireguard
      wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
      chmod 600 /etc/wireguard/private.key
      UERANSIM_PUBLIC_KEY=$(cat /etc/wireguard/public.key)
      echo "ueransim WireGuard public key: $UERANSIM_PUBLIC_KEY" > /home/ubuntu/wireguard-keys.txt
      chown ubuntu:ubuntu /home/ubuntu/wireguard-keys.txt

      # ---- Systemd Service — gNB ----
      cat > /etc/systemd/system/ueransim-gnb.service << 'SVCEOF'
[Unit]
Description=UERANSIM gNB — 5G Base Station Simulator
After=network.target wg-quick@wg0.service
Wants=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/UERANSIM
ExecStart=/home/ubuntu/UERANSIM/build/nr-gnb -c /home/ubuntu/UERANSIM/config/free5gc-gnb.yaml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCEOF

      # ---- Systemd Service — UE ----
      cat > /etc/systemd/system/ueransim-ue.service << 'SVCEOF'
[Unit]
Description=UERANSIM UE — User Equipment Simulator
After=ueransim-gnb.service
Wants=ueransim-gnb.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/UERANSIM
ExecStartPre=/bin/sleep 15
ExecStart=/home/ubuntu/UERANSIM/build/nr-ue -c /home/ubuntu/UERANSIM/config/free5gc-ue.yaml
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
SVCEOF

      systemctl daemon-reload
      systemctl enable ueransim-gnb
      systemctl enable ueransim-ue

      echo "=== UERANSIM VM setup complete ===" | tee -a /home/ubuntu/ready.txt
      chown ubuntu:ubuntu /home/ubuntu/ready.txt
      touch "$INIT_FLAG"
    EOF
  }

  labels = {
    role = "ueransim"
    lab  = "telecom-5g"
  }

  service_account {
    scopes = ["cloud-platform"]
  }
}
