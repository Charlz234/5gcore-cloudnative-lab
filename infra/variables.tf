# ============================================
# GCP Variables
# ============================================

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP Region"
  type        = string
  default     = "us-south1"
}

variable "gcp_zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-south1-a"
}

variable "ssh_user" {
  description = "SSH username for GCP VMs"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "core_machine_type" {
  description = "Machine type for 5G core VM"
  type        = string
  default     = "t2d-standard-2"
}

variable "ueransim_machine_type" {
  description = "Machine type for UERANSIM VM"
  type        = string
  default     = "t2d-standard-1"
}

variable "core_disk_size_gb" {
  description = "Boot disk size for 5G core VM in GB"
  type        = number
  default     = 30
}

variable "ueransim_disk_size_gb" {
  description = "Boot disk size for UERANSIM VM in GB"
  type        = number
  default     = 10
}

variable "ubuntu_image" {
  description = "Ubuntu 22.04 LTS image"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}

variable "core_5g_ip" {
  description = "Fixed internal IP for core-5g VM"
  type        = string
  default     = "10.0.2.3"
}

variable "ueransim_ip" {
  description = "Fixed internal IP for ueransim VM"
  type        = string
  default     = "10.0.2.2"
}

variable "core_startup_script" {
  description = "Startup script for core-5g VM"
  type        = string
  default     = "startup/startup-core.sh"
}

variable "grafana_admin_password" {
  description = "Grafana admin password — stored in terraform.tfvars only, never committed"
  type        = string
  sensitive   = true
}