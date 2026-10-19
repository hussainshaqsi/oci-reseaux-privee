# Finds the latest Ubuntu 22.04 image Oracle has for the AMD shape/region —
# avoids hardcoding an image ID that'll go stale
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order                = "DESC"
}

# ARM-compatible Ubuntu 22.04 image, for the private host using your spare ARM quota
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order                = "DESC"
}

# Oracle requires you to say which physical Availability Domain to launch into
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# The bastion - public subnet, gets a public IP - still AMD E2.1.Micro
resource "oci_core_instance" "bastion" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape                = "VM.Standard.E2.1.Micro"
  display_name         = "bastion"

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand("~/.ssh/oci_private_network_key.pub"))
  }
}

# The private host - private subnet, physically cannot get a public IP - now ARM
resource "oci_core_instance" "private_host" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape                = "VM.Standard.A1.Flex"
  display_name         = "private-host"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = false
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu_arm.images[0].id
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand("~/.ssh/oci_private_network_key.pub"))
  }
}

# Print the IPs after creation so we don't have to dig for them in the console
output "bastion_public_ip" {
  value = oci_core_instance.bastion.public_ip
}

output "bastion_private_ip" {
  value = oci_core_instance.bastion.private_ip
}

output "private_host_ip" {
  value = oci_core_instance.private_host.private_ip
}