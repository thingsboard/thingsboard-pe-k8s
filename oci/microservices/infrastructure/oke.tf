# Needed when the cluster is created (kms_key_id), so it is scoped by key rather than by cluster.
resource "oci_identity_policy" "cluster" {
  compartment_id = local.compartment_id
  name           = "${var.cluster_name}-oke"
  description    = "OKE access to the ${var.cluster_name}-oke key"
  statements = [
    "Allow any-user to use keys ${local.policy_scope} where ALL {request.principal.type = 'cluster', target.key.id = '${oci_kms_key.oke.id}'}",
  ]
}

resource "oci_containerengine_cluster" "this" {
  compartment_id     = local.compartment_id
  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vcn_id             = oci_core_vcn.this.id
  # Workload Identity requires an enhanced cluster.
  type       = "ENHANCED_CLUSTER"
  kms_key_id = oci_kms_key.oke.id

  # VCN-native pod networking limits a 2-OCPU node to 31 pods.
  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  endpoint_config {
    subnet_id            = oci_core_subnet.this["api"].id
    is_public_ip_enabled = true
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.this["lb"].id]

    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }

  depends_on = [oci_identity_policy.cluster]
}

data "oci_containerengine_node_pool_option" "all" {
  node_pool_option_id = "all"
  compartment_id      = local.compartment_id
}

locals {
  fault_domains = ["FAULT-DOMAIN-1", "FAULT-DOMAIN-2", "FAULT-DOMAIN-3"]

  # Every availability domain in multi-AD regions, otherwise the three fault domains of the only one.
  spread = local.multi_ad ? [
    for ad in local.ads : { ad = ad, fault_domains = tolist(null) }
    ] : [
    { ad = local.ads[0], fault_domains = local.fault_domains }
  ]

  # Cassandra rack i gets its own availability domain, or its own fault domain in single-AD regions.
  cassandra_racks = [
    for i in range(3) : local.multi_ad
    ? { ad = local.ads[i % length(local.ads)], fault_domains = tolist(null) }
    : { ad = local.ads[0], fault_domains = [local.fault_domains[i]] }
  ]

  node_pools = merge(
    {
      "tb-node" = merge(var.tb_node_pool, {
        placements = local.spread
        labels     = tomap({ role = "tb-node" })
      })
    },
    var.cassandra_enabled ? {
      for i in range(3) : "cassandra-${i + 1}" => merge(var.cassandra_node_pool, {
        size       = 1
        placements = [local.cassandra_racks[i]]
        labels     = tomap({ role = "cassandra", "cassandra-rack" = "r${i + 1}" })
      })
    } : {},
    var.trendz_enabled ? {
      trendz = merge(var.trendz_node_pool, {
        size       = 1
        placements = local.spread
        labels     = tomap({ role = "trendz" })
      })
    } : {},
  )

  node_k8s_version = replace(trimprefix(var.kubernetes_version, "v"), ".", "\\.")

  # Newest OKE image per architecture, keyed by Oracle Linux major and zero-padded build so OL9 wins.
  # OL8 is the fallback for versions OKE lists no OL9 image for.
  node_images = {
    for arch, infix in { x86 = "", arm = "aarch64-" } : arch => {
      for s in data.oci_containerengine_node_pool_option.all.sources :
      "${regex("^Oracle-Linux-(\\d)", s.source_name)[0]}-${format("%010d", tonumber(regex("-(\\d+)$", s.source_name)[0]))}-${s.source_name}" => s.image_id
      if can(regex("^Oracle-Linux-[89]\\.\\d+-${infix}\\d{4}\\.\\d{2}\\.\\d{2}-\\d+-OKE-${local.node_k8s_version}-\\d+$", s.source_name))
    }
  }

  pool_arch = { for k, p in local.node_pools : k => can(regex("\\.A\\d+\\.", p.shape)) ? "arm" : "x86" }
}

# Pins the image a pool was created with, so a newly published OKE image does not replace every node
# on the next apply. Changing kubernetes_version (or the pool's architecture) picks the newest one again.
resource "terraform_data" "node_image" {
  for_each = local.node_pools

  input            = try(local.node_images[local.pool_arch[each.key]][reverse(sort(keys(local.node_images[local.pool_arch[each.key]])))[0]], null)
  triggers_replace = [var.kubernetes_version, local.pool_arch[each.key]]

  lifecycle {
    ignore_changes = [input]
  }
}

resource "oci_containerengine_node_pool" "this" {
  for_each = local.node_pools

  compartment_id     = local.compartment_id
  cluster_id         = oci_containerengine_cluster.this.id
  name               = each.key
  kubernetes_version = var.kubernetes_version
  node_shape         = each.value.shape

  node_shape_config {
    ocpus         = each.value.ocpus
    memory_in_gbs = each.value.memory_gb
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = terraform_data.node_image[each.key].output
    boot_volume_size_in_gbs = each.value.boot_volume_gb
  }

  node_config_details {
    size = each.value.size

    dynamic "placement_configs" {
      for_each = each.value.placements
      content {
        availability_domain = placement_configs.value.ad
        subnet_id           = oci_core_subnet.this["workers"].id
        fault_domains       = placement_configs.value.fault_domains
      }
    }
  }

  dynamic "initial_node_labels" {
    for_each = each.value.labels
    content {
      key   = initial_node_labels.key
      value = initial_node_labels.value
    }
  }

  # Instance metadata through IMDSv2 only.
  node_metadata = {
    areLegacyImdsEndpointsDisabled = "true"
  }

  # Replaces nodes one at a time, adding the new node before draining the old one.
  node_pool_cycling_details {
    is_node_cycling_enabled = true
    maximum_surge           = "1"
    maximum_unavailable     = "0"
  }

  lifecycle {
    precondition {
      condition     = terraform_data.node_image[each.key].output != null
      error_message = "No Oracle Linux 9 or 8 OKE ${local.pool_arch[each.key]} image found for ${var.kubernetes_version}."
    }
  }
}
