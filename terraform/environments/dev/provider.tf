# environments/dev/provider.tf

provider "google" {
  project = var.project_id
  region  = var.region

  # Applied to every resource that supports labels (cost allocation).
  default_labels = local.labels
}
