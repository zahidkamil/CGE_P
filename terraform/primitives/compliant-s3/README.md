# Lab 2.3 — Compliant S3 (NIST 800-53)

Terraform module that provisions a compliant S3 bucket and dedicated logging bucket satisfying five NIST 800-53 Rev 5 controls: AC-3, SC-28, CM-6, AU-3, AU-6.

---

## Architecture

```
provider "aws" (default_tags)          → CM-6: compliance tags on every resource

aws_s3_bucket "primary"
  ├── server_side_encryption            → SC-28
  ├── versioning                        → CM-6
  ├── public_access_block               → AC-3
  └── logging ──────────────────────────────────┐
                                                 ▼
aws_s3_bucket "log"                      AU-3 / AU-6
  ├── ownership_controls (BucketOwnerPreferred)
  ├── acl (log-delivery-write)
  ├── server_side_encryption            → SC-28
  └── public_access_block               → AC-3
```

---

## Control Mapping

| Control | How |
|---------|-----|
| **AC-3** | `public_access_block` with all four flags `true` on both buckets — blocks every public access vector |
| **SC-28** | AES-256 server-side encryption on both buckets. KMS upgrade path left as commented block for a later lab |
| **CM-6** | Terraform code is the documented baseline; `default_tags` enforces compliance tags on every resource; `terraform plan` detects drift |
| **AU-3** | S3 server access logging captures who, what, when, where, and outcome for every request on the primary bucket |
| **AU-6** | Log bucket stores encrypted, private audit records available for ongoing review |

---

## Log Bucket Design

The log bucket uses `BucketOwnerPreferred` + `log-delivery-write` together:

- `log-delivery-write` grants AWS's internal log delivery service write access — it is **not** a public ACL and is unaffected by `block_public_acls`, which only blocks `AllUsers` and `AuthenticatedUsers` grants
- `BucketOwnerPreferred` transfers ownership of written log objects to you automatically, because the log delivery service includes `bucket-owner-full-control` on every write
- `BucketOwnerEnforced` cannot be used here — it disables all ACLs including `log-delivery-write`, silently breaking logging

---

## What I Learned

- The local name in `resource "aws_s3_bucket" "primary"` is just a Terraform label — the real AWS bucket name is the `bucket` argument. The label is used to wire resources together with references like `aws_s3_bucket.primary.id`
- NIST enhancements like AC-3(2) through AC-3(10) are not all required — your system baseline (Low/Moderate/High) determines which apply. This module satisfies the base controls
- `default_tags` in the provider block is the right place for compliance tags — every new resource inherits them automatically with no risk of forgetting
- S3 server access logs are not real time. Delivery is best-effort with a 1–3 hour typical delay — an empty log bucket right after uploading a file is normal and expected
- `terraform show -json` output is machine-readable compliance evidence. No screenshots needed

---

## Troubleshooting

**AWS CLI output set to `both`**
All `aws s3api` verification commands returned `Unknown output type: both`. Fixed by running `aws configure` and setting output format to `json`.

**`$BUCKET` variable not resolving**
Commands using `$BUCKET` silently failed. Ran `terraform output` to list available outputs, checked the correct name, and used `echo "$BUCKET"` to verify the variable. Hardcoded the bucket name temporarily to confirm the aws commands themselves worked.

**No logs appeared after uploading a file**
Checked the log bucket immediately after uploading a test file — nothing was there. Confirmed the configuration was correct with `aws s3api get-bucket-logging` and `get-bucket-acl`, then waited. Logs appeared a few hours later as expected.

---

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Capture evidence
mkdir -p evidence
terraform show -json tfplan > evidence/plan.json
terraform show -json        > evidence/state.json

# Verify controls
BUCKET=$(terraform output -raw bucket_name)
aws s3api get-bucket-encryption   --profile <profile> --bucket "$BUCKET"
aws s3api get-bucket-versioning   --profile <profile> --bucket "$BUCKET"
aws s3api get-public-access-block --profile <profile> --bucket "$BUCKET"

# Cleanup (empty buckets first due to versioning)
terraform destroy
```