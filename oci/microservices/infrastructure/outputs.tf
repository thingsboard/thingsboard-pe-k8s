output "cluster_id" {
  description = "OKE cluster OCID"
  value       = oci_containerengine_cluster.this.id
}

output "region" {
  description = "OCI region"
  value       = var.region
}

output "compartment_id" {
  description = "Compartment holding every resource"
  value       = local.compartment_id
}

output "ingress_ip_address" {
  description = "Reserved public address of the gateway load balancer"
  value       = oci_core_public_ip.ingress.ip_address
}

output "vault_id" {
  description = "Vault read by External Secrets Operator"
  value       = oci_kms_vault.this.id
}

output "vault_key_id" {
  description = "Key to create new vault secrets with"
  value       = oci_kms_key.secrets.id
}

output "postgres_db_system_id" {
  description = "PostgreSQL database system OCID"
  value       = oci_psql_db_system.this.id
}

output "cassandra_backup_bucket" {
  description = "Bucket for Cassandra backups"
  value       = local.backups_enabled ? local.backup_bucket : null
}

output "medusa_host" {
  description = "S3-compatible Object Storage endpoint for Medusa"
  value       = local.backups_enabled ? local.medusa_host : null
}
