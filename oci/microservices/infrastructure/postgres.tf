resource "random_password" "postgres" {
  length           = 24
  special          = true
  override_special = "#_"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "oci_psql_db_system" "this" {
  compartment_id              = local.compartment_id
  display_name                = "${var.cluster_name}-postgresql"
  db_version                  = var.postgres_version
  shape                       = "PostgreSQL.VM.Standard.E5.Flex"
  instance_ocpu_count         = var.postgres_ocpus
  instance_memory_size_in_gbs = var.postgres_memory_gb
  instance_count              = var.postgres_instance_count

  network_details {
    subnet_id = oci_core_subnet.this["db"].id
  }

  # Storage grows automatically. Regional durability needs more than one availability domain.
  storage_details {
    system_type           = "OCI_OPTIMIZED_STORAGE"
    is_regionally_durable = local.multi_ad
    availability_domain   = local.multi_ad ? null : local.ads[0]
  }

  credentials {
    username = var.postgres_username
    password_details {
      password_type = "PLAIN_TEXT"
      password      = random_password.postgres.result
    }
  }

  management_policy {
    maintenance_window_start = "SUN 04:00"

    backup_policy {
      kind           = "DAILY"
      backup_start   = "03:00"
      retention_days = 7
    }

    pitr_policy {
      kind         = "STANDARD"
      restore_days = 7
    }
  }
}

# Read by External Secrets Operator. The service creates only the `postgres` database;
# k8s-install-tb.sh creates `thingsboard`.
resource "oci_vault_secret" "postgres" {
  compartment_id = local.compartment_id
  vault_id       = oci_kms_vault.this.id
  key_id         = oci_kms_key.secrets.id
  secret_name    = "postgres"
  description    = "PostgreSQL connection for ${var.cluster_name}"

  secret_content {
    content_type = "BASE64"
    content = base64encode(jsonencode({
      PGHOST     = oci_psql_db_system.this.network_details[0].primary_db_endpoint_private_ip
      PGPORT     = "5432"
      PGDATABASE = "thingsboard"
      PGUSER     = var.postgres_username
      PGPASSWORD = random_password.postgres.result
    }))
  }
}
