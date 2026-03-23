# ============================================
# GCP Variables
# ============================================

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP Region — one og the cheapest for t2d spot"
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
  default     = "t2d-standard-4"
}

variable "ueransim_machine_type" {
  description = "Machine type for UERANSIM VM"
  type        = string
  default     = "t2d-standard-2"
}

variable "core_disk_size_gb" {
  description = "Boot disk size for 5G core VM in GB"
  type        = number
  default     = 50
}

variable "ueransim_disk_size_gb" {
  description = "Boot disk size for UERANSIM VM in GB"
  type        = number
  default     = 30
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

# ============================================
# OCI Variables
# ============================================

variable "oci_tenancy_ocid" {
  description = "OCI Tenancy OCID"
  type        = string
}

variable "oci_user_ocid" {
  description = "OCI User OCID"
  type        = string
}

variable "oci_fingerprint" {
  description = "OCI API Key Fingerprint"
  type        = string
}

variable "oci_private_key_path" {
  description = "Path to OCI API private key"
  type        = string
  default     = "/.oci/oci_api_key.pem"
}

variable "oci_region" {
  description = "OCI Region"
  type        = string
  default     = "us-ashburn-1"
}

variable "oci_compartment_ocid" {
  description = "OCI Compartment OCID"
  type        = string
}

variable "oci_ubuntu_image_ocid" {
  description = "Ubuntu 22.04 image OCID for your OCI region"
  type        = string
}

variable "oci_ssh_public_key" {
  description = "SSH public key for OCI VM"
  type        = string
}

variable "oci_availability_domain" {
  description = "OCI Availability Domain for bastion VM — free tier only in AD-2 as at Feb 2026"
  type        = string
  default     = "DRxg:US-ASHBURN-AD-2"
}

# ============================================
# WireGuard Variables
# ============================================

variable "wireguard_port" {
  description = "WireGuard UDP listen port"
  type        = number
  default     = 51820
}
