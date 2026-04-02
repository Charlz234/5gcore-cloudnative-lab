# 5G Core Cloud-Native Lab 

> A 60-day hands-on portfolio project building a production-grade, cloud-native 5G core from scratch — across GCP and OCI — using open-source tools.

**Status:** Week 2 complete ✅ | Week 3 in progress 🔄

---

## Project Roadmap

This project tracks the evolution of a 5G mobile core from a simple containerized setup to a fully automated, observable, cloud-native production environment.

| Phase | Milestone | Tech Stack | Status |
|:--- |:--- |:--- |:--- |
| **Week 1** | [**Docker Compose Baseline**](./week1-free5gc-docker/) | Docker Compose, gtp5g | ✅ Complete |
| **Week 2** | [**Kubernetes Migration**](./week2-free5gc-k8s/) | k3s, Cilium, Multus, Hubble | ✅ Complete |
| **Week 3** | **Observability & Monitoring** | Prometheus, Grafana, Loki | 🔄 In Progress |
| **Week 4** | **GitOps & Automation** | ArgoCD, Helm | ⏳ Planned |
| **Week 5** | **CI/CD Pipelines** | GitHub Actions | ⏳ Planned |
| **Week 6** | **Cloud-Native Development** | Go-based NGAP Parser | ⏳ Planned |

---

## Master Architecture

The lab utilizes a multi-cloud WireGuard mesh to bridge GCP (Data Plane/Core) and OCI (Management/Bastion).



### Infrastructure Highlights:
* **Multi-Cloud Mesh:** OCI Bastion acts as the WireGuard hub for GCP compute nodes.
* **Cost Optimization:** GCP Spot VMs with Terraform-managed auto-scaling and schedules (~$11/mo).
* **Networking:** eBPF-powered pod networking via Cilium 1.19 and multi-interface support via Multus.

---

## Global Tech Stack

* **5G Core:** Free5GC v4.2
* **RAN Sim:** UERANSIM v3.2.7
* **Cloud:** GCP (T2d VMs) & OCI (Always Free)
* **IaC:** Terraform
* **Networking:** WireGuard, Cilium (eBPF), Multus CNI
* **OS:** Ubuntu 22.04 LTS (Kernel 6.8.x)

---

## Repository Navigation

* [**/infra**](./infra): Terraform manifests for GCP and OCI.
* [**/week1-free5gc-docker**](./week1-free5gc-docker): Docker Compose setup, SCTP mapping lessons, and baseline verification.
* [**/week2-free5gc-k8s**](./week2-free5gc-k8s): K8s manifests, Cilium/Multus CNI chaining logic, and Hubble observability.

---

## Final Validation (Week 2)
End-to-end data path is verified. UE registration and PDU session establishment are successful with real-world internet reachability.

* **UE IP:** `10.60.0.1`
* **Ping Test:** `ping -I uesimtun0 8.8.8.8` ➔ 0% packet loss.
* **Throughput:** ~15 flows/sec across the SBI mesh visible in Hubble.

---

## Author

**Idemudia Charles Okojie**
Packet Core & Cloud SME — Ericsson Nigeria
[LinkedIn](https://www.linkedin.com/in/idemudia-okojie-72259354/) | [GitHub](https://github.com/Charlz234)