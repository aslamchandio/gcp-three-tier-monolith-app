# modules/network/versions.tf
# Modules declare provider requirements only — no required_version pin and no
# backend (those belong to the root configuration).

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }
}
