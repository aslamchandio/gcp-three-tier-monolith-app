# modules/managed-instance-group/variables.tf
# Regional Managed Instance Group with a named port, autohealing, and a
# rolling-update policy.

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the regional MIG."
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

variable "instance_template" {
  description = "Self link of the instance template to roll out."
  type        = string
}

variable "instance_count" {
  description = "Fixed target number of instances when autoscaling is disabled (>= 2 for production)."
  type        = number
  default     = 2
}

# --- Autoscaling --------------------------------------------------------------
variable "enable_autoscaling" {
  description = "Attach a regional autoscaler. When true the autoscaler owns the size and instance_count is ignored."
  type        = bool
  default     = false
}

variable "min_replicas" {
  description = "Minimum instances the autoscaler maintains (>= 2 for HA)."
  type        = number
  default     = 2

  validation {
    condition     = var.min_replicas >= 1
    error_message = "min_replicas must be at least 1 (use 2+ for HA)."
  }
}

variable "max_replicas" {
  description = "Maximum instances the autoscaler may create."
  type        = number
  default     = 6
}

variable "autoscaling_cpu_target" {
  description = "Target average CPU utilization (0.0-1.0) that drives scaling."
  type        = number
  default     = 0.6

  validation {
    condition     = var.autoscaling_cpu_target > 0 && var.autoscaling_cpu_target <= 1
    error_message = "autoscaling_cpu_target must be between 0 and 1."
  }
}

variable "autoscaling_cooldown_sec" {
  description = "Seconds the autoscaler waits for a new instance to warm up before using its metrics."
  type        = number
  default     = 90
}

variable "scale_in_window_sec" {
  description = "Trailing window (seconds) over which scale-in is rate-limited, to avoid shrinking too fast after a spike."
  type        = number
  default     = 300
}

variable "scale_in_max_replicas" {
  description = "Maximum instances that may be removed within scale_in_window_sec."
  type        = number
  default     = 1
}

variable "app_port" {
  description = "Application port exposed as the MIG named port."
  type        = number
  default     = 8080
}

variable "named_port_name" {
  description = "Named port label the backend service references."
  type        = string
  default     = "http"
}

variable "health_check_self_link" {
  description = "Self link of the health check used for autohealing."
  type        = string
}

variable "auto_healing_initial_delay_sec" {
  description = "Grace period before autohealing probes a new instance (allow startup script + app boot)."
  type        = number
  default     = 300
}

variable "distribution_zones" {
  description = "Optional explicit list of zones to spread instances across. Empty = let GCP choose zones in the region."
  type        = list(string)
  default     = []
}

variable "max_surge_fixed" {
  description = "Extra instances created during a rolling update. For a regional MIG should be >= number of target zones."
  type        = number
  default     = 3
}

variable "max_unavailable_fixed" {
  description = "Instances that may be unavailable during a rolling update."
  type        = number
  default     = 0
}
