# ============================================
# OCI Infrastructure
# Free AMD bastion — WireGuard server
# VM.Standard.E2.1.Micro — Always Free
# ============================================

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.oci_tenancy_ocid
}

# ---- VCN ----
resource "oci_core_vcn" "bastion_vcn" {
  compartment_id = var.oci_compartment_ocid
  cidr_block     = "172.16.0.0/24"
  display_name   = "telecom-bastion-vcn"
  dns_label      = "bastionvcn"
}

# ---- Internet Gateway ----
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.bastion_vcn.id
  display_name   = "bastion-igw"
  enabled        = true
}

# ---- Route Table ----
resource "oci_core_route_table" "bastion_rt" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.bastion_vcn.id
  display_name   = "bastion-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# ---- Security List ----
resource "oci_core_security_list" "bastion_sl" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.bastion_vcn.id
  display_name   = "bastion-security-list"

  # SSH from anywhere — laptop connects here
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    description = "SSH from laptop"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # WireGuard UDP — GCP VMs connect back to bastion
  ingress_security_rules {
    protocol    = "17"
    source      = "0.0.0.0/0"
    description = "WireGuard tunnel from GCP VMs"
    udp_options {
      min = var.wireguard_port
      max = var.wireguard_port
    }
  }

  # Allow all outbound
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# ---- Public Subnet ----
resource "oci_core_subnet" "bastion_subnet" {
  compartment_id    = var.oci_compartment_ocid
  vcn_id            = oci_core_vcn.bastion_vcn.id
  cidr_block        = "172.16.0.0/24"
  display_name      = "bastion-subnet"
  dns_label         = "bastionsubnet"
  route_table_id    = oci_core_route_table.bastion_rt.id
  security_list_ids = [oci_core_security_list.bastion_sl.id]
}

# ---- OCI Free AMD Bastion VM ----
resource "oci_core_instance" "bastion" {
  compartment_id      = var.oci_compartment_ocid
  availability_domain = var.oci_availability_domain
  display_name        = "telecom-bastion"
  shape               = "VM.Standard.E2.1.Micro"

  lifecycle {
    ignore_changes = [metadata] # Prevents recreation when OCI VM after metadata changes
  }


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
  Content-Type: text/x-shellscript; charset="us-ascii"
  MIME-Version: 1.0
  Content-Transfer-Encoding: 7bit

  ${templatefile("${path.module}/scripts/bastion-init.sh", {
    wireguard_port = var.wireguard_port
  })}
  EOF
)
  }

  freeform_tags = {
    "role" = "wireguard-bastion"
    "lab"  = "telecom-5g"
  }
}
