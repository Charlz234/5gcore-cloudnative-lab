# ============================================
# OCI Infrastructure
# Free AMD bastion — WireGuard server
# ============================================

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.oci_tenancy_ocid
}

locals {
  oci_ad = var.oci_availability_domain
}

# VCN
resource "oci_core_vcn" "bastion_vcn" {
  compartment_id = var.oci_compartment_ocid
  cidr_block     = "172.16.0.0/24"
  display_name   = "telecom-bastion-vcn"
  dns_label      = "bastionvcn"
}

# Internet Gateway
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.bastion_vcn.id
  display_name   = "bastion-igw"
  enabled        = true
}

# Route Table
resource "oci_core_route_table" "bastion_rt" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.bastion_vcn.id
  display_name   = "bastion-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# Security List — allow SSH and WireGuard
resource "oci_core_security_list" "bastion_sl" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.bastion_vcn.id
  display_name   = "bastion-security-list"

  # SSH from anywhere — your laptop connects here
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
    description = "SSH from laptop"
  }

  # WireGuard UDP — GCP VMs connect back to bastion
  ingress_security_rules {
    protocol = "17"
    source   = "0.0.0.0/0"
    udp_options {
      min = var.wireguard_port
      max = var.wireguard_port
    }
    description = "WireGuard tunnel from GCP VMs"
  }

  # Allow all outbound
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# Public Subnet
resource "oci_core_subnet" "bastion_subnet" {
  compartment_id    = var.oci_compartment_ocid
  vcn_id            = oci_core_vcn.bastion_vcn.id
  cidr_block        = "172.16.0.0/24"
  display_name      = "bastion-subnet"
  dns_label         = "bastionsubnet"
  route_table_id    = oci_core_route_table.bastion_rt.id
  security_list_ids = [oci_core_security_list.bastion_sl.id]
}

# OCI Free AMD VM — WireGuard Server + SSH Bastion
resource "oci_core_instance" "bastion" {
  compartment_id      = var.oci_compartment_ocid
  availability_domain = local.oci_ad
  display_name        = "telecom-bastion"
  shape               = "VM.Standard.E2.1.Micro"

  source_details {
    source_type = "image"
    source_id   = var.oci_ubuntu_image_ocid
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.bastion_subnet.id
    display_name     = "bastion-vnic"
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.oci_ssh_public_key
    user_data = base64encode(<<-EOF
      #!/bin/bash
      set -e
      exec > /var/log/startup-script.log 2>&1

      echo "=== Starting OCI Bastion setup ==="

      apt-get update -y
      apt-get install -y \
        wireguard \
        wireguard-tools \
        curl \
        wget \
        jq \
        net-tools \
        iproute2 \
        iptables

      # Install gcloud CLI for managing GCP VMs
      curl https://sdk.cloud.google.com | bash -s -- \
        --disable-prompts \
        --install-dir=/home/ubuntu
      echo 'export PATH=$PATH:/home/ubuntu/google-cloud-sdk/bin' >> /home/ubuntu/.bashrc

      # Enable IP forwarding — required for WireGuard routing
      echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
      sysctl -p

      # Generate WireGuard server keys
      wg genkey | tee /etc/wireguard/server_private.key | \
        wg pubkey > /etc/wireguard/server_public.key
      chmod 600 /etc/wireguard/server_private.key

      SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
      SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)

      echo "OCI Bastion WireGuard public key: $SERVER_PUBLIC_KEY" \
        >> /home/ubuntu/wireguard-keys.txt

      # Create WireGuard config — peers added manually after GCP VMs are up
      cat > /etc/wireguard/wg0.conf << WGEOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = 10.10.0.1/24
ListenPort = ${var.wireguard_port}
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE

# GCP 5g-core — add public key after GCP VM boots
# [Peer]
# PublicKey = <5g-core-wg-public-key>
# AllowedIPs = 10.10.0.3/32

# GCP ueransim — add public key after GCP VM boots
# [Peer]
# PublicKey = <ueransim-wg-public-key>
# AllowedIPs = 10.10.0.4/32
WGEOF

      chmod 600 /etc/wireguard/wg0.conf
      chown ubuntu:ubuntu /home/ubuntu/wireguard-keys.txt

      # Copy lab control scripts placeholder
      mkdir -p /home/ubuntu/scripts
      chown -R ubuntu:ubuntu /home/ubuntu/scripts

      echo "=== OCI Bastion setup complete ===" >> /home/ubuntu/ready.txt
      chown ubuntu:ubuntu /home/ubuntu/ready.txt
    EOF
    )
  }

  freeform_tags = {
    "role" = "wireguard-bastion"
    "lab"  = "telecom-5g"
  }
}
