---
description: "FinOps tagging rules, cost governance policies, and compliance standards for Azure resource deployments."
applyTo: "**/*.bicep,**/infra/**,**/*.json"
---

# FinOps Governance Rules

## Required Resource Tags

Every Azure resource must include the following 7 tags. Resources missing any of these tags are non-compliant and will be flagged by the FinOps scanner.

| # | Tag Name | Purpose | Example Values |
|---|----------|---------|----------------|
| 1 | `CostCenter` | Financial cost center for chargeback | `CC-1234`, `CC-5678` |
| 2 | `Owner` | Resource owner contact | `team@contoso.com` |
| 3 | `Environment` | Deployment environment | `dev`, `staging`, `prod` |
| 4 | `Application` | Application identifier | `finops-demo-001` |
| 5 | `Department` | Organizational department | `Engineering`, `Finance` |
| 6 | `Project` | Project name or code | `FinOps-Scanner` |
| 7 | `ManagedBy` | Management mechanism | `Bicep`, `Terraform`, `Manual` |

## Tag Format Rules

- Tag names use PascalCase
- Tag values must not be empty strings
- `Environment` must be one of: `dev`, `staging`, `prod`, `shared`
- `Owner` must be a valid email address
- `CostCenter` must match pattern `CC-\d{4,6}`

## Cost Governance Policies

### Approved Regions

Resources must be deployed to approved Azure regions only:

- `eastus`
- `eastus2`
- `centralus`

### SKU Governance

| Environment | Max App Service Plan | Max VM Size | Max Storage Tier |
|-------------|---------------------|-------------|-----------------|
| dev | B1 | Standard_B2s | Standard_LRS |
| staging | S1 | Standard_D2s_v5 | Standard_LRS |
| prod | P1v3 | Standard_D4s_v5 | Standard_GRS |

### Auto-Shutdown Policy

- All non-production VMs must have auto-shutdown enabled
- Shutdown time: 19:00 local timezone (default)
- Exceptions require documented approval

### Orphaned Resource Policy

- Unattached managed disks older than 14 days must be reviewed
- Public IPs not associated with a resource must be removed within 7 days
- Network interfaces not attached to a VM must be removed within 7 days

## SARIF Integration

FinOps governance findings use the following SARIF conventions:

- **Category prefix:** `finops/`
- **Rule ID prefix:** `FINOPS-`
- **Tool names:** `PSRule`, `Checkov`, `CloudCustodian`, `Infracost`
- **Security severity:** Mapped to estimated monthly waste amount
