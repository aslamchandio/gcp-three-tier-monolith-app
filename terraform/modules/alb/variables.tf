# modules/alb/variables.tf
# Regional external Application Load Balancer (EXTERNAL_MANAGED scheme).
#
# A regional ALB requires a proxy-only subnet (REGIONAL_MANAGED_PROXY) in the
# VPC/region. This module can create it (create_proxy_subnet = true) without
# touching the existing application subnet.

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for all regional LB resources."
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

variable "vpc_self_link" {
  description = "Self link of the VPC the proxy subnet and LB attach to."
  type        = string
}

variable "instance_group" {
  description = "Self link of the MIG instance group to load balance."
  type        = string
}

variable "health_check_self_link" {
  description = "Self link of the regional health check for the backend service."
  type        = string
}

variable "backend_network_tags" {
  description = "Network tags of the backend instances. Used to scope the proxy-subnet firewall rule. When empty, that firewall rule is not created (you must allow proxy-subnet -> app_port some other way)."
  type        = list(string)
  default     = []
}

variable "app_port" {
  description = "Application/backend port the proxy-only subnet must reach (the data-plane port for a regional Envoy ALB)."
  type        = number
  default     = 8080
}

variable "named_port_name" {
  description = "Named port on the MIG the backend service targets (must match the MIG)."
  type        = string
  default     = "http"
}

variable "backend_timeout_sec" {
  description = "Backend response timeout in seconds."
  type        = number
  default     = 30
}

variable "network_tier" {
  description = "Network tier for the external IP and forwarding rules (PREMIUM or STANDARD)."
  type        = string
  default     = "PREMIUM"
}

# --- Proxy-only subnet (required for regional ALB) ---------------------------
variable "create_proxy_subnet" {
  description = "Create the REGIONAL_MANAGED_PROXY subnet. Set false if one already exists in this VPC/region."
  type        = bool
  default     = true
}

variable "proxy_subnet_cidr" {
  description = "CIDR for the proxy-only subnet. Must not overlap existing subnets."
  type        = string
  default     = "10.129.0.0/23"
}

# --- HTTPS (optional) --------------------------------------------------------
variable "enable_https" {
  description = "Create the HTTPS listener (:443) and redirect HTTP -> HTTPS. Flip this on only once the certificate is ready (a Google-managed cert must be ACTIVE), otherwise the redirect points at a listener that can't complete the TLS handshake."
  type        = bool
  default     = false
}

# Google-managed certificate (Certificate Manager). Preferred when you control a
# domain; no key material is handled by Terraform.
variable "managed_cert_domains" {
  description = "Domains for a Google-managed TLS certificate via Certificate Manager (regional, DNS authorization). When non-empty, a managed certificate is provisioned and attached to the HTTPS proxy (instead of a self-managed cert). Each domain needs its DNS-auth CNAME created (see the managed_cert_dns_records output) plus an A record pointing at the LB IP. The managed cert + DNS authorizations are created regardless of enable_https so the cert can provision before you flip the listener on."
  type        = list(string)
  default     = []
}

# Self-managed certificate (fallback when you have no domain, e.g. a self-signed
# cert for dev). Ignored when managed_cert_domains is set.
variable "ssl_certificate" {
  description = "PEM-encoded certificate. Required when enable_https = true AND managed_cert_domains is empty. Provide via a variable/secret, never hardcoded."
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssl_private_key" {
  description = "PEM-encoded private key. Required when enable_https = true AND managed_cert_domains is empty."
  type        = string
  default     = ""
  sensitive   = true
}
