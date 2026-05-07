# 5G Core Cloud-Native Lab

> A 60-day hands-on portfolio project building a production-grade, cloud-native 5G core from scratch on GCP - using open-source tools, real Kubernetes networking, and full GitOps automation.

**Author:** Idemudia Charles Okojie - Packet Core & Cloud SME, Ericsson Nigeria
[LinkedIn](https://www.linkedin.com/in/idemudia-okojie-72259354/) | [GitHub](https://github.com/Charlz234)

**Status:** Week 7 complete ✅ | Week 8 in progress 🔄

---

## Who This Is For

This lab is designed as a portfolio project but the Terraform playbook is fully 
reproducible. If you are a cloud engineer, DevOps engineer, or telecom professional 
who wants hands-on experience with cloud-native 5G infrastructure, you can spin up 
your own private instance with `terraform apply`.

No prior 5G knowledge required - the stack is documented end to end.

---

## What This Project Is

Most 5G cloud-native content stops at Docker Compose. This project goes further - migrating a full free5GC v4.2 deployment through every layer of a real production stack: container orchestration, eBPF networking, GitOps, CI/CD, and live observability.

The lab is live and reproducible.

---

## Live Demo

| Service | URL | Access |
|:--------|:----|:-------|
| Grafana (5G metrics) | [grafana.niv-dev.xyz](https://grafana.niv-dev.xyz) | Anonymous read-only |


---

## Project Roadmap

| Week | Milestone | Tech Stack | Status |
|:-----|:----------|:-----------|:-------|
| **Week 1** | [Docker Compose Baseline](./week1-free5gc-docker/) | Docker Compose, gtp5g, UERANSIM | ✅ Complete |
| **Week 2** | [Kubernetes Migration](./week2-free5gc-k8s/) | k3s, Cilium 1.19, Multus CNI, Hubble | ✅ Complete |
| **Week 3** | [Observability Stack](./week3-observability/) | Prometheus, Grafana, Cloudflare Tunnel | ✅ Complete |
| **Week 4** | GitOps & Helm | ArgoCD v3, Helm chart (12 NFs) | ✅ Complete |
| **Week 5** | CI/CD Pipelines | GitHub Actions → GHCR | ✅ Complete |
| **Week 6** | Metrics-Enabled NF Images + gtp5g Exporter | Go, Prometheus, custom kernel exporter | ✅ Complete |
| **Week 7** | Terraform Simplification + Rebuild Validation | Terraform, GCP-only 2-VM | ✅ Complete |
| **Week 8** | AI Query Interface + Live Demo Platform | Go CLI, LLM integration | 🔄 In Progress |

---

## Architecture

### Infrastructure

| VM | Role | Spec | Cost |
|:---|:-----|:-----|:-----|
| `core-5g` | 5G Core + k3s control plane | t2d-standard-2 spot, us-south1-a, 30GB | ~$10/mo 24/7 |
| `ueransim` | gNB + UE simulator | t2d-standard-1 spot, us-south1-a, 10GB | ~$5/mo 24/7 |

- GCP-only, (OCI dependency in previous weeks removed)
- Cloud NAT for outbound internet (no public IPs on VMs)
- SSH via IAP tunnel

### Kubernetes Stack

```
k3s v1.34.5
├── Cilium v1.19.1        - eBPF pod networking (vxlan, kubeProxy replacement)
├── Multus CNI (thick)    - multi-interface support for N2/N3 interfaces
├── ArgoCD v3.0.0         - GitOps, automated sync + selfHeal + prune
└── kube-prometheus-stack v82.18.0
    ├── Prometheus        - metrics collection via ServiceMonitors       
    └── Grafana           - dashboards (anonymous read access enabled)
```

### Free5GC NF Deployment (12 pods, `free5gc` namespace)

```
Mongodb → NRF → UDR → UDM → AUSF → PCF → NSSF → NEF → AMF → UPF → SMF → WebUI 
```

Managed entirely by ArgoCD via Helm chart at [`Charlz234/free5gc-k8s`](https://github.com/Charlz234/free5gc-k8s).

### Key Engineering Decisions

| Problem | Solution |
|:--------|:---------|
| GCP hypervisor blocks ipvlan/macvlan | Dummy interfaces + host-device CNI plugin |
| Cilium 1.19 dropped generic-veth chaining | Multus-primary architecture with manual `05-cilium.conflist` |
| SMF PFCP breaks on pod restart or VM preemption (stale ClusterIP) | DNS names for all PFCP endpoints in ConfigMap |
| GCP kernel auto-updates break gtp5g module | Rebuild helper script (`rebuild-gtp5g.sh`) |
| free5GC DockerHub images don't expose Prometheus | Built metrics-enabled images from source via GHA |

---

## Observability

### Grafana Dashboards

| Dashboard | Panels |
|:----------|:-------|
| CP NF Dashboard | SBI Latency p99, Active PDU Sessions, SBI Request Rate |
| UPF GTP5G Metrics | Interface RX/TX, UL/DL Throughput per UE, Active UE Sessions |
| Kubernetes Overview | Node CPU/Memory, Pod status |
| Node Exporter Full | System-level host metrics |

### gtp5g Exporter

A custom Go exporter (`exporter/`) scrapes GTP tunnel counters from the kernel via `/proc` and exposes them as Prometheus metrics. Built and published automatically via GitHub Actions to `ghcr.io/charlz234/gtp5g-exporter:latest`.

### CI/CD

Two GitHub Actions workflows:

- **`build-nf-images.yml`** - builds metrics-enabled free5GC NF images from source → pushes to GHCR
- **`build-exporter.yml`** - builds gtp5g-exporter on every push to `exporter/**` → pushes to GHCR

All images are public. No `imagePullSecret` required.

---

## Quick Start

### Prerequisites

- GCP account with billing enabled
- `gcloud` CLI authenticated
- Terraform >= 1.5
- Git

### Deploy

```bash
git clone https://github.com/Charlz234/5gcore-cloudnative-lab
cd 5gcore-cloudnative-lab/infra

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - set your GCP project ID and Grafana admin password

terraform init
terraform apply
```

Full cluster is ready in ~20 minutes. The startup script handles everything:
- k3s + Cilium + Multus install
- ArgoCD deploy + free5GC sync
- Prometheus + Grafana deploy
- gtp5g exporter deploy
- All dashboard ConfigMaps applied

### Access Grafana (local)

**Terminal 1 - SSH tunnel:**
```bash
gcloud compute ssh core-5g --zone=us-south1-a --tunnel-through-iap -- -L 3000:localhost:3000
```

**Terminal 2 (core-5g VM) - port-forward:**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open [http://localhost:3000](http://localhost:3000)

### Access ArgoCD (local)

**Terminal 1 - SSH tunnel:**
```bash
gcloud compute ssh core-5g --zone=us-south1-a --tunnel-through-iap -- -L 8080:localhost:8080
```

**Terminal 2 - port-forward:**
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:80
```

Open [http://localhost:8080](http://localhost:8080)

Get admin password:
```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

### Access WebUI - Subscriber Provisioning

**Terminal 1 - SSH tunnel:**
```bash
gcloud compute ssh core-5g --zone=us-south1-a --tunnel-through-iap -- -L 5000:localhost:5000
```

**Terminal 2 - port-forward:**
```bash
kubectl port-forward -n free5gc svc/webui 5000:5000
```

Open [http://localhost:5000](http://localhost:5000) - default login: `admin` / `free5gc`

Add subscriber:
- IMSI: `208930000000001`
- Key: `8baf473f2f8fd09487cccbd7097c6862`
- OPC: `8e27b6af0e692e750f32667a3b14605d`
- SST: `1`, SD: `010203`, DNN: `internet`

---

## UERANSIM Setup

UERANSIM runs on the second VM (`ueransim`, `10.0.2.2`). It is not automated - start manually after the subscriber is provisioned.

### SSH to UERANSIM VM

```bash
gcloud compute ssh ubuntu@ueransim --zone=us-south1-a --tunnel-through-iap
```

### Start gNB

```bash
# Terminal 1
sudo ~/UERANSIM/build/nr-gnb -c ~/UERANSIM/config/free5gc-gnb.yaml
```

### Start UE

```bash
# Terminal 2
sudo ~/UERANSIM/build/nr-ue -c ~/UERANSIM/config/free5gc-ue.yaml
```

### Verify E2E

```bash
ping -I uesimtun0 8.8.8.8
```

Expected: 0% packet loss, ~1ms RTT.

Working config files are provided in [`https://github.com/Charlz234/free5gc-k8s/tree/master/ueransim-config/`](https://github.com/Charlz234/free5gc-k8s/tree/master/ueransim-config/).

---

## Optional - Public Access via Cloudflare Tunnel

For a public demo URL (requires a domain with Cloudflare DNS):

```bash
# Install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o cloudflared.deb && sudo dpkg -i cloudflared.deb

# Authenticate and create tunnel
cloudflared tunnel login
cloudflared tunnel create free5gc-lab

# Create DNS routes
cloudflared tunnel route dns <TUNNEL-ID> grafana.yourdomain.xyz
cloudflared tunnel route dns <TUNNEL-ID> argocd.yourdomain.xyz


# Get ClusterIPs:
```bash
kubectl get svc -n monitoring kube-prometheus-stack-grafana
kubectl get svc -n argocd argocd-server


# Write config
sudo mkdir -p /etc/cloudflared /root/.cloudflared
sudo cp ~/.cloudflared/<TUNNEL-ID>.json /root/.cloudflared/
sudo tee /etc/cloudflared/config.yml <<EOF
tunnel: <TUNNEL-ID>
credentials-file: /root/.cloudflared/<TUNNEL-ID>.json

ingress:
  - hostname: grafana.yourdomain.xyz
    service: http://<GRAFANA-CLUSTERIP>:80
  - hostname: argocd.yourdomain.xyz
    service: http://<ARGOCD-CLUSTERIP>:80
  - service: http_status:404
EOF

# Install and start service
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```

---

## Repository Structure

```
5gcore-cloudnative-lab/
├── infra/                        # Terraform IaC (GCP)
│   ├── main.tf
│   ├── compute.tf
│   ├── network.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── startup/
│       ├── startup-core.sh       # Full automated stack install (~20 min)
│       └── startup-ueransim.sh   # UERANSIM build from source
├── week1-free5gc-docker/         # Docker Compose baseline + config files
├── week2-free5gc-k8s/            # Early k8s manifests + CNI notes
├── week3-observability/          # Prometheus + Grafana setup notes
└── docs/
    └── data-plane-flow.md
```

K8s manifests, Helm chart, and monitoring configs live in the companion repo:
[`Charlz234/free5gc-k8s`](https://github.com/Charlz234/free5gc-k8s)

---

## E2E Verification (Week 7)

| Check | Result |
|:------|:-------|
| All 12 NF pods Running | ✅ |
| ArgoCD sync status | ✅ Synced (37 resources) |
| UE registration (IMSI `208930000000001`) | ✅ |
| PDU session established | ✅ |
| `uesimtun0` IP | `10.60.0.1` |
| `ping -I uesimtun0 8.8.8.8` | ✅ 0% packet loss |
| Grafana CP NF Dashboard | ✅ Live metrics |
| Grafana UPF GTP5G Dashboard | ✅ Live tunnel counters |
| gtp5g-exporter | ✅ Running in monitoring namespace |

---

## Troubleshooting
If ArgoCD does not perform sync to make the cluster healthy, mostly upon VM preemption,
kindly run ~/free5gc-k8s/restart-nfs.sh

## Cost

| Scenario | Monthly Cost |
|:---------|:-------------|
| 24/7 (live demo) | ~$20/month |
| 8 hours/day (GCP Resource scheduler) | ~$9/month |
| Destroyed (terraform destroy) | $0 |
