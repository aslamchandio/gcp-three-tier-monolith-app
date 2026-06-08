# modules/instance-template/variables.tf
# Instance template for the application tier. Instances have NO external IP and
# reach the internet via Cloud NAT; they run as the supplied service account.

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the regional instance template."
  type        = string
}

variable "app_name" {
  description = "Application/project short name; part of the naming prefix."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev/stage/prod); part of the naming prefix."
  type        = string
}

variable "machine_type" {
  description = "Compute Engine machine type."
  type        = string
  default     = "e2-medium"
}

variable "source_image" {
  description = "Boot disk image (family or specific image)."
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB."
  type        = number
  default     = 20
}

variable "disk_type" {
  description = "Boot disk type (pd-standard, pd-balanced, pd-ssd)."
  type        = string
  default     = "pd-balanced"
}

variable "network" {
  description = "VPC self link or ID for the network interface."
  type        = string
}

variable "subnetwork" {
  description = "Subnet self link or ID the instances attach to."
  type        = string
}

variable "service_account_email" {
  description = "Service account email the instances run as."
  type        = string
}

variable "service_account_scopes" {
  description = "OAuth scopes. cloud-platform is recommended; actual access is controlled by IAM roles."
  type        = list(string)
  default     = ["https://www.googleapis.com/auth/cloud-platform"]
}

variable "network_tags" {
  description = "Network tags applied to instances (must include the firewall app tag)."
  type        = list(string)
  default     = []
}

variable "startup_script" {
  description = "Startup script contents (e.g. file(\"../../../ecommerce-app/deploy/startup.sh\"))."
  type        = string
  default     = ""
}

variable "metadata" {
  description = "Additional instance metadata (e.g. db_host, db_name, db_password_secret_id consumed by the startup script)."
  type        = map(string)
  default     = {}
}

variable "enable_shielded_vm" {
  description = "Enable Shielded VM (secure boot, vTPM, integrity monitoring)."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels applied to the template and instances."
  type        = map(string)
  default     = {}
}
