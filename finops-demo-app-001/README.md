---
title: "FinOps Demo App 001 — Missing Tags Violation"
description: "Demo application that intentionally deploys Azure resources without required governance tags for FinOps scanner testing."
---

## Purpose

This demo application deploys Azure resources with **zero governance tags** to validate that the FinOps cost governance scanner correctly identifies missing tag violations.

## Intentional Violation

**Violation type:** Missing required tags

All deployed resources (Storage Account, App Service Plan, Web App) are missing all 7 required governance tags:

| # | Missing Tag | Required By |
| --- | ------------- | ------------- |
| 1 | `CostCenter` | FinOps chargeback policy |
| 2 | `Owner` | Resource ownership policy |
| 3 | `Environment` | Environment classification |
| 4 | `Application` | Application identification |
| 5 | `Department` | Organizational mapping |
| 6 | `Project` | Project tracking |
| 7 | `ManagedBy` | Management mechanism |

## Expected Scanner Findings

| Scanner | Expected Finding |
| --------- | ----------------- |
| PSRule | `Azure.Resource.UseTags` — resources missing required tags |
| Checkov | `CKV_AZURE_XXX` — missing tag governance checks |
| Cloud Custodian | `missing-tags` policy — untagged resources detected |

## Resources Deployed

- **Storage Account** (`Standard_LRS`) — no tags
- **App Service Plan** (`B1`) — no tags
- **Web App** — no tags

## Local Development

```powershell
# Start locally
./start-local.ps1

# Stop locally
./stop-local.ps1
```

## Deploy to Azure

Use the **Deploy to Azure** workflow (`Actions` > `Deploy to Azure` > `Run workflow`).

## Teardown

Use the **Teardown Azure Resources** workflow to delete the `rg-finops-demo-001` resource group.
