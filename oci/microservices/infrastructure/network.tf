data "oci_identity_availability_domains" "this" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

locals {
  vcn_cidr        = "10.0.0.0/16"
  oracle_services = data.oci_core_services.all.services[0]

  subnets = {
    api     = { cidr = "10.0.0.0/28", public = true }
    workers = { cidr = "10.0.16.0/20", public = false }
    lb      = { cidr = "10.0.32.0/24", public = true }
    db      = { cidr = "10.0.48.0/24", public = false }
  }

  # [min, max] per rule, matching the listeners in gateway/gateway.yml and gateway/https.yml
  lb_listener_ports = {
    tcp = [[80, 80], [443, 443], [1883, 1883], [7070, 7070], [8883, 8883]]
    udp = [[5683, 5688]]
  }
}

resource "oci_core_vcn" "this" {
  compartment_id = local.compartment_id
  display_name   = "${var.cluster_name}-vcn"
  cidr_blocks    = [local.vcn_cidr]
  dns_label      = "vcn${substr(join("", regexall("[a-z0-9]", var.cluster_name)), 0, 12)}"
}

# Unused by every subnet; managing it removes its default SSH-from-anywhere rule.
resource "oci_core_default_security_list" "this" {
  manage_default_resource_id = oci_core_vcn.this.default_security_list_id
  display_name               = "${var.cluster_name}-default"
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-igw"
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-nat"
}

resource "oci_core_service_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-sgw"

  services {
    service_id = local.oracle_services.id
  }
}

resource "oci_core_route_table" "public" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-private"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }

  route_rules {
    destination       = local.oracle_services.cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this.id
  }
}

resource "oci_core_security_list" "api" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-api"

  dynamic "ingress_security_rules" {
    for_each = var.api_allowed_cidrs
    content {
      protocol = "6"
      source   = ingress_security_rules.value
      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }

  ingress_security_rules {
    protocol = "all"
    source   = local.vcn_cidr
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# The VCN-wide rule covers the OKE worker, API and load balancer traffic.
# In-VCN and NodePort rules are stateless: stateful rules track every flow in a per-node table
# (VM.Standard.E5.Flex: 18,000 flows per OCPU) that drops new connections once full.
resource "oci_core_security_list" "workers" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-workers"

  ingress_security_rules {
    protocol  = "all"
    source    = local.vcn_cidr
    stateless = true
  }

  ingress_security_rules {
    description = "Path MTU discovery"
    protocol    = "1"
    source      = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }

  # The network load balancer preserves client addresses, so NodePort traffic arrives from the internet.
  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = true
    tcp_options {
      min = 30000
      max = 32767
    }
  }

  ingress_security_rules {
    protocol  = "17"
    source    = "0.0.0.0/0"
    stateless = true
    udp_options {
      min = 30000
      max = 32767
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = local.vcn_cidr
    stateless   = true
  }

  # NodePort replies; stateless rules take precedence over the stateful rule below.
  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
    stateless   = true
    tcp_options {
      source_port_range {
        min = 30000
        max = 32767
      }
    }
  }

  egress_security_rules {
    protocol    = "17"
    destination = "0.0.0.0/0"
    stateless   = true
    udp_options {
      source_port_range {
        min = 30000
        max = 32767
      }
    }
  }

  # Stateful: replies from the internet and Oracle services need tracking.
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# The load balancer is created with security-list management disabled, so these rules alone decide what it accepts.
resource "oci_core_security_list" "lb" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-lb"

  dynamic "ingress_security_rules" {
    for_each = local.lb_listener_ports.tcp
    content {
      protocol = "6"
      source   = "0.0.0.0/0"
      tcp_options {
        min = ingress_security_rules.value[0]
        max = ingress_security_rules.value[1]
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = local.lb_listener_ports.udp
    content {
      protocol = "17"
      source   = "0.0.0.0/0"
      udp_options {
        min = ingress_security_rules.value[0]
        max = ingress_security_rules.value[1]
      }
    }
  }

  ingress_security_rules {
    description = "Path MTU discovery"
    protocol    = "1"
    source      = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = local.vcn_cidr
  }
}

# PostgreSQL from the worker nodes only; pod traffic leaves the node with the node's address.
resource "oci_core_security_list" "db" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-db"

  ingress_security_rules {
    protocol = "6"
    source   = local.subnets.workers.cidr
    tcp_options {
      min = 5432
      max = 5432
    }
  }

  ingress_security_rules {
    description = "Path MTU discovery"
    protocol    = "1"
    source      = local.vcn_cidr
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "this" {
  for_each = local.subnets

  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${var.cluster_name}-${each.key}"
  cidr_block                 = each.value.cidr
  dns_label                  = each.key
  prohibit_public_ip_on_vnic = !each.value.public
  route_table_id             = each.value.public ? oci_core_route_table.public.id : oci_core_route_table.private.id
  security_list_ids = [{
    api     = oci_core_security_list.api.id
    workers = oci_core_security_list.workers.id
    lb      = oci_core_security_list.lb.id
    db      = oci_core_security_list.db.id
  }[each.key]]
}

# One regional network load balancer fronts the cluster, so a single reserved address serves every protocol.
# It must be in the cluster's compartment for OKE to attach it.
resource "oci_core_public_ip" "ingress" {
  compartment_id = local.compartment_id
  display_name   = "${var.cluster_name}-ingress"
  lifetime       = "RESERVED"

  # Attached to the load balancer by OKE, not by Terraform.
  lifecycle {
    ignore_changes = [private_ip_id]
  }
}
