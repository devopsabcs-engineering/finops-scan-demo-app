---
title: "FinOps Toolkit Integration Guide"
description: "Setup guide for integrating Microsoft FinOps Toolkit v13, Azure FOCUS cost exports, and Power BI templates with the FinOps compliance dashboard."
ms.date: 2026-03-27
ms.topic: how-to
author: devopsabcs-engineering
keywords:
  - finops-toolkit
  - focus
  - cost-management
  - power-bi
  - azure
---

## Overview

The Microsoft FinOps Toolkit provides Power BI templates and utilities for visualizing Azure cost data
using the FinOps Open Cost and Usage Specification (FOCUS) format. This guide explains how to integrate
the FinOps Toolkit with the FinOps compliance dashboard to combine cost governance scanning results
with actual Azure spending data.

## Architecture

The FinOps compliance dashboard uses two data pipelines:

1. **GitHub Code Scanning API** — FinOps scan results (PSRule, Checkov, Cloud Custodian, Infracost)
2. **Azure FOCUS export → FinOps Toolkit** — Actual cost data from Azure Cost Management

These pipelines feed into a unified Power BI data model described in the
[data model documentation](power-bi-data-model.md).

## Prerequisites

- Azure subscription with **Cost Management Reader** role (or higher)
- Azure Storage account for FOCUS export data (created automatically by Cost Management)
- Power BI Desktop (latest version)
- Microsoft FinOps Toolkit v13

## Step 1: Enable FOCUS Export in Azure Cost Management

### Azure Portal Steps

1. Navigate to **Azure portal > Cost Management + Billing**
2. Select your subscription scope
3. Go to **Cost Management > Exports**
4. Select **+ Add** to create a new export
5. Configure the export:

   | Setting | Value |
   |---------|-------|
   | Export name | `finops-focus-export` |
   | Export type | **FOCUS cost and usage** |
   | Frequency | **Daily** |
   | Start date | Current date |
   | Storage account | Select or create a storage account |
   | Container | `cost-exports` |
   | Directory | `focus` |

6. Select **Create**

### Verify Export

After the first export runs (within 24 hours), verify the data appears in the storage account:

```text
<storage-account>/cost-exports/focus/<date-range>/
```

The export produces Parquet files containing FOCUS-formatted cost data.

## Step 2: Install Microsoft FinOps Toolkit

### Download

Download the FinOps Toolkit Power BI templates from the official GitHub repository:

- **Repository**: [microsoft/finops-toolkit](https://github.com/microsoft/finops-toolkit)
- **Latest release**: v13
- **Template files**: `.pbit` files in the `src/power-bi/` directory

### Key Templates

| Template | Purpose |
|----------|---------|
| Cost summary | Monthly and daily cost views with category breakdowns |
| Cost optimization | Recommendations for reducing spending |
| Rate optimization | Reserved instance and savings plan analysis |
| Data ingestion | Power Query M patterns for FOCUS data |

## Step 3: Connect FOCUS Data to Power BI

### Option A: Direct Storage Account Connection

1. Open Power BI Desktop
2. Select **Get Data > Azure > Azure Blob Storage**
3. Enter the storage account URL
4. Authenticate with your Azure credentials
5. Navigate to the `cost-exports/focus/` container
6. Select the Parquet files
7. Load and transform as needed

### Option B: Use FinOps Toolkit Power Query Templates

The FinOps Toolkit provides pre-built Power Query M expressions optimized for FOCUS data:

1. Open the FinOps Toolkit `.pbit` template
2. Enter your storage account connection string when prompted
3. The template automatically loads and transforms FOCUS data
4. Save as a `.pbix` file for ongoing use

### Power Query M Expression for FOCUS Data

```powerquery
let
    Source = AzureStorage.Blobs("https://<storage-account>.blob.core.windows.net"),
    CostExports = Source{[Name="cost-exports"]}[Data],
    FocusFolder = Table.SelectRows(CostExports, each Text.StartsWith([Name], "focus/")),
    FilterParquet = Table.SelectRows(FocusFolder, each Text.EndsWith([Name], ".parquet")),
    LatestFile = Table.Last(Table.Sort(FilterParquet, {"Date modified", Order.Descending})),
    ImportedData = Parquet.Document(LatestFile[Content])
in
    ImportedData
```

## Step 4: Map FOCUS Data to CostData Fact Table

Transform the FOCUS export columns to match the `CostData` fact table defined in the data model:

| FOCUS Column | CostData Column | Notes |
|-------------|-----------------|-------|
| `ResourceId` | `resource_id` | Azure resource ID |
| `ServiceName` | `service` | Azure service name |
| `BilledCost` | `cost` | Billed cost amount |
| `ChargePeriodStart` | `date` | Date of the charge |
| `ResourceGroupName` | `resource_group` | Resource group name |
| `SubAccountId` | `subscription_id` | Subscription ID |
| `MeterCategory` | `meter_category` | Meter category |
| `BillingCurrency` | `currency` | Currency code |

## Step 5: Configure Data Refresh Schedule

Align the cost data refresh with the FinOps scan pipeline schedule:

| Data Source | Refresh Frequency | Timing |
|------------|-------------------|--------|
| FOCUS export (Azure) | Daily | Automatically exported by Azure Cost Management |
| GitHub Code Scanning API | Weekly | Sunday 6:00 AM UTC (after scan pipeline) |
| Azure Resource Graph | Weekly | Sunday 5:00 AM UTC (after scan pipeline) |
| Power BI dataset | Weekly | Sunday 7:00 AM UTC (after all sources refresh) |

### Configure in Power BI Service

1. Publish the `.pbix` file to Power BI Service
2. Navigate to **Workspace > Dataset settings**
3. Under **Data source credentials**, configure authentication for each source
4. Under **Scheduled refresh**, set the refresh schedule to weekly
5. Enable **Send refresh failure notifications** to the dataset owner

## Additional Resources

- [Microsoft FinOps Toolkit GitHub repository](https://github.com/microsoft/finops-toolkit)
- [FinOps Toolkit documentation](https://aka.ms/finops/toolkit)
- [FOCUS specification](https://focus.finops.org/)
- [Azure Cost Management FOCUS export documentation](https://learn.microsoft.com/azure/cost-management-billing/costs/tutorial-export-acm-data)
- [FinOps Framework](https://www.finops.org/framework/)
