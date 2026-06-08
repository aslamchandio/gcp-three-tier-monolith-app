# modules/gcs-bucket/main.tf

resource "google_storage_bucket" "this" {
  project                     = var.project_id
  name                        = var.name
  location                    = var.location
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.uniform_bucket_level_access
  public_access_prevention    = var.public_access_prevention
  force_destroy               = var.force_destroy
  labels                      = var.labels

  versioning {
    enabled = var.enable_versioning
  }
}

# Read-only access for the application service account (and any other viewers).
resource "google_storage_bucket_iam_member" "viewers" {
  for_each = toset(var.viewers)

  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectViewer"
  member = each.value
}
