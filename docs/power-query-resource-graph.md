---
title: "Power Query — Azure Resource Graph (Tagging Compliance)"
description: "KQL query and Power Query M expression for pulling Azure resource tagging data from Azure Resource Graph into Power BI."
ms.date: 2026-03-27
ms.topic: how-to
author: devopsabcs-engineering
keywords:
  - power-query
  - azure-resource-graph
  - tagging
  - compliance
  - kql
---

## Overview

This guide describes how to connect Power BI to Azure Resource Graph to retrieve resource tagging compliance data.
The query targets resources in the `rg-finops-demo-*` resource groups and evaluates each resource against the
7 required governance tags defined in the FinOps governance policy.

## Required Governance Tags

The FinOps governance policy requires the following 7 tags on every Azure resource:

| Tag Key | Description | Example Value |
| --------- | ------------- | --------------- |
| CostCenter | Financial cost center code | `CC-12345` |
| Owner | Team or individual owner | `platform-team` |
| Environment | Deployment environment | `dev`, `staging`, `prod` |
| Application | Application name | `finops-demo-app-001` |
| Department | Organizational department | `Engineering` |
| Project | Project name | `FinOps Scanner` |
| ManagedBy | Management tool or team | `Bicep` |

## KQL Query for Azure Resource Graph

This KQL query retrieves all resources in the FinOps demo resource groups along with their tag values
and calculates a compliance percentage based on how many of the 7 required tags are present.

```kusto
resources
| where resourceGroup startswith "rg-finops-demo-"
| project id, name, type, resourceGroup, location,
    CostCenter = tags.CostCenter,
    Owner = tags.Owner,
    Environment = tags.Environment,
    Application = tags.Application,
    Department = tags.Department,
    Project = tags.Project,
    ManagedBy = tags.ManagedBy
| extend TagCount = toint(isnotnull(CostCenter)) + toint(isnotnull(Owner)) + toint(isnotnull(Environment))
    + toint(isnotnull(Application)) + toint(isnotnull(Department)) + toint(isnotnull(Project))
    + toint(isnotnull(ManagedBy))
| extend CompliancePercent = round(TagCount * 100.0 / 7, 1)
```

### Query Output Columns

| Column | Type | Description |
| -------- | ------ | ------------- |
| id | string | Azure resource ID |
| name | string | Resource name |
| type | string | Azure resource type (e.g., `Microsoft.Web/sites`) |
| resourceGroup | string | Resource group name |
| location | string | Azure region |
| CostCenter | string | CostCenter tag value (null if missing) |
| Owner | string | Owner tag value (null if missing) |
| Environment | string | Environment tag value (null if missing) |
| Application | string | Application tag value (null if missing) |
| Department | string | Department tag value (null if missing) |
| Project | string | Project tag value (null if missing) |
| ManagedBy | string | ManagedBy tag value (null if missing) |
| TagCount | int | Number of required tags present (0–7) |
| CompliancePercent | real | Percentage of required tags present |

## Power Query M Expression

### Prerequisites

- Azure AD account with **Reader** access to the target subscription
- Power BI Desktop configured with Azure AD authentication

### Azure Resource Graph REST API Query

```powerquery
let
    SubscriptionId = Excel.CurrentWorkbook(){[Name="AzureSubscriptionId"]}[Content]{0}[Column1],
    KqlQuery = "resources | where resourceGroup startswith 'rg-finops-demo-' | project id, name, type, resourceGroup, location, CostCenter = tags.CostCenter, Owner = tags.Owner, Environment = tags.Environment, Application = tags.Application, Department = tags.Department, Project = tags.Project, ManagedBy = tags.ManagedBy | extend TagCount = toint(isnotnull(CostCenter)) + toint(isnotnull(Owner)) + toint(isnotnull(Environment)) + toint(isnotnull(Application)) + toint(isnotnull(Department)) + toint(isnotnull(Project)) + toint(isnotnull(ManagedBy)) | extend CompliancePercent = round(TagCount * 100.0 / 7, 1)",
    RequestBody = Json.FromValue([
        subscriptions = {SubscriptionId},
        query = KqlQuery
    ]),
    Source = Json.Document(
        Web.Contents(
            "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01",
            [
                Headers = [
                    #"Content-Type" = "application/json"
                ],
                Content = RequestBody
            ]
        )
    ),
    Data = Source[data],
    Columns = Source[columns],
    ColumnNames = List.Transform(Columns, each [name]),
    ToTable = Table.FromRows(Data, ColumnNames),
    TypedColumns = Table.TransformColumnTypes(ToTable, {
        {"TagCount", Int64.Type},
        {"CompliancePercent", type number}
    })
in
    TypedColumns
```

### Azure Token Acquisition

Power BI handles Azure AD token acquisition automatically when using the **Organizational account** authentication method:

1. In Power BI Desktop, go to **File > Options and settings > Data source settings**
2. Select the Azure Resource Graph endpoint
3. Choose **Organizational account** and sign in with your Azure AD credentials
4. Power BI automatically acquires and refreshes OAuth2 tokens

For service principal authentication (automated refresh in Power BI Service):

1. Register an Azure AD application with **Reader** role on the target subscription
2. Configure the app registration in Power BI Service data source credentials
3. Use client credentials flow for unattended refresh

## Transform to GovernanceTags Dimension Table

To convert the flat query output into the `GovernanceTags` dimension table (one row per resource-tag pair):

```powerquery
let
    Source = ResourceGraphQuery,  // Reference the query above
    TagColumns = {"CostCenter", "Owner", "Environment", "Application", "Department", "Project", "ManagedBy"},
    Unpivoted = Table.UnpivotOtherColumns(
        Table.SelectColumns(Source, {"id", "name", "resourceGroup", "type"} & TagColumns),
        TagColumns,
        "tag_key",
        "tag_value"
    ),
    AddCompliance = Table.AddColumn(Unpivoted, "is_compliant", each [tag_value] <> null and [tag_value] <> ""),
    Renamed = Table.RenameColumns(AddCompliance, {
        {"id", "resource_id"},
        {"name", "resource_name"},
        {"type", "resource_type"}
    })
in
    Renamed
```

## Refresh Schedule

Align the Resource Graph refresh with the FinOps scan schedule:

| Schedule                 | Frequency                     | Notes                           |
| ------------------------ | ----------------------------- | ------------------------------- |
| Resource Graph query     | Weekly (Sunday 5:00 AM UTC)   | After scan pipeline completes   |
| Tag changes              | As needed                     | Tags update when Bicep deploys  |
