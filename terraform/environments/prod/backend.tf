# environments/prod/backend.tf
# Remote state for the PROD network layer. Isolated from dev by prefix.
# Backends cannot interpolate variables — set the bucket here or override at init:
#   terraform init -backend-config="bucket=<your-state-bucket>"
#
# The bucket must exist beforehand with versioning enabled. For stronger blast-
# radius isolation you may point prod at a dedicated bucket/project.

terraform {
  backend "gcs" {
    bucket = "aslam-terraform-bucket" # <-- replace with your GCS state bucket
    prefix = "prod/three-tier-tfstate"
  }
}
