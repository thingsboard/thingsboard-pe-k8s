resource "oci_kms_vault" "this" {
  compartment_id = local.compartment_id
  display_name   = "${var.cluster_name}-vault"
  vault_type     = "DEFAULT"
}

# Encrypts the secrets stored in the vault.
resource "oci_kms_key" "secrets" {
  compartment_id      = local.compartment_id
  display_name        = "${var.cluster_name}-secrets"
  management_endpoint = oci_kms_vault.this.management_endpoint
  protection_mode     = "SOFTWARE"

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

# Encrypts Kubernetes secrets in etcd. OKE cannot change it after the cluster is created.
resource "oci_kms_key" "oke" {
  compartment_id      = local.compartment_id
  display_name        = "${var.cluster_name}-oke"
  management_endpoint = oci_kms_vault.this.management_endpoint
  protection_mode     = "SOFTWARE"

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

# External Secrets Operator reads the vault through OKE Workload Identity: no keys are stored in the cluster.
locals {
  external_secrets_workload = join(", ", [
    "request.principal.type = 'workload'",
    "request.principal.namespace = 'external-secrets'",
    "request.principal.service_account = 'external-secrets'",
    "request.principal.cluster_id = '${oci_containerengine_cluster.this.id}'",
  ])
}

resource "oci_identity_policy" "external_secrets" {
  compartment_id = local.compartment_id
  name           = "${var.cluster_name}-external-secrets"
  description    = "External Secrets Operator in ${var.cluster_name} reads the ${var.cluster_name}-vault secrets"
  statements = [
    "Allow any-user to read secret-family ${local.policy_scope} where ALL {${local.external_secrets_workload}, target.vault.id = '${oci_kms_vault.this.id}'}",
    # The store validation reads the vault itself, which secret-family does not cover.
    "Allow any-user to read vaults ${local.policy_scope} where ALL {${local.external_secrets_workload}, target.vault.id = '${oci_kms_vault.this.id}'}",
  ]
}
