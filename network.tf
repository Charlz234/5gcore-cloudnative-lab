# ============================================
# GCP Networking
# ============================================

resource "google_compute_network" "telecom_lab_vpc" {
  name                    = "telecom-lab-vpc"
  auto_create_subnetworks = false
  description             = "Private VPC for 5G telecom lab"
}

resource "google_compute_subnetwork" "private_subnet" {
  name                     = "private-subnet"
  ip_cidr_range            = "10.0.2.0/24"
  region                   = var.gcp_region
  network                  = google_compute_network.telecom_lab_vpc.id
  private_ip_google_access = true
  description              = "Private subnet for 5g-core and ueransim VMs"
}

# Cloud Router — required for NAT
resource "google_compute_router" "lab_router" {
  name    = "telecom-lab-router"
  region  = var.gcp_region
  network = google_compute_network.telecom_lab_vpc.id
}

# Cloud NAT — allows private VMs outbound internet
resource "google_compute_router_nat" "lab_nat" {
  name                               = "telecom-lab-nat"
  router                             = google_compute_router.lab_router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# Allow all internal VPC traffic
# because 5g-core and ueransim communicate over N1/N2/N3
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.telecom_lab_vpc.id

  allow {
    protocol = "all"
  }

  source_ranges = ["10.0.0.0/8"]
  description   = "Allow all internal traffic including WireGuard subnet"
}

# Allow WireGuard UDP from OCI bastion
resource "google_compute_firewall" "allow_wireguard" {
  name    = "allow-wireguard"
  network = google_compute_network.telecom_lab_vpc.id

  allow {
    protocol = "udp"
    ports    = [tostring(var.wireguard_port)]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["lab-vm"]
  description   = "Allow WireGuard tunnel from OCI bastion"
}

# Allow ICMP for troubleshooting inside GCP VMs: between 5G Core and UERANSIM
resource "google_compute_firewall" "allow_icmp" {
  name    = "allow-icmp"
  network = google_compute_network.telecom_lab_vpc.id

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/8"]
  description   = "Allow ping within lab network"
}
