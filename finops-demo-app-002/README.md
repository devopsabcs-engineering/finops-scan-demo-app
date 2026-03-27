---
title: "FinOps Demo App 002 — Oversized Resources Violation"
description: "Demo application that intentionally deploys oversized Azure resources for a development workload to test FinOps scanner SKU governance detection."
---

## Purpose

This demo application deploys **oversized Azure resources** tagged as `Environment: Development` to validate that the FinOps scanner detects SKU governance violations.

## Intentional Violation

**Violation type:** Oversized resources for dev environment

| Resource | Deployed SKU | Max Allowed (dev) | Est. Monthly Cost |
| ---------- | ------------- | ------------------- | ------------------- |
| App Service Plan | P3v3 (PremiumV3) | B1 (Basic) | ~$700 |
| Storage Account | Premium_LRS | Standard_LRS | ~$100 |
| **Total waste** | | | **~$800/month** |

## Expected Scanner Findings

| Scanner | Expected Finding |
| --------- | ----------------- |
| Infracost | Monthly cost exceeds dev environment budget threshold |
| PSRule | SKU size exceeds dev environment maximum |
| Checkov | Premium tier storage in non-production environment |

## Resources Deployed

- **App Service Plan** (`P3v3 PremiumV3`) — tagged `Environment: Development`
- **Storage Account** (`Premium_LRS`) — tagged `Environment: Development`
- **Web App** — on the oversized plan

## Local Development

```powershell
./start-local.ps1
./stop-local.ps1
```

## Deploy to Azure

Use the **Deploy to Azure** workflow (`Actions` > `Deploy to Azure` > `Run workflow`).

## Teardown

Use the **Teardown Azure Resources** workflow to delete the `rg-finops-demo-002` resource group.
