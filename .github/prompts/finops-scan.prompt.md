---
description: "Run a FinOps cost governance scan against Azure demo app repositories and analyze the results."
---

## Run FinOps Scan

Run the FinOps cost governance scanner against the demo app repositories and analyze the findings.

### Steps

1. **Run PSRule** against each demo app's `infra/` directory:

   ```powershell
   Assert-PSRule -Module PSRule.Rules.Azure -InputPath infra/ -Option src/config/ps-rule.yaml -OutputFormat Sarif -OutputPath reports/psrule-results.sarif
   ```

2. **Run Checkov** against each demo app's Bicep templates:

   ```bash
   checkov -d infra/ --config-file src/config/.checkov.yaml --output sarif --output-file-path reports/
   ```

3. **Run Cloud Custodian** against deployed Azure resources:

   ```bash
   custodian run -s output/ src/config/custodian/ --cache-period 0
   python src/converters/custodian-to-sarif.py output/ reports/custodian-results.sarif
   ```

4. **Run Infracost** for cost estimation:

   ```bash
   infracost breakdown --path infra/ --format json --out-file reports/infracost.json
   python src/converters/infracost-to-sarif.py reports/infracost.json reports/infracost-results.sarif
   ```

5. **Analyze results**: Review the SARIF files in `reports/` and summarize:
   - Total findings by tool and severity
   - Top cost optimization opportunities with estimated savings
   - Tagging compliance percentage
   - Recommended remediation priorities
