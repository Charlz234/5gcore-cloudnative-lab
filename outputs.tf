# To be saved after Terraform Apply

# OCI Bastion
output "bastion_public_ip" {
  description = "OCI Bastion public IP — SSH from your laptop here"
  value       = oci_core_instance.bastion.public_ip
}

output "ssh_to_bastion" {
  description = "SSH command to connect to OCI bastion"
  value       = "ssh -i ~/.ssh/id_ed25519 ubuntu@${oci_core_instance.bastion.public_ip}"
}

# GCP VMs
output "core_5g_private_ip" {
  description = "GCP 5G core VM private IP"
  value       = google_compute_instance.core_5g.network_interface[0].network_ip
}

output "ueransim_private_ip" {
  description = "GCP UERANSIM VM private IP"
  value       = google_compute_instance.ueransim.network_interface[0].network_ip
}

# SSH via bastion jump host
output "ssh_to_core_via_bastion" {
  description = "SSH to 5G core via OCI bastion"
  value       = "ssh -J ubuntu@${oci_core_instance.bastion.public_ip} ubuntu@${google_compute_instance.core_5g.network_interface[0].network_ip}"
}

output "ssh_to_ueransim_via_bastion" {
  description = "SSH to UERANSIM via OCI bastion"
  value       = "ssh -J ubuntu@${oci_core_instance.bastion.public_ip} ubuntu@${google_compute_instance.ueransim.network_interface[0].network_ip}"
}

# WireGuard setup instructions
output "wireguard_setup_instructions" {
  description = "Steps to complete WireGuard setup after terraform apply"
  value       = <<-EOT

  === WireGuard Setup Steps ===

  1. SSH into OCI bastion:
     ssh -i ~/.ssh/id_ed25519 ubuntu@${oci_core_instance.bastion.public_ip}

  2. Get bastion WireGuard public key:
     cat /etc/wireguard/server_public.key

  3. SSH into core_5g via bastion and get its WireGuard public key:
     ssh -J ubuntu@${oci_core_instance.bastion.public_ip} ubuntu@${google_compute_instance.core_5g.network_interface[0].network_ip}
     cat /etc/wireguard/public.key

  4. SSH into ueransim via bastion and get its WireGuard public key:
     ssh -J ubuntu@${oci_core_instance.bastion.public_ip} ubuntu@${google_compute_instance.ueransim.network_interface[0].network_ip}
     cat /etc/wireguard/public.key

  5. Add peers to OCI bastion /etc/wireguard/wg0.conf

  6. Add OCI bastion as peer on each GCP VM

  7. Start WireGuard:
     sudo wg-quick up wg0

  EOT
}

# Scheduler info
output "scheduler_service_account" {
  description = "Cloud Scheduler service account email"
  value       = google_service_account.lab_scheduler_sa.email
}

# Cost reminder
output "estimated_monthly_cost" {
  description = "Estimated monthly cost at 6hrs/day"
  value       = <<-EOT

 === Estimated Monthly Cost ===
  OCI Bastion (free)               $0.00
  core-5g t2d-standard-4 spot      $3.60
  ueransim t2d-standard-2 spot     $1.80
  core-5g disk 50GB pd-standard    $2.00
  ueransim disk 30GB pd-standard   $1.20
  Cloud Scheduler                  $0.00
  --------------------------------
  Total                            ~$8.60/month

  Set a GCP billing alert at $15/month as safety net.

  EOT
}
