---
title: "FinOps Demo App 003 — Orphaned Resources Violation"
description: "Demo application that intentionally deploys orphaned Azure resources not attached to any compute workload for FinOps scanner testing."
---

## Purpose

This demo application deploys **orphaned Azure resources** to validate that the FinOps scanner detects unattached resources that accumulate cost without providing value.

## Intentional Violation

**Violation type:** Orphaned / unattached resources

| Resource | Status | Est. Monthly Cost |
| ---------- | -------- | ------------------- |
| Public IP (Standard, Static) | Not attached to any NIC or LB | ~$3.65 |
| Network Interface | Not attached to any VM | $0 (but indicates waste) |
| Managed Disk (Premium, 128GB) | Not attached to any VM | ~$19.71 |
| NSG | Not associated with any subnet or NIC | $0 (but indicates waste) |
| **Total waste** | | **~$23/month** |

## Expected Scanner Findings

| Scanner | Expected Finding |
| --------- | ----------------- |
| Cloud Custodian | `orphaned-disk` — managed disk not attached to any VM |
| Cloud Custodian | `orphaned-public-ip` — public IP not associated with a resource |
| Cloud Custodian | `orphaned-nic` — NIC not attached to any VM |
| PSRule | Unattached network resources detected |

## Resources Deployed

- **VNet** with default subnet
- **Public IP** (Standard, Static) — orphaned
- **NIC** — orphaned
- **Managed Disk** (Premium_LRS, 128GB, Empty) — orphaned
- **NSG** — orphaned

## Local Development

```powershell
./start-local.ps1
./stop-local.ps1
```

## Deploy to Azure

Use the **Deploy to Azure** workflow (`Actions` > `Deploy to Azure` > `Run workflow`).

## Teardown

Use the **Teardown Azure Resources** workflow to delete the `rg-finops-demo-003` resource group.
