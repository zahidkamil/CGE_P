# main.tf
terraform {
    required_version = ">=1.6"
    required_providers {
        aws = {source = "hashicorp/aws", version = "~> 5.0"}
        random = {source = "hashicorp/random", version = "~> 3.6"}
    }
}

provider "aws" {
    region = "us-east-1"

    # CM-6: Configuration settings, required compliance tags applied to every
    # taggable resource by default. Removes the chance of forgetting them.

    default_tags {
        tags = {
            Project = var.project_name
            Environment = var.environment
            ManagedBy = "Terraform"
            ComplianceScope = "cge-p-lab"
        }
    }
}

resource "random_id" "bucket_suffix" {
    # Generate a random 4-byte hex string to append to the bucket name, ensuring uniqueness.
    byte_length = 4
}

locals {
    effective_suffix = var.bucket_suffix != "" ? var.bucket_suffix : random_id.bucket_suffix.hex
    primary_name = "${var.project_name}-${var.environment}-data-${local.effective_suffix}"
    log_name = "${var.project_name}-${var.environment}-logs-${local.effective_suffix}"
}

resource "aws_s3_bucket" "primary" {
    bucket = local.primary_name
}


data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms_key_policy" {
  // This does not create an IAM policy but is used to construct a JSON policy doucment using HCL blocks instead of hand-writing JSON. The resulting JSON is then passed to the KMS key resource.
  // Grants the root user of the account full access to the KMS key, and allows S3 to use the key for encryption/decryption.
  statement {
    sid = "AllowAdministration"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    // When S3 encrypts an object with a KMS key, it needs to call GenerateDataKey to get a data key for encrypting the object, and Decrypt to decrypt the data key when reading the object.
    // The data key is stored alongside the object in S3, encrypted with the KMS key. S3 uses the KMS key to decrypt the data key when reading the object.
    sid = "AllowS3Use"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt"
    ]
    resources = ["*"]
    condition {
      //Ensures this key can be used to encrypt/decrypt objects belinging to your account's S3 buckets. 
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "bucket" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms_key_policy.json

  tags = {
    Name = "${var.project_name}-s3-kms"
  }
}

resource "aws_kms_alias" "bucket" {
  name          = "alias/${var.project_name}-${var.environment}-s3"
  target_key_id = aws_kms_key.bucket.key_id
}


# SC-28: Protection of information at rest.
# AES-256 keeps this lab simple. The commented block below shows how you'd
# switch to KMS-managed keys, covered in a later lab.
resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
    bucket = aws_s3_bucket.primary.id

    # rule {
    #     apply_server_side_encryption_by_default {
    #         sse_algorithm = "AES256"
    #     }
    # }

    # KMS teaser:
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.bucket.arn
      }
      bucket_key_enabled = true
      // Reduces the number of calls to KMS as S3 generates one time-limited "bucket key" per bucket by calling KMS once, and then uses that bucket key to encrypt/decrypt objects in the bucket. 
      //The bucket key is rotated automatically by S3, and is only valid for a short time (15 minutes). This reduces the number of calls to KMS, which can be a bottleneck for high-throughput workloads.
    }
}

# CM-6: Versioning preserves prior object states for recovery and audit.
resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
  versioning_configuration {
    status = "Enabled"
  }
}

# AC-3: Access control, explicit deny on every public access vector.
resource "aws_s3_bucket_public_access_block" "primary" {
  bucket                  = aws_s3_bucket.primary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# Log Bucket
# AU-3 / AU-6: Content of audit records + audit review.
resource "aws_s3_bucket" "log" {
  bucket = local.log_name
}

// Bucket ownership controls and ACLs to allow S3 server access logging to write to the log bucket, while keeping it private otherwise.
resource "aws_s3_bucket_ownership_controls" "log" {
  bucket = aws_s3_bucket.log.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

// The "log-delivery-write" ACL allows the S3 logging service to write logs to this bucket, while the public access block and ownership controls prevent any other access.
// AWs log delivery service writes the object and automatically includes the "bucket-owner-full-control" ACL on the object, which gives full control to the bucket owner even if the log writer is a different AWS account (as is the case with S3 server access logging).
resource "aws_s3_bucket_acl" "log" {
  depends_on = [aws_s3_bucket_ownership_controls.log]
  bucket     = aws_s3_bucket.log.id
  acl        = "log-delivery-write"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log" {
  bucket = aws_s3_bucket.log.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "log" {
  bucket                  = aws_s3_bucket.log.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true // only for AllUsers or AuthenticatedUsers ACLs, so it doesn't interfere with the log-delivery-write ACL
  restrict_public_buckets = true
}

// AU-3 / AU-6: Content of audit records + audit review.
resource "aws_s3_bucket_logging" "primary" {
  bucket        = aws_s3_bucket.primary.id
  target_bucket = aws_s3_bucket.log.id
  target_prefix = "access-logs/"
}