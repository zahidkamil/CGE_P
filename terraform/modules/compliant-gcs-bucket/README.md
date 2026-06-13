# compliant-gcs-bucket

Reusable Terraform module that deploys a GCS bucket with security and compliance controls locked in. Consumers configure what the module exposes via variables — they cannot disable the hardcoded controls.

## Resources Provisioned

- KMS keyring and crypto key with enforced 90-day rotation
- IAM binding granting the GCS service agent access to the key
- GCS bucket with CMEK encryption, uniform access, and public access prevention

## NIST Controls

| Control | Enforcement |
|---------|-------------|
| **SC-12** — Key Management | KMS crypto key with `rotation_period = "7776000s"` (90 days) |
| **SC-13** — Cryptographic Protection | CMEK via `encryption { default_kms_key_name = ... }` |
| **SC-28** — Protection at Rest | All objects encrypted with the customer-managed key |
| **AC-3** — Access Enforcement | `uniform_bucket_level_access = true` and `public_access_prevention = "enforced"` |
| **CM-6** — Configuration Settings | Hardcoded controls + required labels merged last so consumers cannot override them |
| **AU-11** — Audit Record Retention | `retention_policy` and `versioning` enforce a minimum retention period |

> AU-11 covers data retention here, not audit log retention. Full control compliance requires Cloud Logging data access logs retained separately.

## Usage

```hcl
module "data_bucket" {
  source = "../../modules/compliant-gcs-bucket"

  gcp_project        = "my-project"
  project_label      = "my-team"
  environment        = "dev"
  retention_days     = 30
  bucket_name_suffix = "my-bucket-001"
}
```

## Inputs

| Name | Description | Required |
|------|-------------|----------|
| `gcp_project` | GCP project ID | yes |
| `project_label` | Project label value for compliance tagging | yes |
| `environment` | Deployment environment (`dev`, `prod`, etc.) | yes |
| `retention_days` | Minimum object retention period in days | yes |
| `bucket_name_suffix` | Suffix appended to the generated bucket name | yes |
| `labels` | Additional labels to merge onto the bucket | no |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_url` | `gs://` URL of the bucket |
| `bucket_self_link` | Self-link of the bucket |
| `kms_key_id` | Resource ID of the CMEK key |
| `compliance_attestation` | Map of enforced control values for audit evidence |
