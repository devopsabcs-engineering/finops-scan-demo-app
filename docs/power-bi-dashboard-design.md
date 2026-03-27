---
title: "FinOps Compliance Dashboard Design"
description: "Page layouts, chart specifications, DAX measures, and filter interactions for the 6-page FinOps compliance Power BI dashboard."
ms.date: 2026-03-27
ms.topic: concept
author: devopsabcs-engineering
keywords:
  - power-bi
  - dashboard
  - finops
  - compliance
  - visualization
---

## Overview

The FinOps compliance dashboard extends the existing AdvSecReport with 6 new pages focused on cost governance.
Each page is designed to answer specific questions about Azure cost compliance across the 5 demo app repositories.

## Color Scheme

Use a consistent color palette across all dashboard pages:

| Element | Color | Hex Code | Usage |
|---------|-------|----------|-------|
| Error/Critical | Red | `#D13438` | Error-severity findings, over-budget items |
| Warning | Amber | `#FF8C00` | Warning-severity findings, approaching limits |
| Note/Info | Blue | `#0078D4` | Note-severity findings, informational items |
| Compliant/Fixed | Green | `#107C10` | Compliant resources, fixed findings |
| Background | White | `#FFFFFF` | Page background |
| Text Primary | Dark Gray | `#323130` | Primary text |
| Accent | Teal | `#008575` | KPI cards, headers |

## Page 1: FinOps Compliance by Repository

### Purpose

Provides a high-level view of FinOps compliance across all scanned repositories, showing the distribution
of findings by severity and the current state of remediation.

### Layout

| Position | Visual | Data Source | Size |
|----------|--------|-------------|------|
| Top-left | KPI card — Total Open | FinOpsAlerts | 1/4 width |
| Top-center-left | KPI card — Total Fixed | FinOpsAlerts | 1/4 width |
| Top-center-right | KPI card — Total Dismissed | FinOpsAlerts | 1/4 width |
| Top-right | KPI card — Compliance Rate | FinOpsAlerts | 1/4 width |
| Middle | Stacked bar chart — Severity by Repository | FinOpsAlerts | Full width |
| Bottom | Alert details table | FinOpsAlerts | Full width |

### Chart Specifications

**Stacked Bar Chart — Severity by Repository**

- X-axis: `repo_name`
- Y-axis: Count of alerts
- Legend: `severity` (error = red, warning = amber, note = blue)
- Sort: Descending by total alert count

**Alert Details Table**

- Columns: Repository, Rule ID, Severity, Tool, State, Created Date, Resource Name
- Conditional formatting: severity column color-coded
- Default sort: severity descending, then created_at descending

### DAX Measures

```dax
Total Open = CALCULATE(COUNTROWS(FinOpsAlerts), FinOpsAlerts[state] = "open")
Total Fixed = CALCULATE(COUNTROWS(FinOpsAlerts), FinOpsAlerts[state] = "fixed")
Total Dismissed = CALCULATE(COUNTROWS(FinOpsAlerts), FinOpsAlerts[state] = "dismissed")
Compliance Rate = DIVIDE([Total Fixed], [Total Fixed] + [Total Open] + [Total Dismissed])
```

### Filters

- Slicer: Tool Name (PSRule, Checkov, Cloud Custodian, Infracost)
- Slicer: Severity (error, warning, note)
- Slicer: Date Range (created_at)

## Page 2: Cost Trend Analysis

### Purpose

Shows how FinOps compliance changes over time, highlighting trends in new findings versus remediated findings.

### Layout

| Position | Visual | Data Source | Size |
|----------|--------|-------------|------|
| Top-left | KPI card — Current Open | FinOpsAlerts | 1/3 width |
| Top-center | KPI card — Fixed This Month | FinOpsAlerts | 1/3 width |
| Top-right | KPI card — Mean Time to Remediate | FinOpsAlerts | 1/3 width |
| Middle | Line chart — Open Alerts Over Time | FinOpsAlerts | Full width |
| Bottom | Area chart — New vs Fixed per Week | FinOpsAlerts | Full width |

### Chart Specifications

**Line Chart — Open Alerts Over Time**

- X-axis: Date (weekly granularity)
- Y-axis: Count of open alerts
- Lines: One per repository (or one combined)
- Add a moving average trendline (4-week window)

**Area Chart — New vs Fixed per Week**

- X-axis: Week start date
- Y-axis: Count of alerts
- Series 1: New alerts (red area)
- Series 2: Fixed alerts (green area)
- Overlap mode: transparent at 50% opacity

### DAX Measures

```dax
New Alerts This Week =
CALCULATE(
    COUNTROWS(FinOpsAlerts),
    DATESINPERIOD(FinOpsAlerts[created_at], TODAY(), -7, DAY)
)

Fixed This Week =
CALCULATE(
    COUNTROWS(FinOpsAlerts),
    DATESINPERIOD(FinOpsAlerts[fixed_at], TODAY(), -7, DAY),
    FinOpsAlerts[state] = "fixed"
)

Fixed This Month =
CALCULATE(
    COUNTROWS(FinOpsAlerts),
    DATESMTD(FinOpsAlerts[fixed_at]),
    FinOpsAlerts[state] = "fixed"
)

Mean Time to Remediate =
AVERAGEX(
    FILTER(FinOpsAlerts, [state] = "fixed"),
    DATEDIFF([created_at], [fixed_at], DAY)
)
```

### Filters

- Slicer: Date Range
- Slicer: Repository

## Page 3: Tagging Compliance

### Purpose

Evaluates how well Azure resources comply with the 7 required governance tags, displayed at the resource group level.

### Layout

| Position | Visual | Data Source | Size |
|----------|--------|-------------|------|
| Top-left | KPI card — Overall Tagging Compliance % | GovernanceTags | 1/3 width |
| Top-center | KPI card — Fully Compliant Resources | GovernanceTags | 1/3 width |
| Top-right | KPI card — Non-Compliant Resources | GovernanceTags | 1/3 width |
| Middle-left | Donut chart — Tagged vs Untagged % | GovernanceTags | 1/2 width |
| Middle-right | Matrix — Resource Group × Tag Key | GovernanceTags | 1/2 width |
| Bottom | Table — Non-compliant resources detail | GovernanceTags | Full width |

### Chart Specifications

**Donut Chart — Tagged vs Untagged**

- Values: Count of compliant (green) vs non-compliant (red) tag entries
- Center label: Overall compliance percentage

**Matrix — Resource Group × Tag Key**

- Rows: `resource_group`
- Columns: 7 tag keys (CostCenter, Owner, Environment, Application, Department, Project, ManagedBy)
- Values: Compliance icon (checkmark or X)
- Conditional formatting: green for present, red for missing

### DAX Measures

```dax
Overall Tagging Compliance =
DIVIDE(
    COUNTROWS(FILTER(GovernanceTags, [is_compliant] = TRUE())),
    COUNTROWS(GovernanceTags)
)

Fully Compliant Resources =
COUNTROWS(
    FILTER(
        SUMMARIZE(GovernanceTags, GovernanceTags[resource_id], "TagsPresent", COUNTROWS(GovernanceTags)),
        [TagsPresent] = 7
    )
)

Non-Compliant Resources =
COUNTROWS(
    FILTER(
        SUMMARIZE(GovernanceTags, GovernanceTags[resource_id], "TagsPresent",
            CALCULATE(COUNTROWS(FILTER(GovernanceTags, [is_compliant] = TRUE())))),
        [TagsPresent] < 7
    )
)
```

### Filters

- Slicer: Resource Group
- Slicer: Tag Key

## Page 4: Right-Sizing Recommendations

### Purpose

Displays resources identified as oversized by Cloud Custodian policies, with SKU recommendations and estimated savings.

### Layout

| Position | Visual | Data Source | Size |
|----------|--------|-------------|------|
| Top-left | KPI card — Total Recommendations | FinOpsAlerts | 1/3 width |
| Top-center | KPI card — Total Estimated Savings | FinOpsAlerts | 1/3 width |
| Top-right | KPI card — Avg Savings per Resource | FinOpsAlerts | 1/3 width |
| Middle | Table — Right-Sizing Details | FinOpsAlerts | Full width |
| Bottom | Bar chart — Savings by Resource Group | FinOpsAlerts | Full width |

### Chart Specifications

**Right-Sizing Details Table**

- Columns: Resource Name, Resource Group, Current SKU, Recommended SKU, Estimated Monthly Savings, Source Tool, Detection Date
- Sort: Estimated savings descending
- Conditional formatting: savings column with data bars

**Bar Chart — Savings by Resource Group**

- X-axis: `resource_group`
- Y-axis: Sum of `estimated_savings`
- Color: teal (`#008575`)

### DAX Measures

```dax
Total Right-Sizing Recommendations =
CALCULATE(
    COUNTROWS(FinOpsAlerts),
    FinOpsAlerts[rule_id] = "FINOPS-006",
    FinOpsAlerts[state] = "open"
)

Total Estimated Savings =
CALCULATE(
    SUM(FinOpsAlerts[estimated_savings]),
    FinOpsAlerts[state] = "open"
)

Avg Savings Per Resource =
DIVIDE([Total Estimated Savings], [Total Right-Sizing Recommendations])
```

### Filters

- Slicer: Resource Group
- Slicer: Source Tool

## Page 5: Orphaned Resource Detection

### Purpose

Lists orphaned Azure resources detected by Cloud Custodian policies, showing their age, type, and estimated cost impact.

### Layout

| Position | Visual | Data Source | Size |
|----------|--------|-------------|------|
| Top-left | KPI card — Total Orphaned Resources | FinOpsAlerts | 1/3 width |
| Top-center | KPI card — Est. Monthly Waste | FinOpsAlerts | 1/3 width |
| Top-right | KPI card — Avg Age (Days) | FinOpsAlerts | 1/3 width |
| Middle | Table — Orphaned Resources | FinOpsAlerts | Full width |
| Bottom | Pie chart — Orphaned Resources by Type | FinOpsAlerts | Full width |

### Chart Specifications

**Orphaned Resources Table**

- Columns: Resource Name, Resource Type, Resource Group, Age (Days), Estimated Monthly Cost, Detection Date, Status
- Sort: Age descending
- Conditional formatting: age column (green < 30 days, amber 30–90, red > 90)

**Pie Chart — By Resource Type**

- Values: Count of orphaned resources by `resource_type`
- Display: percentages on labels

### DAX Measures

```dax
Total Orphaned Resources =
CALCULATE(
    COUNTROWS(FinOpsAlerts),
    FinOpsAlerts[rule_id] = "FINOPS-008",
    FinOpsAlerts[state] = "open"
)

Estimated Monthly Waste =
CALCULATE(
    SUM(FinOpsAlerts[estimated_savings]),
    FinOpsAlerts[rule_id] = "FINOPS-008",
    FinOpsAlerts[state] = "open"
)

Avg Orphan Age Days =
AVERAGEX(
    FILTER(FinOpsAlerts, [rule_id] = "FINOPS-008" && [state] = "open"),
    DATEDIFF([created_at], TODAY(), DAY)
)
```

### Filters

- Slicer: Resource Type
- Slicer: Resource Group

## Page 6: Budget vs Actual Spend

### Purpose

Compares budgeted versus actual Azure spending by department and month,
highlighting variances and trends.

### Layout

| Position | Visual | Data Source | Size |
|----------|--------|-------------|------|
| Top-left | KPI card — Total Budget | CostData | 1/3 width |
| Top-center | KPI card — Total Actual Spend | CostData | 1/3 width |
| Top-right | KPI card — Variance % | CostData | 1/3 width |
| Middle | Waterfall chart — Spend by Department | CostData | Full width |
| Bottom | Clustered column chart — Budget vs Actual by Month | CostData | Full width |

### Chart Specifications

**Waterfall Chart — Spend by Department**

- Category: Department (from resource tags)
- Values: Total actual spend per department
- Breakdown: Positive increases as dark blue, negative as light blue
- Total bar at the end

**Clustered Column Chart — Budget vs Actual by Month**

- X-axis: Month
- Y-axis: Cost (USD)
- Series 1: Budget (blue outline)
- Series 2: Actual (solid fill, green if under budget, red if over)
- Add variance percentage as data labels

### DAX Measures

```dax
Total Actual Spend =
SUM(CostData[cost])

Budget Variance =
[Total Actual Spend] - [Total Budget]

Variance Percent =
DIVIDE([Budget Variance], [Total Budget])

Monthly Spend =
CALCULATE(
    SUM(CostData[cost]),
    DATESMTD(CostData[date])
)
```

> **Note:** Budget data must be manually entered or imported from an Azure Budget export.
> The `Total Budget` measure references a Budget table not included in the automated data pipeline.

### Filters

- Slicer: Department
- Slicer: Month/Year
- Slicer: Subscription

## Filter Interactions Between Pages

All pages share the following cross-filter behaviors:

| Source Visual | Target Visual | Interaction |
|--------------|---------------|-------------|
| Repository slicer | All visuals on page | Filter |
| Severity slicer | Charts and tables | Filter |
| Date range slicer | Time-based charts | Filter |
| Bar chart click | Details table | Cross-highlight |
| KPI card | No interaction | None (display only) |

Pages use **bidirectional cross-filtering** sparingly — only the Repositories dimension enables cross-page
drill-through from any page to the Compliance by Repository page for detailed investigation.

## Drill-Through Configuration

Enable drill-through from any page to **Page 1 (Compliance by Repository)**:

- Drill-through field: `repo_name`
- Right-click on any repository in a chart → **Drill through > Compliance by Repository**
- The target page filters to show only the selected repository's alerts
