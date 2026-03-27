---
title: "FinOps Demo App 005 — Redundant / Expensive Resources Violation"
description: "Demo application that intentionally deploys redundant App Service Plans across expensive regions and GRS storage for FinOps scanner testing."
---

## Purpose

This demo application deploys **redundant and unnecessarily expensive resources** to validate that the FinOps scanner detects duplicate infrastructure, non-approved regions, and over-provisioned storage redundancy.

## Intentional Violation

**Violation type:** Redundant and expensive resources

| Resource | Issue | Est. Monthly Cost |
| ---------- | ------- | ------------------- |
| S3 App Service Plan (westeurope) | Non-approved region, duplicate plan | ~$200 |
| S3 App Service Plan (southeastasia) | Non-approved region, duplicate plan | ~$200 |
| GRS Storage Account | Geo-redundant where LRS suffices for dev | ~$50 |
| **Total waste** | | **~$450/month** |

### Policy Violations

- **Region policy:** Both App Service Plans use non-approved regions (`westeurope`, `southeastasia`). Approved regions: `eastus`, `eastus2`, `centralus`.
- **Duplicate resources:** Two identical plans running the same workload doubles costs.
- **Storage redundancy:** GRS is unnecessary for a development static site; LRS would cost ~$2/month.

## Expected Scanner Findings

| Scanner | Expected Finding |
| --------- | ----------------- |
| Infracost | Monthly cost exceeds budget threshold for dev environment |
| PSRule | Resources deployed to non-approved regions |
| Checkov | GRS storage in non-production environment |
| Cloud Custodian | Duplicate App Service Plans across regions |

## Resources Deployed

- **App Service Plan** (`S3`) in `westeurope` — redundant
- **App Service Plan** (`S3`) in `southeastasia` — redundant
- **Web App** on Europe plan
- **Web App** on Asia plan
- **Storage Account** (`Standard_GRS`) — over-provisioned redundancy

## Local Development

```powershell
./start-local.ps1
./stop-local.ps1
```

## Deploy to Azure

Use the **Deploy to Azure** workflow (`Actions` > `Deploy to Azure` > `Run workflow`).

## Teardown

Use the **Teardown Azure Resources** workflow to delete the `rg-finops-demo-005` resource group.
