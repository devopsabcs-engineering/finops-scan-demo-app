---
title: "FinOps Demo App 004 — No Auto-Shutdown Violation"
description: "Demo application that intentionally deploys a development VM without auto-shutdown to test FinOps scanner shutdown policy detection."
---

## Purpose

This demo application deploys a **D4s_v5 VM running 24/7** tagged as `Environment: Development` without an auto-shutdown schedule to validate that the FinOps scanner detects missing shutdown policies.

## Intentional Violation

**Violation type:** Missing auto-shutdown on non-production VM

| Resource                               | Issue                                             | Est. Monthly Cost |
| -------------------------------------- | ------------------------------------------------- | ----------------- |
| D4s_v5 VM                              | Running 24/7 without auto-shutdown                | ~$140             |
| Off-hours waste (12h/day + weekends)   | ~60% of runtime is outside business hours         | ~$84 wasted       |

Per governance policy, all non-production VMs must have `Microsoft.DevTestLab/schedules` auto-shutdown enabled at 19:00 local timezone.

## Expected Scanner Findings

| Scanner | Expected Finding |
| --------- | ----------------- |
| Cloud Custodian | `offhours` policy — VM missing auto-shutdown schedule |
| PSRule | `Azure.VM.AutoShutdown` — dev VM without shutdown schedule |
| Checkov | Missing DevTestLab schedule for non-prod VM |

## Resources Deployed

- **VNet** with default subnet
- **NSG** with SSH rule
- **Public IP** (Standard, Static)
- **NIC** — attached to VM
- **VM** (D4s_v5, Ubuntu 22.04 LTS) — NO auto-shutdown schedule

## Local Development

```powershell
./start-local.ps1
./stop-local.ps1
```

## Deploy to Azure

Use the **Deploy to Azure** workflow (`Actions` > `Deploy to Azure` > `Run workflow`).

**Note:** The VM requires an `adminPassword` parameter. Set it via the Azure CLI or as a workflow parameter override.

## Teardown

Use the **Teardown Azure Resources** workflow to delete the `rg-finops-demo-004` resource group.
