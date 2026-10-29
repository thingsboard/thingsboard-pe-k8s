variable "region" {
  description = "OCI region identifier, e.g. eu-frankfurt-1"
  type        = string
}

variable "tenancy_ocid" {
  description = "Tenancy OCID"
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment for all resources. Empty means the tenancy root compartment."
  type        = string
  default     = ""
}

variable "config_file_profile" {
  description = "Profile in ~/.oci/config"
  type        = string
  default     = "DEFAULT"
}

variable "auth" {
  description = "OCI provider authentication: APIKey or SecurityToken (oci session authenticate)"
  type        = string
  default     = "APIKey"

  validation {
    condition     = contains(["APIKey", "SecurityToken"], var.auth)
    error_message = "auth must be APIKey or SecurityToken."
  }
}

variable "cluster_name" {
  description = "Prefix for every resource name"
  type        = string
  default     = "thingsboard"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,29}$", var.cluster_name))
    error_message = "cluster_name must start with a letter and contain only lowercase letters, digits and hyphens (max 30)."
  }
}

variable "kubernetes_version" {
  description = "Exact OKE version for the control plane and node pools, e.g. v1.36.4"
  type        = string
}

variable "api_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the Kubernetes API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tb_node_pool" {
  description = "Node pool for ThingsBoard services, Kafka, ZooKeeper and Valkey"
  type = object({
    shape          = optional(string, "VM.Standard.E5.Flex")
    ocpus          = optional(number, 2)
    memory_gb      = optional(number, 16)
    size           = optional(number, 3)
    boot_volume_gb = optional(number, 50)
  })
  default = {}
}

variable "cassandra_enabled" {
  description = "Create three Cassandra node pools, one per availability or fault domain"
  type        = bool
  default     = false
}

variable "cassandra_node_pool" {
  description = "Shape of each Cassandra node"
  type = object({
    shape          = optional(string, "VM.Standard.E5.Flex")
    ocpus          = optional(number, 2)
    memory_gb      = optional(number, 16)
    boot_volume_gb = optional(number, 50)
  })
  default = {}
}

variable "cassandra_backups_enabled" {
  description = "Create an Object Storage bucket and credentials for Cassandra backups (Medusa)"
  type        = bool
  default     = true
}

variable "service_user_email_domain" {
  description = "Email domain for the backup service user; identity domains require an email on every user. Nothing is sent to it."
  type        = string
  default     = ""
}

variable "trendz_enabled" {
  description = "Create a node pool for Trendz Analytics"
  type        = bool
  default     = false
}

variable "trendz_node_pool" {
  description = "Shape of the Trendz node"
  type = object({
    shape          = optional(string, "VM.Standard.E5.Flex")
    ocpus          = optional(number, 2)
    memory_gb      = optional(number, 16)
    boot_volume_gb = optional(number, 50)
  })
  default = {}
}

variable "postgres_version" {
  description = "PostgreSQL major version. Changing it replaces the database system and deletes its data."
  type        = string
  default     = "18"
}

variable "postgres_username" {
  description = "PostgreSQL administrator name. The service reserves `postgres`, and this admin is not a superuser."
  type        = string
  default     = "admin"
}

variable "postgres_ocpus" {
  description = "OCPUs per PostgreSQL node (1 OCPU = 2 vCPUs)"
  type        = number
  default     = 1
}

variable "postgres_memory_gb" {
  description = "Memory per PostgreSQL node in GB (minimum 16)"
  type        = number
  default     = 16
}

variable "postgres_instance_count" {
  description = "PostgreSQL nodes; 2 or more adds a standby that takes over on failure"
  type        = number
  default     = 2
}

locals {
  compartment_id = var.compartment_ocid != "" ? var.compartment_ocid : var.tenancy_ocid
  policy_scope   = local.compartment_id == var.tenancy_ocid ? "in tenancy" : "in compartment id ${local.compartment_id}"

  ads      = data.oci_identity_availability_domains.this.availability_domains[*].name
  multi_ad = length(local.ads) > 1

  backups_enabled = var.cassandra_enabled && var.cassandra_backups_enabled
}
