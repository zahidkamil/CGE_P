# Compliance Policies (Lab 3.3 — GCP)

Rego policies mapping NIST 800-53 controls to Terraform plan-time checks. Each policy inspects `terraform plan -json` output and denies non-compliant resources before `apply`.

| Control | Package | File | Severity | Enforces | Remediation |
|---|---|---|---|---|---|
| SC-28 | `compliance.sc28` | `sc28_encryption.rego` | High | Every `google_storage_bucket` has a non-empty `encryption { default_kms_key_name }` block (CMEK). | Add `encryption { default_kms_key_name = <kms_crypto_key_id> }` referencing a KMS key you control. |
| AC-3 | `compliance.ac3` | `ac3_no_public.rego` | Critical | Buckets: `uniform_bucket_level_access = true` and `public_access_prevention = "enforced"`. Firewalls: no `0.0.0.0/0`/`*` ingress on ports 22 or 3389. | Set the two bucket flags to their required values; narrow `source_ranges` or remove the firewall rule. |
| CM-6 | `compliance.cm6` | `cm6_required_tags.rego` | Medium | Taggable resources (`google_storage_bucket`, `google_compute_instance`, `google_compute_disk`) carry all four labels: `project`, `environment`, `managed_by`, `compliance_scope`. | Add the missing labels listed in the deny message. |

## Running the suite

```bash
opa test -v policies/
opa eval -d policies -i terraform/plan.json data.compliance.sc28.deny --format=pretty
opa eval -d policies -i terraform/plan.json data.compliance.ac3.deny  --format=pretty
opa eval -d policies -i terraform/plan.json data.compliance.cm6.deny  --format=pretty
```

An empty `deny` array means that control is satisfied. Every violation message includes the resource address, the control ID, and the fix.