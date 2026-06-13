# consumers/dev/main.tf
terraform {
  required_version = ">= 1.6"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = "zahid-cloud-learning"
  region  = "us-central1"
}

locals {
  gcp_project = "zahid-cloud-learning"
}

module "data_bucket" {
  source = "../../modules/compliant-gcs-bucket"

  gcp_project        = local.gcp_project
  project_label      = "cgep-lab"
  environment        = "dev"
  retention_days     = 30
  bucket_name_suffix = "should-never-exist"
}

output "attestation" { value = module.data_bucket.compliance_attestation }
output "bucket_url"  { value = module.data_bucket.bucket_url }