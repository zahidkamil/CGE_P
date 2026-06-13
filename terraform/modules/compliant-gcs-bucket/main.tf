# main.tf
terraform {
  required_version = ">= 1.6"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

locals {
  required_labels = {
    project          = var.project_label
    environment      = var.environment
    managed_by       = "terraform"
    compliance_scope = "cge-p-lab"
  }
  # merge works from left to right, and the rightmost value wins on duplicate keys. 
  # This allows users/consumers of this module to provide additional labels but the required label values will not be overridden.
  # The developer calling this module can only touch what the module exposes as variable blocks. Therefore to change this
  # a consumer would have to fork the module, modify it to escape the controls set, which becomes a deliberate auditable action.
  effective_labels = merge(var.labels, local.required_labels)
  bucket_name      = "${var.project_label}-${var.environment}-${var.bucket_name_suffix}"
  keyring_id       = "${var.bucket_name_suffix}-ring"
  key_id           = "${var.bucket_name_suffix}-key"
}

# For each GCP Project, google uses a service account that is used as an identity for google cloud storage operations
# including CMEK, storage notifications to pub/sub allowing the service account obtaining access to these services and for 
# cloud storage to use these customer-managed resources. 
data "google_storage_project_service_account" "gcs" {
  project = var.gcp_project
}

# SC-12: cryptographic key establishment. We own the key, not Google.
# keyring is just a container/namespace for keys and cannot be deleted. Permissions are granted at the keyring level rather 
# than per key. 
resource "google_kms_key_ring" "ring" {
  name     = local.keyring_id
  location = var.kms_location
  project  = var.gcp_project
}

# SC-13 / SC-28: cryptographic protection at rest. 90-day rotation.
resource "google_kms_crypto_key" "key" {
  name            = local.key_id
  key_ring        = google_kms_key_ring.ring.id
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = false  # set true in production
  }
}

# Only adds the single role needed to the service account used by GCS, following the principle of least privilege.
resource "google_kms_crypto_key_iam_member" "gcs_encrypter" {
  crypto_key_id = google_kms_crypto_key.key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

# AC-3 + SC-28 + CM-6 + AU-11 in one resource declaration.
resource "google_storage_bucket" "bucket" {
  name     = local.bucket_name
  project  = var.gcp_project
  location = var.location

  # AC-3 -> uniform_bucket_level removes ACLs or per-object permissions, so only IAM policies apply. Public access prevention enforces that no public ACLs or policies can be added.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  

  versioning { enabled = true }
  # SC-28: encryption at rest with customer-managed keys (CMEK). Google-managed keys are the default if this block is omitted.
  encryption {
    default_kms_key_name = google_kms_crypto_key.key.id
  }
  # AU-11: Retaining logs by making it undeletable for a set period
  retention_policy {
    retention_period = var.retention_days * 86400 # SC-12: retention period in seconds
    is_locked        = false
  }
  # CM-6: Object versioning preserves prior object states for recovery and audit.
  labels = local.effective_labels

  depends_on = [google_kms_crypto_key_iam_member.gcs_encrypter]
}