# ============================================
# Outputs
# ============================================

output "core_5g_private_ip" {
  description = "5G core VM private IP"
  value       = google_compute_instance.core_5g.network_interface[0].network_ip
}

output "ueransim_private_ip" {
  description = "UERANSIM VM private IP"
  value       = google_compute_instance.ueransim.network_interface[0].network_ip
}

output "ssh_to_core" {
  description = "Access instructions for the 5G Core via IAP"
  value       = <<-EOT
    Command: gcloud compute ssh ubuntu@core-5g --zone=${var.gcp_zone} --tunnel-through-iap
    Note:    Once connected, run 'tail -f /var/log/startup-script.log' to monitor setup.
  EOT
}

output "ssh_to_ueransim" {
  description = "SSH to UERANSIM via IAP"
  value       = "gcloud compute ssh ubuntu@ueransim --zone=${var.gcp_zone} --tunnel-through-iap"
}


output "estimated_monthly_cost" {
  description = "Estimated monthly cost"
  value       = <<-EOT
  === Estimated Monthly Cost      ===
  core-5g  t2d-standard-2 spot    ~$6.55
  ueransim t2d-standard-1 spot    ~$3.27
  core-5g  disk 30GB pd-standard   $3.60
  ueransim disk 10GB pd-standard   $1.20
  Cloud NAT                       ~$7.00(depends on traffic through UPF, e.t.c)
  ─────────────────────────────────────────
  Total                          ~$22/month
  Set a GCP billing alert at $25/month.
  EOT
}
