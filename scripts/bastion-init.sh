#!/bin/bash
# ============================================
# bastion-init.sh
# OCI Bastion VM initialization script
# Runs on first boot via cloud-init user_data
# ============================================

set -e
exec > /var/log/bastion-init.log 2>&1

echo "=== Starting OCI Bastion initialization ==="
echo "Timestamp: $(date)"

# ---- System Updates ----
apt-get update -y
apt-get install -y \
  wireguard \
  wireguard-tools \
  curl \
  wget \
  jq \
  net-tools \
  iproute2 \
  iptables \
  iptables-persistent

# ---- IP Forwarding ----
# Required for WireGuard to route traffic between peers
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p

# ---- WireGuard Key Generation ----
mkdir -p /etc/wireguard
wg genkey | tee /etc/wireguard/server_private.key | \
  wg pubkey > /etc/wireguard/server_public.key
chmod 755 /etc/wireguard
chmod 600 /etc/wireguard/server_private.key
chmod 644 /etc/wireguard/server_public.key

SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)

# ---- WireGuard Server Config ----
cat > /etc/wireguard/wg0.conf << WGEOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = 10.10.0.1/24
# Port injected by Terraform templatefile()
ListenPort = ${wireguard_port}
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE

# ============================================
# Add GCP VM peers after terraform apply
# Run scripts/wireguard-setup.sh to configure
# ============================================

# GCP core-5g VM — uncomment and add key after deployment
# [Peer]
# PublicKey = <core-5g-wg-public-key>
# AllowedIPs = 10.10.0.3/32
# PersistentKeepalive = 25

# GCP ueransim VM — uncomment and add key after deployment
# [Peer]
# PublicKey = <ueransim-wg-public-key>
# AllowedIPs = 10.10.0.4/32
# PersistentKeepalive = 25
WGEOF

chmod 600 /etc/wireguard/wg0.conf

# ---- Save Keys for Reference ----
cat > /home/ubuntu/wireguard-info.txt << EOF
=== OCI Bastion WireGuard Info ===
Generated: $(date)

Public Key (share with GCP VMs):
$SERVER_PUBLIC_KEY

WireGuard IP: 10.10.0.1
Listen Port: ${wireguard_port}

Next Steps:
1. Get public keys from GCP VMs
2. Run: sudo ./scripts/wireguard-setup.sh <core-key> <ueransim-key>
3. Start WireGuard: sudo wg-quick up wg0
EOF

chown ubuntu:ubuntu /home/ubuntu/wireguard-info.txt

# ---- Create Scripts Directory ----
mkdir -p /home/ubuntu/scripts
chown -R ubuntu:ubuntu /home/ubuntu/scripts

# ---- Enable WireGuard on Boot ----
systemctl enable wg-quick@wg0

# ---- Done ----
echo "=== OCI Bastion initialization complete ===" 
echo "Timestamp: $(date)"
echo "WireGuard public key: $SERVER_PUBLIC_KEY"
echo "Ready." > /home/ubuntu/ready.txt
chown ubuntu:ubuntu /home/ubuntu/ready.txt
