#
# Copyright © 2016-2026 The Thingsboard Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

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
