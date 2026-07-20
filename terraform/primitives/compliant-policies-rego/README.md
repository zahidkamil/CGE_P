# Lab 3.3 — Writing Compliance Policies in Rego (GCP)

Policy-as-code layer that checks a `terraform plan -json` output against NIST 800-53 controls *before* anything is applied.

## What's here

```
policies/
  sc28_encryption.rego      # SC-28: CMEK on GCS buckets
  ac3_no_public.rego        # AC-3: no public buckets, no open mgmt ports
  cm6_required_tags.rego    # CM-6: required compliance labels
  tests/                    # *_test.rego fixtures, one per policy
  README.md                 # control/severity/remediation index
terraform/
  main.tf                   # fixture with compliant + non-compliant resources
```

## How Rego works (quick mental model)

Rego isn't "return true/false" — a policy builds up a **set** by iterating over input data, and a resource only ends up in that set if every condition in a rule body holds for it.

- `deny contains msg if { ... }` — each time the body evaluates true for some binding, `msg` is added to the `deny` set. Multiple `deny` blocks in the same package all feed the same set (like calling `.update()` on a Python set repeatedly).
- `some x in collection` — equivalent to Python's `for x in collection`.
- Statements stacked in one rule body are implicitly **AND**ed — all must be true for that iteration to contribute a result.
- `package compliance.sc28` at the top of a file is like a Python module path. It's what makes the rule addressable later as `data.compliance.sc28.deny`.
- Helper rules like `bucket_resource contains r if {...}` work the same way as `deny` — they build their own named set (here, a deduplicated list of buckets from both `root_module.resources` and nested `child_modules`) so the main `deny` rule doesn't have to repeat that traversal logic.
- Function-style rules (`foo(x) := y if {...}`) are closer to real functions with guard-clause branches — e.g. `provided_labels` returns a set of label keys if labels exist, or an explicit empty `set()` if they don't.

## Why `opa eval` finds `data.compliance.sc28.deny`

`data` is OPA's root namespace containing every loaded package. `-d policies` loads all `.rego` files under that folder (like adding a directory to `PYTHONPATH`). The package declaration inside each file (`package compliance.sc28`) determines where its rules live under `data`, and `deny` is just the name chosen for the rule — querying `data.compliance.sc28.deny` is the same idea as `import compliance.sc28` then reading `compliance.sc28.deny`.

## Why the tests can use fake JSON

`google_storage_bucket.good` in a test fixture isn't a variable — it's a plain string shaped like the `address` field real `terraform show -json` output produces (`type.name`). `with input as compliant_input` temporarily swaps in that hand-written JSON as `input` for one expression, the same way you'd monkeypatch a global in a pytest test, so the policy can be exercised without running a real `terraform plan`.

## Plan-time quirk worth remembering

KMS key IDs resolve to `"(known after apply)"` at plan time and are omitted from the JSON entirely. `has_cmek` therefore checks that the `encryption` block *exists and isn't empty/null*, not that it holds a real key string — the value itself only resolves once you actually apply.

## Verification

```bash
opa test -v policies/                # expect PASS: 8/8
opa eval -d policies -i terraform/plan.json data.compliance.sc28.deny --format=pretty
opa eval -d policies -i terraform/plan.json data.compliance.ac3.deny  --format=pretty
opa eval -d policies -i terraform/plan.json data.compliance.cm6.deny  --format=pretty
```

Fix the fixture's non-compliant resources, regenerate `plan.json`, and all three `deny` sets should come back empty.

## Where this goes next

Lab 3.4 adds AWS-flavored equivalents of these same three controls (`aws_s3_bucket` and friends), and the combined suite runs through Conftest as the CI gate — same control IDs, same `deny` pattern, different cloud provider.