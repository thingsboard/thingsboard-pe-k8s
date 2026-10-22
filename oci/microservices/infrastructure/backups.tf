# Cassandra backups (Medusa) use the S3-compatible Object Storage API, which authenticates with a
# Customer Secret Key, so they need a dedicated user limited to one bucket.
data "oci_objectstorage_namespace" "this" {
  compartment_id = var.tenancy_ocid
}

locals {
  backup_bucket = "${var.cluster_name}-cassandra-backups"
  medusa_host   = "${data.oci_objectstorage_namespace.this.namespace}.compat.objectstorage.${var.region}.oraclecloud.com"
}

resource "oci_objectstorage_bucket" "cassandra_backups" {
  count = local.backups_enabled ? 1 : 0

  compartment_id = local.compartment_id
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = local.backup_bucket
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
}

resource "oci_identity_user" "cassandra_backups" {
  count = local.backups_enabled ? 1 : 0

  compartment_id = var.tenancy_ocid
  name           = local.backup_bucket
  description    = "Writes Cassandra backups to ${local.backup_bucket}"
  email          = "${local.backup_bucket}@${var.service_user_email_domain}"

  lifecycle {
    precondition {
      condition     = var.service_user_email_domain != ""
      error_message = "Set service_user_email_domain, or cassandra_backups_enabled = false."
    }
  }
}

# New users can use every credential type, including a console password; keep only Customer Secret Keys.
resource "oci_identity_user_capabilities_management" "cassandra_backups" {
  count = local.backups_enabled ? 1 : 0

  user_id                      = oci_identity_user.cassandra_backups[0].id
  can_use_api_keys             = false
  can_use_auth_tokens          = false
  can_use_console_password     = false
  can_use_customer_secret_keys = true
  can_use_smtp_credentials     = false
}

resource "oci_identity_group" "cassandra_backups" {
  count = local.backups_enabled ? 1 : 0

  compartment_id = var.tenancy_ocid
  name           = local.backup_bucket
  description    = "Writes Cassandra backups to ${local.backup_bucket}"
}

resource "oci_identity_user_group_membership" "cassandra_backups" {
  count = local.backups_enabled ? 1 : 0

  user_id  = oci_identity_user.cassandra_backups[0].id
  group_id = oci_identity_group.cassandra_backups[0].id
}

resource "oci_identity_policy" "cassandra_backups" {
  count = local.backups_enabled ? 1 : 0

  compartment_id = local.compartment_id
  name           = local.backup_bucket
  description    = "Object read/write on ${local.backup_bucket}"
  statements = [
    "Allow group ${oci_identity_group.cassandra_backups[0].name} to read buckets ${local.policy_scope} where target.bucket.name = '${local.backup_bucket}'",
    "Allow group ${oci_identity_group.cassandra_backups[0].name} to manage objects ${local.policy_scope} where target.bucket.name = '${local.backup_bucket}'",
  ]
}

resource "oci_identity_customer_secret_key" "cassandra_backups" {
  count = local.backups_enabled ? 1 : 0

  user_id      = oci_identity_user.cassandra_backups[0].id
  display_name = "medusa"

  depends_on = [oci_identity_user_capabilities_management.cassandra_backups]
}

resource "oci_vault_secret" "cassandra_backups" {
  count = local.backups_enabled ? 1 : 0

  compartment_id = local.compartment_id
  vault_id       = oci_kms_vault.this.id
  key_id         = oci_kms_key.secrets.id
  secret_name    = "cassandra-backups"
  description    = "S3-compatible credentials for ${local.backup_bucket}"

  secret_content {
    content_type = "BASE64"
    content = base64encode(jsonencode({
      access-key-id     = oci_identity_customer_secret_key.cassandra_backups[0].id
      secret-access-key = oci_identity_customer_secret_key.cassandra_backups[0].key
    }))
  }
}
