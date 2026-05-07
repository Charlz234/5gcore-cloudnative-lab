#!/bin/bash
set -eo pipefail
exec > /var/log/startup-script.log 2>&1

trap 'echo "ERROR: Script failed at line $LINENO — command: $BASH_COMMAND" >> /var/log/startup-script.log' ERR

# ---- First Boot Check ----
INIT_FLAG="/var/lib/startup-complete"
if [ -f "$INIT_FLAG" ]; then
  echo "Already initialized"
  exit 0
fi

echo "=== Starting UERANSIM VM setup ==="
echo "Start time: $(date)"

# ---- Retry Helper ----
retry() {
  local n=1 max=5 delay=15
  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        echo "Attempt $n/$max failed for: $*. Retrying in ${delay}s..."
        sleep $delay
        ((n++))
      else
        echo "ERROR: Command failed after $max attempts: $*"
        return 1
      fi
    }
  done
}

# ---- System Updates ----
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  make \
  gcc \
  g++ \
  libsctp-dev \
  lksctp-tools \
  iproute2 \
  git \
  curl \
  wget \
  net-tools \
  cmake

# ---- Load SCTP module (required for NGAP N2 interface) ----
modprobe sctp
echo "sctp" >> /etc/modules-load.d/sctp.conf

# ---- Build UERANSIM ----
retry git clone https://github.com/aligungr/UERANSIM /home/ubuntu/UERANSIM
cd /home/ubuntu/UERANSIM
make -j$(nproc)
chown -R ubuntu:ubuntu /home/ubuntu/UERANSIM

echo "=== UERANSIM VM setup complete at $(date) ===" | tee /home/ubuntu/ready.txt
cat >> /home/ubuntu/ready.txt << 'READYEOF'

=== How to run UERANSIM ===

1. Copy your config files to ~/UERANSIM/config/
   (free5gc-gnb.yaml, free5gc-ue.yaml, free5gc-ue2.yaml)
   Get templates from: https://github.com/Charlz234/free5gc-k8s/tree/master/ueransim-config (web browser)
   or git clone https://github.com/Charlz234/free5gc-k8s ,
   then navigate to free5gc-k8s/ueransim-config directory

2. Terminal 1 — gNB:
   cd ~/UERANSIM
   sudo ./build/nr-gnb -c config/free5gc-gnb.yaml

3. Terminal 2 — UE1:
   sudo ./build/nr-ue -c config/free5gc-ue.yaml

4. Terminal 3 — UE2 (optional):
   sudo ./build/nr-ue -c config/free5gc-ue2.yaml

5. Verify tunnel:
   ip addr show uesimtun0
   ping -I uesimtun0 8.8.8.8

Startup log: /var/log/startup-script.log
READYEOF

chown ubuntu:ubuntu /home/ubuntu/ready.txt
touch "$INIT_FLAG"
echo "=== Startup script complete at $(date) ==="