#!/bin/bash
set -eo pipefail
exec > /var/log/startup-script.log 2>&1

trap 'echo "ERROR: Script failed at line $LINENO - command: $BASH_COMMAND" >> /var/log/startup-script.log' ERR

# ---- First Boot Check ----
INIT_FLAG="/var/lib/startup-complete"
if [ -f "$INIT_FLAG" ]; then
  echo "Already initialized - k3s starts automatically via systemd"
  exit 0
fi

echo "=== Starting 5G Core VM setup ==="
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
  git \
  curl \
  wget \
  net-tools \
  iproute2 \
  iptables \
  linux-headers-$(uname -r) \
  build-essential \
  gcc-12 \
  jq \
  python3

# ---- IP Forwarding ----
echo 'net.ipv4.ip_forward=1'          >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p

# ---- TUN Device ----
mkdir -p /dev/net
mknod /dev/net/tun c 10 200 || true
chmod 666 /dev/net/tun

# ---- Docker (iptables DISABLED - prevents SCTP hijacking on port 38412) ----
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

# ---- Go ----
GO_VERSION="1.25.5"
retry wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz -O /tmp/go.tar.gz
tar -C /usr/local -xzf /tmp/go.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/ubuntu/.bashrc
echo 'export GOPATH=/home/ubuntu/go'       >> /home/ubuntu/.bashrc
echo 'export GOROOT=/usr/local/go'         >> /home/ubuntu/.bashrc
rm /tmp/go.tar.gz
export PATH=$PATH:/usr/local/go/bin

# ---- gtp5g Kernel Module ----
# Build with gcc-12 specifically - gcc-13+ breaks gtp5g v0.9.14
# Do NOT add to modules-load.d - UPF pod must be sole owner of upfgtp interface
retry git clone -b v0.9.14 https://github.com/free5gc/gtp5g /tmp/gtp5g
cd /tmp/gtp5g
make CC=gcc-12
make install
modprobe gtp5g || true
echo "gtp5g install: $?" >> /var/log/startup-script.log

# Rebuild helper for GCP kernel auto-updates
cat > /usr/local/bin/rebuild-gtp5g.sh << 'GEOF'
#!/bin/bash
cd /tmp/gtp5g && make CC=gcc-12 && make install && modprobe gtp5g
GEOF
chmod +x /usr/local/bin/rebuild-gtp5g.sh

cd /home/ubuntu

# ---- k3s ----
retry curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-backend=none \
  --disable-network-policy \
  --disable=traefik \
  --disable=servicelb" sh -

mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config
chmod 600 /home/ubuntu/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> /home/ubuntu/.bashrc

# Auto-refresh kubeconfig on login
cat >> /home/ubuntu/.bashrc << 'BASHEOF'

if [ -f /etc/rancher/k3s/k3s.yaml ]; then
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config 2>/dev/null
  sudo chown $USER ~/.kube/config 2>/dev/null
  chmod 600 ~/.kube/config 2>/dev/null
fi
BASHEOF

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# ---- Helm ----
retry curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ---- Wait for k3s node Ready ----
echo "Waiting for k3s node to be ready..."
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  echo "  still waiting for k3s..."
  sleep 5
done
echo "k3s node is Ready at $(date)"

# ---- Cilium ----
retry helm repo add cilium https://helm.cilium.io/
retry helm repo update

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

kubectl patch cm cilium-config -n kube-system \
  --type merge \
  -p '{"data":{"custom-cni-conf":"true","cni-exclusive":"false"}}'

# Write CNI configs
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

# ---- Multus ----
retry kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
kubectl rollout status ds/kube-multus-ds -n kube-system --timeout=120s

# Patch Multus memory limit - prevents OOMKills from CNI floods during NF startup
kubectl patch ds kube-multus-ds -n kube-system --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"256Mi"}]'

# CNI plugins bundle - host-device plugin required for Multus NADs
CNI_VERSION="v1.6.2"
retry curl -L https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz \
  -o /tmp/cni-plugins.tgz
mkdir -p /opt/cni/bin
tar -xzf /tmp/cni-plugins.tgz -C /opt/cni/bin/
echo "CNI plugins: $(ls /opt/cni/bin/ | tr '\n' ' ')" >> /var/log/startup-script.log

# Re-write Multus as primary after plugin install
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

# ---- Dummy Network Interfaces ----
# GCP hypervisor blocks ipvlan/macvlan - dummy interfaces + host-device is the workaround
modprobe dummy
echo "dummy" > /etc/modules-load.d/dummy.conf

ip link add n2dummy type dummy && ip link set n2dummy up || true
ip link add n3dummy type dummy && ip link set n3dummy up || true
ip link add n3upf   type dummy && ip link set n3upf   up || true

mkdir -p /etc/systemd/network

cat > /etc/systemd/network/10-n2dummy.netdev << 'EOF'
[NetDev]
Name=n2dummy
Kind=dummy
EOF

cat > /etc/systemd/network/10-n2dummy.network << 'EOF'
[Match]
Name=n2dummy
[Network]
EOF

cat > /etc/systemd/network/10-n3dummy.netdev << 'EOF'
[NetDev]
Name=n3dummy
Kind=dummy
EOF

cat > /etc/systemd/network/10-n3dummy.network << 'EOF'
[Match]
Name=n3dummy
[Network]
EOF

cat > /etc/systemd/network/10-n3upf.netdev << 'EOF'
[NetDev]
Name=n3upf
Kind=dummy
EOF

cat > /etc/systemd/network/10-n3upf.network << 'EOF'
[Match]
Name=n3upf
[Network]
EOF

systemctl enable systemd-networkd
systemctl restart systemd-networkd

echo "Dummy interfaces: $(ip link show | grep dummy | tr '\n' ' ')" >> /var/log/startup-script.log

# ---- ArgoCD ----
kubectl create namespace argocd
retry kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.0.0/manifests/install.yaml

echo "Waiting for ArgoCD server rollout..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

# Patch argocd-server to insecure mode - avoids self-signed TLS certificate warnings on port-forward
kubectl patch deployment argocd-server -n argocd --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'

# ---- NAT stabilisation wait ----
# ArgoCD scheduling causes NAT port churn - wait before further outbound calls
echo "Waiting 60s for NAT to stabilise after ArgoCD pod scheduling..."
sleep 60

# ---- kube-prometheus-stack ----
retry helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
retry helm repo update

kubectl create namespace monitoring

# Read Grafana admin password from GCP instance metadata
GRAFANA_ADMIN_PASSWORD=$(curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/grafana-admin-password")

if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
  echo "ERROR: grafana-admin-password not found in instance metadata"
  exit 1
fi

kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  -n monitoring

# ---- Clone Free5GC K8s manifests ----
retry git clone https://github.com/Charlz234/free5gc-k8s /home/ubuntu/free5gc-k8s
chown -R ubuntu:ubuntu /home/ubuntu/free5gc-k8s
chmod +x /home/ubuntu/free5gc-k8s/restart-nfs.sh

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version 82.18.0 \
  --namespace monitoring \
  -f /home/ubuntu/free5gc-k8s/monitoring/kube-prometheus-stack-values.yaml \
  --set grafana.admin.existingSecret=grafana-admin-secret \
  --set grafana.admin.userKey=admin-user \
  --set grafana.admin.passwordKey=admin-password \
  --set grafana.grafana\.ini.auth.anonymous.enabled=true \
  --set grafana.grafana\.ini.auth.anonymous.org_role=Viewer \
  --set grafana.sidecar.dashboards.enabled=true \
  --set grafana.sidecar.dashboards.label=grafana_dashboard \
  --set-string grafana.sidecar.dashboards.labelValue="1" \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

echo "Waiting for Grafana rollout..."
kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring --timeout=180s

# ---- Free5GC namespace + NADs ----
kubectl create namespace free5gc
kubectl apply -f /home/ubuntu/free5gc-k8s/nad.yaml

# ---- Apply monitoring manifests ----
kubectl apply -f /home/ubuntu/free5gc-k8s/monitoring/free5gc-servicemonitors.yaml
kubectl apply -f /home/ubuntu/free5gc-k8s/monitoring/kubernetes-overview-dashboard-cm.yaml
kubectl apply --server-side -f /home/ubuntu/free5gc-k8s/monitoring/node-exporter-dashboard-cm.yaml
kubectl apply -f /home/ubuntu/free5gc-k8s/exporter/k8s/deployment.yaml
kubectl apply -f /home/ubuntu/free5gc-k8s/exporter/k8s/service.yaml
kubectl apply -f /home/ubuntu/free5gc-k8s/exporter/k8s/servicemonitor.yaml
kubectl apply -f /home/ubuntu/free5gc-k8s/exporter/k8s/grafana-nf-dashboard-cm.yaml
kubectl apply -f /home/ubuntu/free5gc-k8s/exporter/k8s/grafana-upf-dashboard-cm.yaml


# ---- ArgoCD Application (automated sync enabled - no manual trigger needed) ----
sleep 30
kubectl apply -f /home/ubuntu/free5gc-k8s/argocd-app.yaml

echo "=== 5G Core VM setup complete at $(date) ===" | tee /home/ubuntu/ready.txt
cat >> /home/ubuntu/ready.txt << 'READYEOF'

=== Manual Steps Required After First Boot ===

1. Access Grafana locally:
   #On core-5g VM:
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
   # From local machine:
   gcloud compute ssh core-5g --zone=us-south1-a --tunnel-through-iap -- -L 3000:localhost:3000
   # Open: http://localhost:3000

2. Access ArgoCD locally:
   #On core-5g VM:
   kubectl port-forward -n argocd svc/argocd-server 8080:80
   # From local machine:
   gcloud compute ssh core-5g --zone=us-south1-a --tunnel-through-iap -- -L 8080:localhost:8080

   #In another VM terminal, get the password. Username is admin
   kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
   # Open: http://localhost:8080

3. Verify ArgoCD synced Free5GC:
   kubectl get pods -n free5gc

4. Provision subscriber(s) via WebUI:
   #On core-5g VM::
   kubectl port-forward -n free5gc svc/webui 5000:5000
   # From local machine (separate terminal):
   gcloud compute ssh core-5g --zone=us-south1-a --tunnel-through-iap -- -L 5000:localhost:5000
   # Open: http://localhost:5000
   # Default login: admin / free5gc

5. Start UERANSIM (on ueransim VM) and run E2E test:
   ping -I uesimtun0 8.8.8.8

Startup log: /var/log/startup-script.log
READYEOF

chown ubuntu:ubuntu /home/ubuntu/ready.txt

# INIT_FLAG set last - only if everything above succeeded
touch "$INIT_FLAG"
echo "=== Startup script complete at $(date) ==="