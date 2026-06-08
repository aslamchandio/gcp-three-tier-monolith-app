# modules/network/variables.tf
# Environment-agnostic inputs. The root configuration supplies environment-
# specific values; this module never hardcodes project, region, or environment.

variable "project_id" {
  description = "GCP project ID where the network resources are created."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources (subnet, Cloud Router, Cloud NAT)."
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

variable "network_name" {
  description = "Optional explicit VPC name. If empty, derived as <app_name>-<environment>-vpc."
  type        = string
  default     = ""
}

variable "app_network_tag" {
  description = "Optional explicit network tag for application instances. If empty, derived as <app_name>-<environment>-app."
  type        = string
  default     = ""
}

variable "app_subnet_cidr" {
  description = "Primary CIDR range for the application subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.app_subnet_cidr, 0))
    error_message = "app_subnet_cidr must be a valid IPv4 CIDR (e.g. 10.10.1.0/24)."
  }
}

variable "psa_address" {
  description = "Optional explicit start IP for the Private Services Access range (e.g. 10.77.0.0). If empty, GCP auto-allocates a block."
  type        = string
  default     = ""

  validation {
    condition     = var.psa_address == "" || can(cidrhost("${var.psa_address}/32", 0))
    error_message = "psa_address must be empty or a valid IPv4 address (e.g. 10.77.0.0)."
  }
}

variable "psa_prefix_length" {
  description = "Prefix length for the Private Services Access range reserved for Cloud SQL private IP."
  type        = number
  default     = 16

  validation {
    condition     = var.psa_prefix_length >= 16 && var.psa_prefix_length <= 24
    error_message = "psa_prefix_length must be between 16 and 24."
  }
}

variable "app_port" {
  description = "Internal application port the future backend instances listen on (also the health check port)."
  type        = number
  default     = 8080
}

variable "iap_source_range" {
  description = "Google Identity-Aware Proxy TCP forwarding source range for SSH."
  type        = string
  default     = "35.235.240.0/20"
}

variable "health_check_source_ranges" {
  description = "Google load balancer health check / proxy source ranges."
  type        = list(string)
  default     = ["35.191.0.0/16", "130.211.0.0/22"]
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs on the application subnet."
  type        = bool
  default     = true
}

variable "nat_log_filter" {
  description = "Cloud NAT logging filter: ERRORS_ONLY, TRANSLATIONS_ONLY, or ALL."
  type        = string
  default     = "ERRORS_ONLY"

  validation {
    condition     = contains(["ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"], var.nat_log_filter)
    error_message = "nat_log_filter must be one of: ERRORS_ONLY, TRANSLATIONS_ONLY, ALL."
  }
}
