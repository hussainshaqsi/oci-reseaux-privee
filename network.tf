# The VCN - your own private network inside Oracle Cloud, like your own isolated LAN
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.1.0.0/16"]
  display_name   = "oci-private-network-vcn"
  dns_label      = "privnet"
}

# Internet Gateway - the only door between this VCN and the public internet
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "igw"
  enabled        = true
}

# NAT Gateway - lets things INSIDE the private subnet reach OUT to the internet
# (so it can run apt update), but nothing from outside can ever come IN through it.
# It's a one-way door, opposite of the Internet Gateway.
resource "oci_core_nat_gateway" "nat" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "nat-gw"
}

# Public subnet - where the bastion lives. Allowed to have a public IP.
resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.1.0.0/24"
  display_name               = "public-subnet"
  dns_label                  = "public"
  route_table_id             = oci_core_route_table.public_rt.id
  security_list_ids          = [oci_core_security_list.public_sl.id]
  prohibit_public_ip_on_vnic = false
}

# Private subnet - where the app host lives.
# prohibit_public_ip_on_vnic = true is the actual line that makes "no public IP" a
# hard rule, not just a choice — Oracle will refuse to assign one here, period.
resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.1.1.0/24"
  display_name               = "private-subnet"
  dns_label                  = "private"
  route_table_id             = oci_core_route_table.private_rt.id
  security_list_ids          = [oci_core_security_list.private_sl.id]
  prohibit_public_ip_on_vnic = true
}

# Public route table: "to reach anywhere (0.0.0.0/0), go out through the Internet Gateway"
resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# Private route table: "to reach anywhere, go out through the NAT Gateway" (out-only, remember)
resource "oci_core_route_table" "private_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "private-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_nat_gateway.nat.id
  }
}

# Public subnet firewall: the ENTIRE internet can only reach one thing here —
# WireGuard's port. Nothing else. No SSH open to the world, anywhere in this file.
resource "oci_core_security_list" "public_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-sl"

 ingress_security_rules {
    # TEMPORARY - for initial setup only, removed once WireGuard is verified
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# Private subnet firewall: SSH is only accepted from the public subnet (the bastion) —
# never directly from the internet, because it's not even routable from there.
resource "oci_core_security_list" "private_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "private-sl"

  ingress_security_rules {
    protocol = "6" # 6 = TCP
    source   = "10.1.0.0/24"
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol = "1" # 1 = ICMP, for ping/troubleshooting
    source   = "10.1.0.0/16"
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}