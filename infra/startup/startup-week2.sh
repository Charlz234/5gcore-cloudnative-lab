#!/bin/bash
set -e
exec > /var/log/startup-script.log 2>&1

# ---- First Boot Check ----
INIT_FLAG="/var/lib/startup-complete"
if [ -f "$INIT_FLAG" ]; then
  echo "Already initialized — k3s starts automatically via systemd"
  exit 0
fi

echo "=== Starting 5G Core VM setup (Week 2 — Kubernetes) ==="
echo "Start time: $(date)"

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
  jq \
  python3

# ---- IP Forwarding ----
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p

# ---- TUN Device ----
mkdir -p /dev/net
mknod /dev/net/tun c 10 200 || true
chmod 666 /dev/net/tun

# ---- Docker (iptables DISABLED — prevents SCTP hijacking on port 38412) ----
curl -fsSL https://get.docker.com | sh
apt-get install -y docker-compose-plugin
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'DOCKEREOF'
{
  "iptables": false
}
DOCKEREOF
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

# ---- gtp5g Kernel Module ----
# NOTE: DO NOT add to modules-load.d — UPF pod must be sole owner of upfgtp interface
git clone -b v0.9.14 https://github.com/free5gc/gtp5g /tmp/gtp5g
cd /tmp/gtp5g
make
make install
modprobe gtp5g || true
echo "gtp5g install status: $?" >> /var/log/startup-script.log
cd /home/ubuntu

# ---- k3s ----
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-backend=none \
  --disable-network-policy \
  --disable=traefik \
  --disable=servicelb" sh -

# Set up kubeconfig for ubuntu user
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config
chmod 600 /home/ubuntu/.kube/config

echo 'export KUBECONFIG=~/.kube/config' >> /home/ubuntu/.bashrc
export KUBECONFIG=/home/ubuntu/.kube/config

# Auto-refresh kubeconfig on every login (k3s rewrites it as root on restart)
cat >> /home/ubuntu/.bashrc << 'BASHEOF'

# Auto-refresh kubeconfig from k3s on login
if [ -f /etc/rancher/k3s/k3s.yaml ]; then
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config 2>/dev/null
  sudo chown $USER ~/.kube/config 2>/dev/null
  chmod 600 ~/.kube/config 2>/dev/null
fi
BASHEOF

# ---- Helm ----
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ---- Wait for k3s node Ready ----
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "Waiting for k3s node to be ready..."
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  echo "  still waiting for k3s..."
  sleep 5
done
echo "k3s node is Ready at $(date)"

# ---- Cilium ----
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium --version 1.19.1 \
  --namespace kube-system \
  --set k8sServiceHost=127.0.0.1 \
  --set k8sServicePort=6443 \
  --set kubeProxyReplacement=true \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set operator.replicas=1 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.tls.enabled=false \
  --set hubble.relay.tls.server.enabled=false \
  --set cni.customConf=true \
  --set cni.exclusive=false \
  --set cluster.name=default

echo "Waiting for Cilium rollout..."
kubectl rollout status ds/cilium -n kube-system --timeout=180s

# Patch Cilium ConfigMap to hands-off CNI mode
kubectl patch cm cilium-config -n kube-system \
  --type merge \
  -p '{"data":{"custom-cni-conf":"true","cni-exclusive":"false"}}'

cat > /etc/cni/net.d/05-cilium.conflist << 'CNIEOF'
{
  "cniVersion": "0.3.1",
  "name": "cilium",
  "plugins": [
    {
       "type": "cilium-cni",
       "enable-debug": false,
       "log-file": "/var/run/cilium/cilium-cni.log"
    }
  ]
}
CNIEOF

cat > /etc/cni/net.d/00-multus.conf << 'CNIEOF'
{
  "cniVersion": "0.3.1",
  "name": "multus-cni-network",
  "type": "multus-shim",
  "logLevel": "verbose",
  "logToStderr": true,
  "clusterNetwork": "/host/etc/cni/net.d/05-cilium.conflist"
}
CNIEOF

kubectl delete pod -n kube-system -l app.kubernetes.io/name=cilium-agent
kubectl rollout status ds/cilium -n kube-system --timeout=120s

# Verify Cilium is in hands-off mode
CILIUM_CNI=$(kubectl -n kube-system exec ds/cilium -- cilium-dbg status 2>/dev/null | grep "CNI Config")
echo "Cilium CNI status: $CILIUM_CNI" >> /var/log/startup-script.log

# ---- Multus ----
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
kubectl rollout status ds/kube-multus-ds -n kube-system --timeout=120s

# Install full CNI plugins bundle (host-device plugin required for Multus NADs)
CNI_VERSION="v1.6.2"
curl -L https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz \
  -o /tmp/cni-plugins.tgz
mkdir -p /opt/cni/bin
tar -xzf /tmp/cni-plugins.tgz -C /opt/cni/bin/
echo "CNI plugins: $(ls /opt/cni/bin/ | tr '\n' ' ')" >> /var/log/startup-script.log

# Write Multus primary config
# Multus is primary CNI, Cilium is delegate
# Note: Cilium 1.19 dropped generic-veth chaining — Multus-primary is the correct approach
cat > /etc/cni/net.d/00-multus.conf << 'CNIEOF'
{
  "cniVersion": "0.3.1",
  "name": "multus-cni-network",
  "type": "multus-shim",
  "logLevel": "verbose",
  "logToStderr": true,
  "clusterNetwork": "/host/etc/cni/net.d/05-cilium.conflist"
}
CNIEOF

echo "CNI configs written: $(ls /etc/cni/net.d/)" >> /var/log/startup-script.log

# ---- Dummy Network Interfaces ----
# GCP hypervisor disables promiscuous mode — ipvlan/macvlan not available
# Using dummy interfaces + host-device plugin as workaround for Multus NADs
modprobe dummy
echo "dummy" > /etc/modules-load.d/dummy.conf

ip link add n2dummy type dummy && ip link set n2dummy up || true
ip link add n3dummy type dummy && ip link set n3dummy up || true
ip link add n3upf type dummy && ip link set n3upf up || true

# Persist dummy interfaces across reboots via systemd-networkd
mkdir -p /etc/systemd/network

cat > /etc/systemd/network/10-n2dummy.netdev << 'EOF'
[NetDev]
Name=n2dummy
Kind=dummy
EOF

cat > /etc/systemd/network/10-n3dummy.netdev << 'EOF'
[NetDev]
Name=n3dummy
Kind=dummy
EOF

cat > /etc/systemd/network/10-n3upf.netdev << 'EOF'
[NetDev]
Name=n3upf
Kind=dummy
EOF

systemctl enable systemd-networkd
systemctl restart systemd-networkd

# ---- WireGuard Keys ----
mkdir -p /etc/wireguard
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
chmod 600 /etc/wireguard/private.key
CORE_PUBLIC_KEY=$(cat /etc/wireguard/public.key)
echo "5g-core WireGuard public key: $CORE_PUBLIC_KEY" > /home/ubuntu/wireguard-keys.txt
chown ubuntu:ubuntu /home/ubuntu/wireguard-keys.txt

# ---- Clone Free5GC K8s manifests ----
git clone https://github.com/Charlz234/free5gc-k8s /home/ubuntu/free5gc-k8s
chown -R ubuntu:ubuntu /home/ubuntu/free5gc-k8s
chmod +x /home/ubuntu/free5gc-k8s/restart-nfs.sh

# ---- Deploy Free5GC namespace and NADs ----
kubectl create namespace free5gc
kubectl apply -f /home/ubuntu/free5gc-k8s/nad.yaml
kubectl apply -f /home/ubuntu/free5gc-k8s/templates/

echo "=== 5G Core VM setup complete (Week 2) at $(date) ===" | tee -a /home/ubuntu/ready.txt
cat >> /home/ubuntu/ready.txt << 'READYEOF'

IMPORTANT — WireGuard not configured yet. Steps:
1. Get your WireGuard public key:
   cat ~/wireguard-keys.txt

2. Update OCI bastion /etc/wireguard/wg0.conf with this VM's public key
   sudo wg set wg0 peer <this-vm-pubkey> allowed-ips 10.10.0.3/32

3. Create /etc/wireguard/wg0.conf on this VM (use bastion pubkey + endpoint)
   sudo wg-quick up wg0

4. Verify tunnel:
   ping 10.10.0.1

5. Start Free5GC:
   ~/free5gc-k8s/restart-nfs.sh

Startup log: /var/log/startup-script.log
READYEOF

chown ubuntu:ubuntu /home/ubuntu/ready.txt
touch "$INIT_FLAG"
echo "=== Startup script complete at $(date) ==="
