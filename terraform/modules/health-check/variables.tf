# modules/health-check/variables.tf
# Regional HTTP health check, used by BOTH the backend service and the MIG
# autohealing policy.

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the regional health check."
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

variable "name_suffix" {
  description = "Suffix to distinguish this health check (e.g. mig-hc, lb-hc) so multiple can coexist."
  type        = string
  default     = "hc"
}

variable "app_port" {
  description = "Application port the health check probes."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path to probe (the app exposes /health)."
  type        = string
  default     = "/health"
}

variable "check_interval_sec" {
  description = "Seconds between probes."
  type        = number
  default     = 10
}

variable "timeout_sec" {
  description = "Probe timeout in seconds."
  type        = number
  default     = 5
}

variable "healthy_threshold" {
  description = "Consecutive successes before marking healthy."
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Consecutive failures before marking unhealthy."
  type        = number
  default     = 3
}
