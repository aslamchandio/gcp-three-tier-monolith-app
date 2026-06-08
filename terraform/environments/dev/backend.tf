# environments/dev/backend.tf
# Remote state for the DEV network layer. State is isolated from prod by prefix.
# Backends cannot interpolate variables — set the bucket here or override at init:
#   terraform init -backend-config="bucket=<your-state-bucket>"
#
# The bucket must exist beforehand (create once, manually or in a bootstrap stack)
# with versioning enabled.

terraform {
  backend "gcs" {
    bucket = "bucket-tf-1234" # <-- replace with your GCS state bucket
    prefix = "dev/three-tier-tfstate"
  }
}
