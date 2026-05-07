# ============================================
# GCP Compute — Spot VMs
# ============================================

locals {
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))
}

# ============================================
# 5G Core VM
# t2d-standard-2 spot | 2 vCPU | 8GB | 30GB
# Runs: Free5GC, k3s, Cilium, Multus, ArgoCD,
#       Prometheus, Grafana, gtp5g-exporter
# Access: gcloud compute ssh core-5g --zone=us-south1-a --tunnel-through-iap
# ============================================
resource "google_compute_instance" "core_5g" {
  name           = "core-5g"
  machine_type   = var.core_machine_type
  zone           = var.gcp_zone
  can_ip_forward = true
  tags           = ["lab-vm"]

  scheduling {
    preemptible         = true
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    provisioning_model  = "SPOT"
  }

  boot_disk {
    initialize_params {
      image = var.ubuntu_image
      size  = var.core_disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.id
    network_ip = var.core_5g_ip
    # No public IP — SSH via IAP: gcloud compute ssh core-5g --tunnel-through-iap --zone=us-south1-a
  }

  metadata = {
    ssh-keys       = "${var.ssh_user}:${local.ssh_public_key}"
    startup-script = file("${path.module}/${var.core_startup_script}")
    grafana-admin-password = var.grafana_admin_password
    enable-oslogin = "FALSE"
  }

  labels = {
    role = "5g-core"
    lab  = "telecom-5g"
  }

  service_account {
    scopes = ["cloud-platform"]
  }
}

# ============================================
# UERANSIM VM
# t2d-standard-1 spot | 1 vCPU | 4GB | 10GB
# Runs: UERANSIM gNB + UE
# Access: gcloud compute ssh ueransim --zone=us-south1-a --tunnel-through-iap
# ============================================
resource "google_compute_instance" "ueransim" {
  name           = "ueransim"
  machine_type   = var.ueransim_machine_type
  zone           = var.gcp_zone
  can_ip_forward = true
  tags           = ["lab-vm"]

  scheduling {
    preemptible         = true
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    provisioning_model  = "SPOT"
  }

  boot_disk {
    initialize_params {
      image = var.ubuntu_image
      size  = var.ueransim_disk_size_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private_subnet.id
    network_ip = var.ueransim_ip
    # No public IP — SSH via IAP: gcloud compute ssh ueransim --tunnel-through-iap --zone=us-south1-a
  }

  metadata = {
    ssh-keys       = "${var.ssh_user}:${local.ssh_public_key}"
    startup-script = file("${path.module}/startup/startup-ueransim.sh")
    enable-oslogin = "FALSE"
    
  }

  labels = {
    role = "ueransim"
    lab  = "telecom-5g"
  }

  service_account {
    scopes = ["cloud-platform"]
  }
  
}
