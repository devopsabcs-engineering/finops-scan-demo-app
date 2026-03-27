---
title: "FinOps Compliance Data Model"
description: "Power BI data model for FinOps compliance pages integrating GitHub Code Scanning API, Azure Resource Graph, and FOCUS cost data."
ms.date: 2026-03-27
ms.topic: reference
author: devopsabcs-engineering
keywords:
  - power-bi
  - data-model
  - finops
  - compliance
---

## Overview

This document defines the Power BI data model for the FinOps compliance dashboard pages.
The model integrates three primary data sources:

- **GitHub Code Scanning API** — FinOps scan results (PSRule, Checkov, Cloud Custodian, Infracost) uploaded as SARIF
- **Azure Resource Graph** — Resource tagging compliance and metadata
- **Azure FOCUS export** — Standardized cost data via the Microsoft FinOps Toolkit

The data model uses a star schema with shared dimension tables across Security, Accessibility, and FinOps scan domains.
The `Repositories` dimension is shared across all domains, enabling cross-domain analysis in a single report.

## Entity-Relationship Diagram

### Dimension and Fact Tables

| Table | Type | Source | Key Fields |
| ----- | ---- | ------ | ---------- |
| Repositories | Dimension | GitHub API | repo_name, org, url |
| FinOpsAlerts | Fact | Code Scanning API | rule_id, severity, state, tool_name, created_at, fixed_at, repo_name |
| CostData | Fact | Azure FOCUS export | resource_id, service, cost, date, resource_group |
| ScanTools | Dimension | Static | tool_name, tool_version, scan_domain |
| GovernanceTags | Dimension | Azure Resource Graph | resource_id, tag_key, tag_value |

### Column Details

#### Repositories (Dimension)

| Column | Data Type | Description |
| ------ | --------- | ----------- |
| repo_name | Text | Repository short name (e.g., `finops-demo-app-001`) |
| org | Text | GitHub organization (e.g., `devopsabcs-engineering`) |
| url | Text | Full GitHub repository URL |
| scan_domain | Text | Domain filter: `Security`, `Accessibility`, or `FinOps` |

#### FinOpsAlerts (Fact)

| Column | Data Type | Description |
| ------ | --------- | ----------- |
| alert_number | Whole Number | GitHub alert number (unique per repo) |
| rule_id | Text | SARIF rule identifier (e.g., `FINOPS-001`) |
| rule_description | Text | Human-readable rule description |
| severity | Text | Alert severity: `error`, `warning`, `note` |
| state | Text | Alert state: `open`, `fixed`, `dismissed` |
| tool_name | Text | Scanner tool name (PSRule, Checkov, custodian-to-sarif, infracost-to-sarif) |
| created_at | DateTime | Alert creation timestamp |
| fixed_at | DateTime | Alert fix timestamp (null if still open) |
| repo_name | Text | Foreign key to `Repositories` |
| estimated_savings | Decimal | Estimated monthly cost savings in USD (populated for cost-related findings) |
| resource_name | Text | Azure resource name associated with the finding |

#### CostData (Fact)

| Column | Data Type | Description |
| ------ | --------- | ----------- |
| resource_id | Text | Azure resource ID |
| service | Text | Azure service name |
| cost | Decimal | Cost amount in billing currency |
| date | Date | Cost date |
| resource_group | Text | Azure resource group name |
| subscription_id | Text | Azure subscription ID |
| meter_category | Text | Azure meter category |
| currency | Text | Billing currency code |

#### ScanTools (Dimension)

| Column | Data Type | Description |
| ------ | --------- | ----------- |
| tool_name | Text | Tool identifier used in SARIF upload |
| tool_version | Text | Tool version string |
| scan_domain | Text | Domain classification: `FinOps` |
| tool_description | Text | Human-readable tool description |

Static data:

| tool_name | tool_version | scan_domain | tool_description |
| --------- | ----------- | ----------- | ---------------- |
| PSRule | 2.9.0 | FinOps | Azure Well-Architected Framework rules for IaC |
| Checkov | 3.2 | FinOps | Policy-as-code for IaC security and compliance |
| custodian-to-sarif | 1.0.0 | FinOps | Cloud Custodian runtime governance policies |
| infracost-to-sarif | 1.0.0 | FinOps | Infrastructure cost estimation and optimization |

#### GovernanceTags (Dimension)

| Column | Data Type | Description |
| ------ | --------- | ----------- |
| resource_id | Text | Azure resource ID |
| resource_name | Text | Azure resource name |
| resource_group | Text | Azure resource group name |
| resource_type | Text | Azure resource type |
| tag_key | Text | Tag key name |
| tag_value | Text | Tag value (null if tag is missing) |
| is_compliant | Boolean | Whether the tag is present and valid |

## Relationships

| From Table | From Column | To Table | To Column | Cardinality | Cross-Filter |
| --------- | ----------- | -------- | --------- | ----------- | ------------ |
| FinOpsAlerts | repo_name | Repositories | repo_name | Many-to-One | Single |
| FinOpsAlerts | tool_name | ScanTools | tool_name | Many-to-One | Single |
| CostData | resource_id | GovernanceTags | resource_id | Many-to-Many | Single |
| GovernanceTags | resource_group | CostData | resource_group | Many-to-One | Single |

### Shared Dimension: Repositories

The `Repositories` dimension table is shared across Security, Accessibility, and FinOps scan domains.
The `scan_domain` column enables filtering by domain while using a single lookup table.

- **Security domain** — GHAS alerts (CodeQL, Dependabot, secret scanning)
- **Accessibility domain** — Accessibility scan results (axe-core, Lighthouse)
- **FinOps domain** — Cost governance alerts (PSRule, Checkov, Cloud Custodian, Infracost)

The `ScanDomain` column values are: `"Security"`, `"Accessibility"`, `"FinOps"`.

## DAX Measures

### Compliance Rate

Percentage of findings that have been resolved.

```dax
Compliance Rate =
DIVIDE(
    COUNTROWS(FILTER(FinOpsAlerts, [state] = "fixed")),
    COUNTROWS(FinOpsAlerts)
)
```

### Total Open Findings

Count of alerts currently in the open state.

```dax
Total Open Findings =
CALCULATE(
    COUNTROWS(FinOpsAlerts),
    FinOpsAlerts[state] = "open"
)
```

### Cost Savings Potential

Sum of estimated monthly savings across all open findings.

```dax
Cost Savings Potential =
CALCULATE(
    SUM(FinOpsAlerts[estimated_savings]),
    FinOpsAlerts[state] = "open"
)
```

### Findings by Severity (Error)

Count of findings with error-level severity.

```dax
Critical Findings =
COUNTROWS(
    FILTER(FinOpsAlerts, [severity] = "error")
)
```

### Findings by Severity (Warning)

```dax
Warning Findings =
COUNTROWS(
    FILTER(FinOpsAlerts, [severity] = "warning")
)
```

### Findings by Severity (Note)

```dax
Note Findings =
COUNTROWS(
    FILTER(FinOpsAlerts, [severity] = "note")
)
```

### Mean Time to Remediate

Average duration between alert creation and resolution.

```dax
Mean Time to Remediate =
AVERAGEX(
    FILTER(FinOpsAlerts, [state] = "fixed"),
    DATEDIFF([created_at], [fixed_at], DAY)
)
```

### Tagging Compliance Rate

Percentage of resources with all 7 required governance tags present.

```dax
Tagging Compliance Rate =
DIVIDE(
    COUNTROWS(FILTER(GovernanceTags, [is_compliant] = TRUE())),
    COUNTROWS(GovernanceTags)
)
```
