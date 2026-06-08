# modules/gcs-bucket/outputs.tf

output "bucket_name" {
  description = "Name of the bucket."
  value       = google_storage_bucket.this.name
}

output "bucket_url" {
  description = "gs:// URL of the bucket."
  value       = "gs://${google_storage_bucket.this.name}"
}

output "bucket_self_link" {
  description = "Self link of the bucket."
  value       = google_storage_bucket.this.self_link
}
