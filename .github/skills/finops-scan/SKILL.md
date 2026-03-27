---
name: finops-scan
description: "Use this skill when the user asks about FinOps scanning, cost governance scanning, running PSRule, Checkov, Cloud Custodian, or Infracost against Azure resources, interpreting SARIF results, or configuring any of the 4 scanner tools. Also use when discussing Azure cost governance policies, required tags, or scan result analysis."
---

## Overview

The FinOps Cost Governance Scanner combines 4 open-source tools to scan Azure infrastructure for cost governance violations. Each tool covers a distinct domain and produces or converts to SARIF v2.1.0 for GitHub Security tab integration.

## PSRule for Azure

**Purpose:** Validates Azure IaC templates (Bicep/ARM) against the Azure Well-Architected Framework Cost Optimization pillar.

**What it scans:** Bicep and ARM templates for structural cost governance issues (missing tags, non-recommended SKUs, missing configurations).

**Configuration file:** `src/config/ps-rule.yaml`

**Key rules for FinOps:**

- `Azure.Resource.UseTags` — Ensures resources have required tags
- `Azure.VM.UseManagedDisks` — Recommends managed disks over unmanaged
- `Azure.AppService.MinPlan` — Validates minimum App Service plan tier
- `Azure.SQL.MinTLS` — Security rule with cost implications
- `Azure.VM.DiskCaching` — Ensures disk caching is configured
- `Azure.Storage.UseReplication` — Validates storage replication settings

**Run locally:**

```powershell
Install-Module -Name PSRule.Rules.Azure -Scope CurrentUser
Assert-PSRule -Module PSRule.Rules.Azure -InputPath infra/ -Option src/config/ps-rule.yaml -OutputFormat Sarif -OutputPath reports/psrule-results.sarif
```

**Run in CI (GitHub Actions):**

```yaml
- uses: microsoft/ps-rule@v2.9.0
  with:
    modules: PSRule.Rules.Azure
    outputFormat: Sarif
    outputPath: reports/psrule-results.sarif
```

**SARIF output:** Native. Upload with category `finops/psrule`.

## Checkov

**Purpose:** Multi-cloud IaC security and compliance scanner with 1,000+ built-in policies covering Azure, AWS, and GCP.

**What it scans:** Bicep, Terraform, ARM, CloudFormation, Kubernetes manifests, Dockerfile, and Helm charts.

**Configuration file:** `src/config/.checkov.yaml`

**Key settings:**

- `framework: [bicep, arm]` — Scan Bicep and ARM templates
- `soft-fail: true` — Do not fail the pipeline on findings (report only)
- `skip-check` — Exclude specific checks not relevant to cost governance

**Run locally:**

```bash
pip install checkov
checkov -d infra/ --config-file src/config/.checkov.yaml --output sarif --output-file-path reports/
```

**Run in CI (GitHub Actions):**

```yaml
- uses: bridgecrewio/checkov-action@v12
  with:
    directory: infra/
    config_file: src/config/.checkov.yaml
    output_format: sarif
    output_file_path: reports/
```

**SARIF output:** Native. Upload with category `finops/checkov`.

## Cloud Custodian

**Purpose:** Runtime cost governance engine that scans deployed Azure resources for orphans, tagging violations, right-sizing opportunities, and idle resources.

**What it scans:** Live Azure resources via Azure Resource Manager APIs.

**Configuration directory:** `src/config/custodian/`

**Policy YAML format:**

```yaml
policies:
  - name: find-orphaned-disks
    resource: azure.disk
    filters:
      - type: value
        key: properties.diskState
        value: Unattached
    actions:
      - type: mark-for-op
        tag: custodian_cleanup
        op: delete
        days: 14
```

**Run locally:**

```bash
pip install c7n c7n-azure
custodian run -s output/ src/config/custodian/ --cache-period 0
```

**SARIF output:** JSON only (requires conversion). Use `src/converters/custodian-to-sarif.py` to convert Cloud Custodian JSON output to SARIF v2.1.0. Upload with category `finops/custodian`.

## Infracost

**Purpose:** Pre-deployment cost estimation from IaC changes. Shows cost impact of pull requests before merge.

**What it scans:** Bicep and Terraform templates to estimate monthly cloud costs.

**Run locally:**

```bash
infracost breakdown --path infra/ --format json --out-file reports/infracost.json
```

**Run in CI (GitHub Actions):**

```yaml
- uses: infracost/actions/setup@v3
  with:
    api-key: ${{ secrets.INFRACOST_API_KEY }}
- run: infracost breakdown --path infra/ --format json --out-file reports/infracost.json
```

**SARIF output:** JSON only (requires conversion). Use `src/converters/infracost-to-sarif.py` to convert Infracost JSON output to SARIF v2.1.0. Upload with category `finops/infracost`.

## Interpreting SARIF Results in GitHub Security Tab

SARIF results appear under the **Security** tab > **Code scanning alerts** in each repository.

**Filtering by tool:**

- Use the "Tool" filter to select `PSRule`, `Checkov`, `Cloud Custodian`, or `Infracost`
- Each tool uses a distinct SARIF category prefix (`finops/psrule`, `finops/checkov`, `finops/custodian`, `finops/infracost`)

**Severity mapping:**

| SARIF Level | GitHub Severity | Action |
|-------------|----------------|--------|
| `error` | Critical/High | Immediate fix required |
| `warning` | Medium | Plan remediation |
| `note` | Low | Track for review |

**Rule ID prefixes:**

- `FINOPS-TAG-*` — Tagging compliance violations
- `FINOPS-COST-*` — Cost optimization violations
- `FINOPS-OPT-*` — Resource optimization recommendations
- `FINOPS-GATE-*` — Deployment cost gate violations
- `FINOPS-ANOMALY-*` — Cost anomaly detections
