# free5gc-k8s

Free5GC v4.2 deployed on Kubernetes using k3s, Cilium, and Multus CNI.

This is a working reference implementation built as part of a 6-8 weeks cloud-native 5G portfolio. It runs on GCP spot VMs with a WireGuard mesh to an OCI bastion. End-to-end verified: UE registration, PDU session establishment, and ping 8.8.8.8 via uesimtun0.

> **Note:** Manifests are not yet fully templated via `values.yaml`. IPs and config are in the configmaps directly. Full Helm parameterisation is planned in the coming weeks.

---

## Architecture

```
UERANSIM VM (10.0.2.2)          core-5g VM (10.0.2.3)
┌─────────────────┐              ┌──────────────────────────────────────┐
│  gNB + UE sim   │──N2 (SCTP)──▶│  AMF  (hostNetwork)                  │
│  UERANSIM v3.2.7│──N3 (GTP-U)─▶│  UPF  (hostNetwork)                  │
└─────────────────┘              │                                      │
                                 │  k3s + Cilium v1.19 + Multus (thick) │
                                 │  NRF, SMF, PCF, AUSF, UDM, UDR,     │
                                 │  NEF, NSSF, WEBUI  (pod networking)  │
                                 │  MongoDB (PVC, local-path)           │
                                 └──────────────────────────────────────┘
                                          │
                                 OCI Bastion (WireGuard hub)
```

**Why AMF and UPF run on hostNetwork:**
- AMF needs NGAP/SCTP on N2 — SCTP doesn't work reliably through Kubernetes service proxying
- UPF needs GTP-U on N3 and direct kernel access for the gtp5g module
- Both appear as the `host` node in Hubble — this is expected, not a bug

**Why dummy interfaces instead of macvlan/ipvlan:**
GCP's hypervisor disables promiscuous mode. macvlan and ipvlan are blocked at the hypervisor level. Dummy interfaces with the host-device CNI plugin are the correct workaround for Multus NADs on GCP.

**Why Multus-primary (not Cilium-primary):**
Cilium 1.19 dropped generic-veth chaining. The old pattern of Cilium-primary + Multus as a meta-plugin no longer works. Multus is primary CNI, Cilium is the delegate via `05-cilium.conflist`.

---

## Prerequisites

| Component | Version |
|-----------|---------|
| k3s | v1.34.5 |
| Cilium | v1.19.1 |
| Multus CNI | thick daemonset (master branch) |
| Helm | v3.20.1 |
| gtp5g | v0.9.14 |
| gcc | 12 (required for gtp5g on GCP kernel) |
| Ubuntu | 22.04, kernel 6.8.0-x-gcp |

---

## Quick Start

### 1. Provision infrastructure

```bash
cd 5gcore-cloudnative-lab/infra/
terraform init
terraform apply
```

### 2. Configure WireGuard

After startup completes:
Login through gcloud IAP tunnel or Console SSH. Switch to ubuntu user with 'sudo su ubuntu'

```bash
# Get the core-5g WireGuard public key
cat ~/wireguard-keys.txt

# On OCI bastion — add core-5g as a peer
sudo wg set wg0 peer <core-5g-pubkey> allowed-ips 10.10.0.3/32

# On core-5g — create wg0.conf and bring up tunnel
sudo wg-quick up wg0

# Verify
ping 10.10.0.1
```

### 3. Start NFs

Startup script runs automatically (~15 mins). Installs k3s, Cilium, Multus, gtp5g, and deploys all NFs.
When VM is up, run ~/free5gc-k8s/restart-nfs.sh

### Existing VM restart
The startup script only runs once (first boot flag at /var/lib/startup-complete).
Use the same command ~/free5gc-k8s/restart-nfs.sh

The script restarts all NFs in the correct order with readiness checks between each.

**NF startup order:**
```
mongodb → nrf → udr → udm → ausf → pcf → nssf → nef → amf → upf → smf → webui
```

> UPF must start before SMF. SMF sends a PFCP association request immediately at startup - if UPF isn't ready, the N4 session fails silently.

### 4. Add a subscriber

Open the WebUI tunnel from your local machine:

```bash
ssh -i path/to/ubuntuVM-private-key -L 5000:10.10.0.3:30500 ubuntu@<bastion-ip>
```

Navigate to `http://localhost:5000`, login, and add a subscriber:

| Field | Value |
|-------|-------|
| IMSI | 208930000000001 |
| Key | 8baf473f2f8fd09487cccbd7097c6862 |
| OPC | 8e27b6af0e692e750f32667a3b14605d |
| SST | 1 |
| SD | 010203 |
| DNN | internet |

The default values are fine. Just click CREATE

### 5. Connect UERANSIM

On the UERANSIM VM:

```bash
# Start gNB
./nr-gnb -c config/free5gc-gnb.yaml &
The gnb and ue processes can be killed with 'sudo pkill -f nr-gnb' and 'sudo pkill -f nr-ue' if you want to start cleanly.

# Start UE
./nr-ue -c config/free5gc-ue.yaml
```

### 6. Verify end-to-end

```bash
ping -I uesimtun0 8.8.8.8
```

Expected: 0% packet loss, ~1ms RTT.

---

```

### Out of scope: Auto-start on boot

The restart-nfs script can be made to run as a systemd service so it runs at boot, but seeing the startup sequence and recognising when something goes wrong is part of the lab, so the systemd setup will be outside the lab's scope.

---

## Observability — Hubble UI

```bash
# On core-5g (keep terminal open)
kubectl port-forward -n kube-system svc/hubble-ui 12000:80 --address 0.0.0.0

# On local machine (keep terminal open)
ssh -i path/to/ubuntuVM-private-key -L 12000:10.10.0.3:12000 ubuntu@<bastion-public-ip>
```

Open `http://localhost:12000`, select the `free5gc` namespace.

AMF and UPF will not appear due to `hostNetwork: true`.
Hubble handles pod-pod communications due to the way Cilium interacts with the pods' interfaces in this lab.

---

## Repository Structure

```
free5gc-k8s/
├── Chart.yaml                  # Helm chart metadata
├── values.yaml                 # Configurable parameters (IPs, ports)
├── nad.yaml                    # Multus NetworkAttachmentDefinitions
├── restart-nfs.sh              # NF startup script (correct order + readiness checks)
└── templates/
    ├── namespace.yaml
    ├── mongodb-deployment.yaml  # + PVC (local-path StorageClass)
    ├── mongodb-pvc.yaml
    ├── nrf-deployment.yaml      + configmap
    ├── amf-deployment.yaml      + configmap  (hostNetwork)
    ├── upf-deployment.yaml      + configmap  (hostNetwork, iptables init container)
    ├── smf-deployment.yaml      + configmap
    ├── ausf-deployment.yaml     + configmap
    ├── udm-deployment.yaml      + configmap
    ├── udr-deployment.yaml      + configmap
    ├── pcf-deployment.yaml      + configmap
    ├── nssf-deployment.yaml     + configmap
    ├── nef-deployment.yaml      + configmap
    └── webui-deployment.yaml    + configmap
```

---

## Known Issues and Fixes


**Multus OOM or crash**
```bash
kubectl scale deployment -n free5gc --all --replicas=0
# Write CNI files if missing (see restart-nfs.sh step 5)
kubectl rollout restart ds kube-multus-ds -n kube-system
~/free5gc-k8s/restart-nfs.sh
```

**CNI files missing after reboot**
```bash
ls /etc/cni/net.d/
# Should contain 00-multus.conf AND 05-cilium.conflist
# If missing, restart-nfs.sh step 5 writes them automatically
```

**gtp5g not loaded after kernel update**
GCP updates kernels automatically. The gtp5g module is compiled against a specific kernel version and will fail silently after an update. Rebuild it with the below steps:
```bash
sudo apt-get install -y linux-headers-$(uname -r) gcc-12
cd /tmp && git clone -b v0.9.14 https://github.com/free5gc/gtp5g
cd gtp5g && make CC=gcc-12 && sudo make install && sudo modprobe gtp5g
```

**Subscriber data lost after pod restart**
Fixed in this repo — MongoDB uses a PersistentVolumeClaim (`mongodb-pvc`, `local-path` StorageClass). Data survives pod restarts and VM reboots.

---

## Roadmap

- [x] Week 1 — Docker Compose baseline (Free5GC + UERANSIM, end-to-end verified)
- [x] Week 2 — Kubernetes (k3s + Cilium + Multus + Hubble)
- [ ] Week 3 — Prometheus + Grafana observability
- [ ] Week 4 — ArgoCD GitOps + full Helm parameterisation
- [ ] Week 5 — GitHub Actions CI/CD pipeline
- [ ] Week 6 — Go-based NGAP parser
- [ ] Week 7 — Live demo platform

---

## Related Repo

[5gcore-cloudnative-lab](https://github.com/Charlz234/5gcore-cloudnative-lab) — Terraform IaC, startup scripts, and portfolio documentation.

---

## Author

Idemudia Charles Okojie  
Packet Core & Cloud SME — Ericsson Nigeria  
[GitHub](https://github.com/Charlz234) · [LinkedIn](https://www.linkedin.com/in/idemudia-okojie-72259354/)
