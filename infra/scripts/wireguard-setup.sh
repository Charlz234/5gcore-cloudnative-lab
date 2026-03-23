#!/bin/bash
# ============================================
# wireguard-setup.sh
# Run on OCI bastion AFTER all VMs are up
# Adds GCP VMs as WireGuard peers
# ============================================
# Usage:
#   chmod +x wireguard-setup.sh
#   sudo ./wireguard-setup.sh <core-5g-wg-pubkey> <ueransim-wg-pubkey>
#
# Get GCP VM public keys by running on each VM:
#   cat /etc/wireguard/public.key
# ============================================

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <core-5g-wg-public-key> <ueransim-wg-public-key>"
  echo ""
  echo "Steps to get keys:"
  echo "  1. ssh -J ubuntu@<bastion-ip> ubuntu@10.0.2.3"
  echo "     sudo cat /etc/wireguard/public.key"
  echo "  2. ssh -J ubuntu@<bastion-ip> ubuntu@10.0.2.2"
  echo "     sudo cat /etc/wireguard/public.key"
  exit 1
fi

CORE_PUBLIC_KEY="$1"
UERANSIM_PUBLIC_KEY="$2"
BASTION_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)
BASTION_PUBLIC_IP=$(curl -s ifconfig.me)

echo "=== Adding GCP VM peers to WireGuard ==="

# Add core-5g and ueransim peers to bastion config
cat >> /etc/wireguard/wg0.conf << EOF

[Peer]
# GCP core-5g VM
PublicKey = $CORE_PUBLIC_KEY
AllowedIPs = 10.10.0.3/32
PersistentKeepalive = 25

[Peer]
# GCP ueransim VM
PublicKey = $UERANSIM_PUBLIC_KEY
AllowedIPs = 10.10.0.4/32
PersistentKeepalive = 25
EOF

# Start WireGuard on bastion
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo ""
echo "=== Bastion WireGuard started ==="
echo "Bastion WireGuard IP: 10.10.0.1"
echo ""
echo "=== Now configure each GCP VM ==="
echo ""
echo "--- On core-5g (ssh -J ubuntu@$BASTION_PUBLIC_IP ubuntu@10.0.2.3) ---"
echo ""
echo "sudo bash -c 'cat > /etc/wireguard/wg0.conf << WGEOF"
echo "[Interface]"
echo "PrivateKey = \$(cat /etc/wireguard/private.key)"
echo "Address = 10.10.0.3/24"
echo ""
echo "[Peer]"
echo "PublicKey = $BASTION_PUBLIC_KEY"
echo "Endpoint = $BASTION_PUBLIC_IP:51820"
echo "AllowedIPs = 10.10.0.0/24"
echo "PersistentKeepalive = 25"
echo "WGEOF'"
echo ""
echo "sudo systemctl enable wg-quick@wg0"
echo "sudo systemctl start wg-quick@wg0"
echo ""
echo "--- On ueransim (ssh -J ubuntu@$BASTION_PUBLIC_IP ubuntu@10.0.2.2) ---"
echo ""
echo "sudo bash -c 'cat > /etc/wireguard/wg0.conf << WGEOF"
echo "[Interface]"
echo "PrivateKey = \$(cat /etc/wireguard/private.key)"
echo "Address = 10.10.0.4/24"
echo ""
echo "[Peer]"
echo "PublicKey = $BASTION_PUBLIC_KEY"
echo "Endpoint = $BASTION_PUBLIC_IP:51820"
echo "AllowedIPs = 10.10.0.0/24"
echo "PersistentKeepalive = 25"
echo "WGEOF'"
echo ""
echo "sudo systemctl enable wg-quick@wg0"
echo "sudo systemctl start wg-quick@wg0"
echo ""
echo "=== After configuring both GCP VMs, test tunnel ==="
echo "ping 10.10.0.3  # bastion to core-5g"
echo "ping 10.10.0.4  # bastion to ueransim"
