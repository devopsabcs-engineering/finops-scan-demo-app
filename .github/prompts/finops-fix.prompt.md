---
description: "Fix FinOps governance violations found in Azure IaC templates by applying remediation changes."
---

## Fix FinOps Violations

Analyze FinOps scan results and apply fixes to the IaC templates to resolve cost governance violations.

### Steps

1. **Read the SARIF results** from the `reports/` directory to identify violations
2. **For each violation**, determine the fix based on the rule ID:

   | Rule Pattern | Fix Action |
   |-------------|------------|
   | `FINOPS-TAG-*` | Add missing required tags to the resource |
   | `FINOPS-COST-*` | Right-size the resource SKU for the environment |
   | `FINOPS-OPT-*` | Remove orphaned resources or enable auto-shutdown |
   | `FINOPS-GATE-*` | Adjust resource configuration to meet budget thresholds |

3. **Apply the required governance tags** to resources missing them:

   ```bicep
   tags: {
     CostCenter: 'CC-1234'
     Owner: 'team@contoso.com'
     Environment: 'dev'
     Application: 'finops-demo-001'
     Department: 'Engineering'
     Project: 'FinOps-Scanner'
     ManagedBy: 'Bicep'
   }
   ```

4. **Right-size resources** by changing SKUs to match environment governance rules
5. **Enable auto-shutdown** on non-production VMs
6. **Remove orphaned resources** (unattached disks, unused public IPs, detached NICs)
7. **Re-run the scan** to verify all violations are resolved
