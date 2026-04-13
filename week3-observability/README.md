# Week 3 — Observability Stack

**Prometheus + Grafana on k3s, exposed via Cloudflare Tunnel**

Live dashboard: [grafana.niv-dev.xyz](https://grafana.niv-dev.xyz)

---

## What this week covers

Building a production-grade observability stack on top of the Free5GC 5G core deployed in Week 2. The stack exposes real-time cluster and NF metrics via a public Grafana dashboard — no open inbound ports, no bastion host required.

---

## Architecture

```
Browser → Cloudflare edge (TLS) → cloudflared (systemd, core-5g)
       → Grafana ClusterIP      → Prometheus (cluster metrics)
                                → ServiceMonitors (NF metrics port 9089)
```

Key decisions:

- **Cloudflare Tunnel** instead of a load balancer or NodePort exposure — zero inbound firewall rules, TLS handled by Cloudflare
- **kube-prometheus-stack** Helm chart — deploys Prometheus Operator, Grafana, kube-state-metrics, and node-exporter in one release
- **Persistent storage** for both Prometheus TSDB (10Gi) and Grafana (2Gi) via `local-path` StorageClass — same as MongoDB, no extra cost on GCP
- **Anonymous viewer access** — public users land on dashboards without login; admin access via Kubernetes secret only
- **Dashboard provisioning via ConfigMaps** — dashboards survive pod restarts and fresh installs, no manual import needed

---

## Stack

| Component | Version | Role |
|-----------|---------|------|
| kube-prometheus-stack | 82.18.0 | Prometheus Operator + Grafana + exporters |
| Prometheus | v3.x | Metrics collection and TSDB |
| Grafana | v12.x | Visualization |
| cloudflared | 2026.3.0 | Tunnel to Cloudflare edge |
| node-exporter | latest | Host-level metrics |
| kube-state-metrics | latest | Cluster-level metrics |

---

## Prerequisites

- Week 2 setup complete — k3s + Cilium + Free5GC running
- Helm v3 installed
- Cloudflare account with your domain managed
- `kubectl` configured (`KUBECONFIG=/etc/rancher/k3s/k3s.yaml`)

---

## Deployment

### 1. Create Grafana admin secret

```bash
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=your-strong-password \
  -n monitoring --create-namespace
```

### 2. Deploy kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f monitoring/kube-prometheus-stack-values.yaml
```

### 3. Apply NF service patches and ServiceMonitors

```bash
# Patch NF services to expose metrics port 9089
kubectl apply -f templates/nf-services-metrics.yaml

# Apply updated NF ConfigMaps (metrics.enable: true)
kubectl apply -f templates/amf-configmap.yaml
kubectl apply -f templates/nrf-configmap.yaml
kubectl apply -f templates/smf-configmap.yaml
kubectl apply -f templates/upf-configmap.yaml
kubectl apply -f templates/ausf-configmap.yaml
kubectl apply -f templates/udm-configmap.yaml
kubectl apply -f templates/udr-configmap.yaml
kubectl apply -f templates/pcf-configmap.yaml
kubectl apply -f templates/nssf-configmap.yaml
kubectl apply -f templates/nef-configmap.yaml

# Rolling restart to pick up new configs
kubectl rollout restart deployment -n free5gc

# Deploy ServiceMonitors
kubectl apply -f monitoring/free5gc-servicemonitors.yaml
```

### 4. Apply provisioned dashboards

```bash
kubectl apply -f monitoring/node-exporter-dashboard-cm.yaml
kubectl apply -f monitoring/kubernetes-overview-dashboard-cm.yaml
```

### 5. Set up Cloudflare Tunnel

```bash
# Install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o cloudflared.deb
sudo dpkg -i cloudflared.deb

# Authenticate and create tunnel
cloudflared tunnel login
cloudflared tunnel create free5gc-lab
cloudflared tunnel route dns free5gc-lab grafana.your-domain.xyz

# Configure tunnel
sudo mkdir -p /etc/cloudflared
sudo cp ~/.cloudflared/config.yml /etc/cloudflared/
sudo cp ~/.cloudflared/<TUNNEL-ID>.json /etc/cloudflared/
sudo sed -i 's|/home/ubuntu/.cloudflared/|/etc/cloudflared/|' /etc/cloudflared/config.yml

# Install and start as systemd service
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

`~/.cloudflared/config.yml` structure:
```yaml
tunnel: free5gc-lab
credentials-file: /etc/cloudflared/<TUNNEL-ID>.json

ingress:
  - hostname: grafana.your-domain.xyz
    service: http://<GRAFANA_CLUSTERIP>:80
  - service: http_status:404

Get your Grafana ClusterIP:
```bash
kubectl get svc -A | grep grafana
```
Replace `<GRAFANA_CLUSTERIP>` with the IP in the CLUSTER-IP column.
```

---

## Accessing services

| Service | Method |
|---------|--------|
| Grafana (public) | `https://grafana.your-domain.xyz` |
| Grafana (admin) | Same URL → `/login` with secret credentials |
| Free5GC WebUI | `gcloud compute start-iap-tunnel core-5g 30500 --local-host-port=localhost:5000 --zone=us-south1-a` |
| Prometheus UI | `kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090` + IAP tunnel |

---

## Known limitations

- **NF application-level metrics** (AMF session count, PDU sessions, SBI request rate) are not yet flowing. The `free5gc/amf:v4.2.1` Docker Hub image parses the `metrics:` config block but does not start the HTTP server. Fix planned in Week 4 Helmification — switching to the official `free5gc-helm` image which has metrics compiled in.
- **UPF metrics** — UPF runs `hostNetwork: true`; scraping via PodMonitor is configured but data plane counters require the metrics server fix above.

---

## Troubleshooting

**502 Bad Gateway on Grafana URL**
```bash
kubectl get pods -n monitoring
# If Grafana is not Running:
kubectl rollout restart deployment/kube-prom-stack-grafana -n monitoring
```

**cloudflared not connecting**
```bash
sudo systemctl status cloudflared
sudo journalctl -u cloudflared -n 50
```

**UPF CrashLoopBackOff after reboot**
```bash
# gtp5g module needs rebuild after GCP kernel update
cd ~/gtp5g
make clean && make -j$(nproc) CC=gcc-12
sudo make install && sudo modprobe gtp5g
kubectl rollout restart deployment/upf -n free5gc
```

**Multus EOF errors / pods stuck in ContainerCreating**
```bash
bash ~/free5gc-k8s/restart-nfs.sh
```
The restart script handles gtp5g rebuild, Multus recovery, and monitoring stack restart automatically.

---

## Screenshots

See `week3-observability/screenshots/` for:
- Grafana dashboard at `grafana.niv-dev.xyz` (anonymous access)
- Node Exporter Full — CPU, memory, disk, network per node
- Kubernetes compute resources — pod-level breakdown
- `systemctl status cloudflared` — tunnel service running

---

## Dashboards

Two dashboards are provisioned automatically via ConfigMap:

- `node-exporter-dashboard-cm.yaml` — host-level metrics (CPU, memory, disk, network)
- `kubernetes-overview-dashboard-cm.yaml` — cluster-level metrics (pod count, resource requests/limits)

If deploying via ArgoCD (Week 4+), these are synced automatically on repo push.
For manual setup only:
```bash
kubectl apply -f monitoring/node-exporter-dashboard-cm.yaml
kubectl apply -f monitoring/kubernetes-overview-dashboard-cm.yaml
```

Dashboards appear in Grafana within ~30s. No restart required.


## Troubleshooting

### Grafana login fails despite correct secret
Grafana persists credentials in its internal DB (PVC). If the pod was ever started
before the secret was correctly wired, the DB holds a stale password.

Fix:
```bash
kubectl exec -n monitoring -it \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o name) \
  -- grafana cli admin reset-admin-password 'YOUR_PASSWORD'
```
Then login with `admin` / `YOUR_PASSWORD`. No pod restart needed.


## Repository structure

```
free5gc-k8s/
├── templates/              # NF Deployments, Services, ConfigMaps
│   ├── *-configmap.yaml    # All updated with metrics.enable: true
│   └── nf-services-metrics.yaml
├── monitoring/
│   ├── kube-prometheus-stack-values.yaml
│   ├── free5gc-servicemonitors.yaml
│   ├── node-exporter-dashboard-cm.yaml
│   └── kubernetes-overview-dashboard-cm.yaml
└── restart-nfs.sh          # Full cluster recovery script
```

---

## Next — Week 4

- Full Helm parameterisation of Free5GC manifests
- ArgoCD GitOps deployment
- Switch to free5gc-helm images to unlock NF application metrics
