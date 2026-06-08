# modules/secret-manager/main.tf

locals {
  # Only create a version for secrets that were given an initial value.
  secret_versions = {
    for k, v in var.secrets : k => v
    if v.secret_data != null
  }

  # Flatten {secret => [members]} into individual accessor bindings for created secrets.
  created_accessors = merge([
    for k, v in var.secrets : {
      for m in v.accessors : "${k}=>${m}" => { secret_key = k, member = m }
    }
  ]...)

  # Same for pre-existing (external) secrets referenced only by id.
  external_accessors = merge([
    for sid, members in var.external_accessors : {
      for m in members : "${sid}=>${m}" => { secret_id = sid, member = m }
    }
  ]...)
}

# --- Created secrets ----------------------------------------------------------
resource "google_secret_manager_secret" "this" {
  for_each = var.secrets

  project   = var.project_id
  secret_id = each.key
  labels    = var.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "this" {
  for_each = local.secret_versions

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = sensitive(each.value.secret_data)
}

# --- Accessor grants on created secrets --------------------------------------
resource "google_secret_manager_secret_iam_member" "created" {
  for_each = local.created_accessors

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret_key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}

# --- Accessor grants on pre-existing secrets (e.g. the Cloud SQL DB password) -
resource "google_secret_manager_secret_iam_member" "external" {
  for_each = local.external_accessors

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
