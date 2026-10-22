region       = "YOUR_OCI_REGION"
tenancy_ocid = "YOUR_TENANCY_OCID"
# Optional: a compartment for all resources; the tenancy root compartment is used when empty.
# compartment_ocid = "YOUR_COMPARTMENT_OCID"

# Profile in ~/.oci/config. Use auth = "SecurityToken" after `oci session authenticate`.
config_file_profile = "DEFAULT"
auth                = "APIKey"

cluster_name = "thingsboard"

# Exact version listed by: oci ce cluster-options get --cluster-option-id all
kubernetes_version = "v1.36.4"

# Restrict access to the Kubernetes API, e.g. ["203.0.113.0/24"]
api_allowed_cidrs = ["0.0.0.0/0"]

tb_node_pool = {
  shape     = "VM.Standard.E5.Flex"
  ocpus     = 2
  memory_gb = 16
  size      = 3
}

cassandra_enabled = false
cassandra_node_pool = {
  shape     = "VM.Standard.E5.Flex"
  ocpus     = 2
  memory_gb = 16
}

# With Cassandra: backups need an email domain for the service user (nothing is sent to it).
cassandra_backups_enabled = true
service_user_email_domain = ""

trendz_enabled = false

postgres_version        = "18"
postgres_ocpus          = 1
postgres_memory_gb      = 16
postgres_instance_count = 2
