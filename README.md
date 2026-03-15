# 5G Core Cloud-Native Lab

> A 60-day hands-on portfolio project building a production-grade, cloud-native 5G core from scratch — across GCP and OCI — using open-source tools.

**Status:** Week 1 complete ✅ | Week 2 in progress 🔄

---

## Architecture Overview

```
                        ┌─────────────────────────────────────────────┐
                        │           OCI (Always Free Tier)            │
                        │                                             │
                        │   ┌─────────────────────────────────────┐   │
                        │   │     Bastion VM (WireGuard Hub)      │   │
                        │   │     Public: xxx.xxx.xxx.xxx         │   │
                        │   │     WireGuard: 10.10.0.1/24         │   │
                        │   └──────────────┬──────────────────────┘   │
                        └─────────────────-│───────────────────────────┘
                                           │ WireGuard Mesh
                   ┌───────────────────────┴───────────────────┐
                   │                                           │
     ┌─────────────▼──────────────┐           ┌───────────────-▼─────────────┐
     │      GCP VM: core-5g       │           │    GCP VM: ueransim          │
     │      10.0.2.3              │           │    10.0.2.2                  │
     │      WG: 10.10.0.3         │           │    WG: 10.10.0.4             │
     │                            │           │                              │
     │  ┌──────────────────────┐  │  N2/NGAP  │  ┌────────────────────────┐  │
     │  │   Free5GC v4.2       │◄─┼──SCTP─────┼──│   UERANSIM v3.2.7      │  │
     │  │   (14 CNFs)          │  │  :38412   │  │   nr-gnb (gNB)         │  │
     │  │  AMF  SMF  UPF  NRF  │◄─┼──N3/GTP───┼──│   nr-ue  (UE)          │  │
     │  │ WEBUI   UDM  UDR     │  │  :2152    │  └────────────────────────┘  │
     │  │  PCF  AUSF NEF CHF   │  │           │                              │
     │  │ N3IWUE N3IWF MONGO   │  │           │  uesimtun0: 10.60.0.x        │
     │  └──────────────────────┘  │           │  ping 8.8.8.8 ✅             │
     │                            │           └──────────────────────────────┘
     │  Docker Compose + gtp5g    │
     │  UPF: network_mode: host   │
     └────────────────────────────┘
                   │
                   │ NAT (ens4)
                   ▼
              Internet (8.8.8.8)
```

---

## Results

| Test | Result |
|------|--------|
| UE Registration | ✅ MM-REGISTERED/NORMAL-SERVICE |
| PDU Session | ✅ uesimtun0 and uesimtun1 up for UEs 1&2 resp., IP: 10.60.0.1 and 10.60.0.2 |
| Internet ping | ✅ 0% loss, ~1ms RTT |
| GTP-U trace | ✅ N3 traffic confirmed on port 2152 |


---

## Weekly Progress

| Week | Focus | Status |
|------|-------|--------|
| 0 | Multi-cloud infra (Terraform + WireGuard) | ✅ Complete |
| 1 | Free5GC + UERANSIM on Docker Compose | ✅ Complete |
| 2 | k3s + Cilium + Free5GC on Kubernetes | 🔄 In progress |
| 3 | Prometheus + Grafana observability | ⏳ Planned |
| 4 | ArgoCD GitOps | ⏳ Planned |
| 5 | CI/CD with GitHub Actions | ⏳ Planned |
| 6 | Go-based NGAP parser | ⏳ Planned |

---

## Stack

| Component | Technology |
|-----------|------------|
| 5G Core | Free5GC v4.2 |
| RAN Simulator | UERANSIM v3.2.7 |
| Kernel module | gtp5g v0.9.14 |
| Orchestration | Docker Compose → Kubernetes (k3s) |
| CNI | Cilium (Week 2) |
| Cloud | GCP (2x T2d VMs, Cloud NAT) + OCI (Always Free) |
| VPN | WireGuard mesh |
| IaC | Terraform |
| OS | Ubuntu 22.04 LTS |
| Cost | ~$10/month |

---

## Week 0 — Multi-Cloud Infrastructure

### What was built
- OCI bastion VM as passive WireGuard hub
- 2 GCP VMs provisioned with Terraform (core-5g + ueransim)
- WireGuard mesh tunnel across OCI and GCP
- Startup scripts: Docker, gtp5g kernel module, UERANSIM build

### Key decisions
- **Passive WireGuard architecture** — bastion has no endpoints on peers; GCP VMs initiate connections to OCI bastion. Avoids NAT traversal issues.
- **Ubuntu 22.04** — 20.04 no longer available on GCP
- **gtp5g v0.9.14** — pinned for kernel 6.8.x compatibility
- **Docker from get.docker.com** — not apt repos (docker-compose-plugin availability)

### Files
```
infra/
├── main.tf           — provider config
├── compute.tf        — VM definitions + startup scripts for GCP VMs
├── oci.tf            — VM definitions for OCI VM (Bastion)
├── network.tf        — VPC, firewall rules, GCP Identity-Aware Proxy
├── scheduler.tf      — auto start/stop schedule
└── variables.tf      — input variables


```

---

## Week 1 — Free5GC + UERANSIM

### What was built
- Full 5G core (14 NFs) deployed via Docker Compose on core-5g VM
- External UERANSIM VM as gNB + UE (not the built-in container in free5gc-compose)
- End-to-end 5G data connectivity achieved

### Key configuration decisions

#### AMF
```yaml
ngapIpList:
  - 0.0.0.0        # bind all interfaces inside container
ngapPort: 38412
```
Docker port mapping: `38412:38412/sctp`

#### UPF
```yaml
# network_mode: host (in docker-compose.yaml)
pfcp:
  addr: 10.0.2.3   # host IP — container uses host network
  nodeID: 10.0.2.3
gtpu:
  ifList:
    - addr: 0.0.0.0
      type: N3
```

#### SMF
```yaml
pfcp:
  nodeID: smf.free5gc.org
  listenAddr: smf.free5gc.org
  externalAddr: smf.free5gc.org
userplaneInformation:
  upNodes:
    UPF:
      nodeID: 10.0.2.3     # must match UPF pfcp.nodeID
      addr: 10.0.2.3       # SMF reaches UPF via host IP
      interfaces:
        - interfaceType: N3
          endpoints:
            - 10.0.2.3     # gNB sends GTP-U here
```

#### UERANSIM gNB
```yaml
linkIp: 10.0.2.2
ngapIp: 10.0.2.2
gtpIp: 10.0.2.2
amfConfigs:
  - address: 10.0.2.3
    port: 38412
```

#### NAT (on core-5g VM)
```bash
sudo iptables -t nat -A POSTROUTING -s 10.60.0.0/16 -o ens4 -j MASQUERADE
sudo iptables -I FORWARD 1 -j ACCEPT
```
Persisted via `upf-iptables.sh` (runs on UPF container start).

### Lessons learned

**Docker DNS vs host IP boundaries** — the hardest part of this deployment.
- NFs on `privnet` resolve each other via Docker DNS (`nrf.free5gc.org`, `smf.free5gc.org`, etc.)
- UPF must be in `network_mode: host` for GTP-U kernel module access — loses Docker DNS
- AMF must stay on `privnet` to resolve NRF, but expose SCTP port externally via port mapping
- SMF PFCP `listenAddr` must use Docker DNS (container IP), but UPF `nodeID`/`addr` must use host IP

**SCTP port mapping** — Docker handles SCTP differently from TCP/UDP. Requires kernel SCTP module loaded on host (`modprobe sctp`).

**UPF PFCP addr** — comment in upfcfg.yaml says "Can't set to 0.0.0.0" — this is true and causes a nil pointer panic in SMF if violated.

**NAT interface** — GCP uses `ens4` not `eth0`. Wrong interface = silent traffic drop on user plane.

### Files
```
week1-free5gc-docker/
├── docker-compose.yaml
├── config/
│   ├── amfcfg.yaml
│   ├── smfcfg.yaml
│   ├── upfcfg.yaml
│   ├── nrfcfg.yaml
│   └── upf-iptables.sh
├── ueransim/
│   ├── free5gc-gnb.yaml
│   ├── free5gc-ue.yaml
│   └── free5gc-ue2.yaml
├── screenshots/
└── captures/
```

---

## Quickstart

### Prerequisites
- GCP account + OCI account (Always Free)
- Terraform >= 1.3.0
- SSH key pair

### 1. Provision infrastructure
```bash
cd infra/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GCP project, OCI tenancy etc.
terraform init
terraform apply
```

### 2. Set up WireGuard
```bash
# See docs/wireguard-setup.md for step-by-step instructions
```

### 3. Deploy Free5GC
```bash
# SSH into core-5g VM
# Option 1 — via WireGuard bastion
ssh -i ~/.ssh/your-key -J ubuntu@<bastion-ip> ubuntu@10.10.0.3

# Option 2 — via GCP Identity-Aware Proxy (IAP)
gcloud compute ssh core-5g --tunnel-through-iap --zone=us-south1-a

cd ~/free5gc-compose
docker compose up -d
docker ps  # verify all 14 NFs running
```

### 4. Start UERANSIM
```bash
# SSH into ueransim VM
# Option 1 — via WireGuard bastion
ssh -i ~/.ssh/your-key -J ubuntu@<bastion-ip> ubuntu@10.10.0.4

# Option 2 — via GCP Identity-Aware Proxy (IAP)
gcloud compute ssh ueransim --tunnel-through-iap --zone=us-south1-a

# Terminal 1 — gNB
cd ~/UERANSIM
sudo ./build/nr-gnb -c config/free5gc-gnb.yaml

# Terminal 2 — UE1
sudo ./build/nr-ue -c config/free5gc-ue.yaml

# Terminal 3 — UE2 (Optional)
sudo ./build/nr-ue -c config/free5gc-ue2.yaml

```

### 5. Verify connectivity
```bash
# On ueransim VM
ping -I uesimtun0 8.8.8.8
curl --interface uesimtun0 ifconfig.me

```

---

## Cost

| Resource | Cost |
|----------|------|
| GCP core-5g (T2d-Standard-4) | less than $4/month |
| GCP ueransim (T2d-Standard-2) | less than $2/month |
| GCP Cloud NAT | less than $1.5/month |
| OCI bastion | Free (Always Free tier) |
| GCP egress | Free (within free tier) |
| **Total** | **less than $8/month** |

VMs are scheduled to run for 6 hours daily to minimise cost.

---

## Security Notes

- WireGuard private keys are **never committed** — see `.gitignore`
- Terraform state files are **never committed**
- All inter-VM traffic is encrypted via WireGuard
- GCP firewall restricts inbound access to WireGuard port only

---
> **Note:** This README will be updated weekly as the lab progresses.
---

## References

- [Free5GC Documentation](https://free5gc.org)
- [UERANSIM](https://github.com/aligungr/UERANSIM)
- [gtp5g kernel module](https://github.com/free5gc/gtp5g)
- [3GPP TS 23.501](https://www.3gpp.org/ftp/Specs/archive/23_series/23.501/) — 5G System Architecture

---

## Author

**Idemudia Charles Okojie** — Packet Core & Cloud SME @ Ericsson Nigeria  
[LinkedIn](https://www.linkedin.com/in/idemudia-okojie-72259354/) · [GitHub](https://github.com/Charlz234)
