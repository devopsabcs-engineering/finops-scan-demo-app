---
title: "FinOps Power BI Implementation Guide"
description: "Consolidated implementation-ready design document for adding FinOps compliance pages to the AdvSecReport Power BI project, including semantic model definitions, DAX measures, Power Query M expressions, and report page layouts."
ms.date: 2026-03-30
ms.topic: reference
author: devopsabcs-engineering
keywords:
  - power-bi
  - finops
  - compliance
  - semantic-model
  - tmdl
  - pbip
  - dashboard
  - governance
---

## Overview

This document provides a complete implementation specification for adding FinOps compliance pages to the existing `AdvSecReport.pbip` Power BI project. Rather than creating a standalone report, the FinOps pages extend the shared semantic model and report definition that already serves Security and Accessibility domains.

The integration relies on the shared `Repositories` dimension table, which includes a `scan_domain` column (`"Security"`, `"Accessibility"`, `"FinOps"`) enabling cross-domain analysis within a single report. This approach mirrors how the `accessibility_compliance` page was added alongside the original security pages.

### Data Sources

The FinOps pages consume data from three pipelines:

1. GitHub Code Scanning API: FinOps scan results from PSRule, Checkov, Cloud Custodian, and Infracost (uploaded as SARIF)
2. Azure Resource Graph: Resource tagging compliance data via KQL
3. Azure FOCUS export: Standardized cost data via the Microsoft FinOps Toolkit v13

### Architecture

```text
Scanner Pipeline (GitHub Actions / ADO Pipeline)
    ├── Checkov        → SARIF → Upload to Code Scanning
    ├── PSRule         → SARIF → Upload to Code Scanning
    ├── Cloud Custodian → JSON → custodian-to-sarif.py → SARIF → Upload
    └── Infracost       → JSON → infracost-to-sarif.py → SARIF → Upload

GitHub Code Scanning API ──→ Power Query M ──→ FinOpsAlerts (fact)
Azure Resource Graph    ──→ Power Query M ──→ GovernanceTags (dimension)
Azure FOCUS Export      ──→ Power Query M ──→ CostData (fact)
Static Data             ──→ TMDL          ──→ ScanTools (dimension)
```

## Semantic Model Additions

The FinOps extension adds 4 new tables to the existing `AdvSecReport.SemanticModel`. All tables connect to the shared `Repositories` dimension through `repo_name`.

### Entity-Relationship Diagram

```text
┌─────────────┐       ┌──────────────┐       ┌──────────────┐
│ ScanTools   │──┐    │ Repositories │    ┌──│ GovernanceTags│
│ (dimension) │  │    │  (shared)    │    │  │ (dimension)  │
└─────────────┘  │    └──────────────┘    │  └──────────────┘
                 │           │            │         │
                 ▼           ▼            │         ▼
            ┌──────────────────┐         │  ┌──────────────┐
            │   FinOpsAlerts   │         │  │   CostData   │
            │     (fact)       │         │  │    (fact)     │
            └──────────────────┘         │  └──────────────┘
                                         │         │
                                         └─────────┘
                                      (resource_id join)
```

### Relationships

| From Table | From Column | To Table | To Column | Cardinality | Cross-Filter |
| --- | --- | --- | --- | --- | --- |
| FinOpsAlerts | repo_name | Repositories | repo_name | Many-to-One | Single |
| FinOpsAlerts | tool_name | ScanTools | tool_name | Many-to-One | Single |
| CostData | resource_id | GovernanceTags | resource_id | Many-to-Many | Single |
| GovernanceTags | resource_group | CostData | resource_group | Many-to-One | Single |

### Table 1: FinOpsAlerts (Fact)

Source: GitHub Code Scanning API (all 4 FinOps scanner tools)

#### FinOpsAlerts TMDL Definition

```tmdl
table FinOpsAlerts

    column alert_id
        dataType: int64
        isHidden: false
        formatString: 0
        summarizeBy: none
        sourceColumn: alert_id
        sortByColumn: alert_id

    column repo_name
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: repo_name

    column rule_id
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: rule_id

    column severity
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: severity
        sortByColumn: severity_order

    column severity_order
        dataType: int64
        isHidden: true
        summarizeBy: none
        sourceColumn: severity_order

    column state
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: state

    column tool_name
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: tool_name

    column estimated_savings
        dataType: decimal
        isHidden: false
        formatString: "$#,##0.00"
        summarizeBy: sum
        sourceColumn: estimated_savings

    column resource_name
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: resource_name

    column created_at
        dataType: dateTime
        isHidden: false
        formatString: yyyy-MM-dd
        summarizeBy: none
        sourceColumn: created_at

    column fixed_at
        dataType: dateTime
        isHidden: false
        formatString: yyyy-MM-dd
        summarizeBy: none
        sourceColumn: fixed_at

    partition FinOpsAlerts = m
        mode: import
        source =
            let
                Source = FinOpsAlertsQuery
            in
                Source
```

#### FinOpsAlerts Column Reference

| Column | Data Type | Format | Sort By | Description |
| --- | --- | --- | --- | --- |
| alert_id | Int64 | `0` | alert_id | GitHub alert number (unique per repo) |
| repo_name | String | | | FK to `Repositories` |
| rule_id | String | | | SARIF rule ID (e.g., `FINOPS-TAG-001`, `CKV_AZURE_35`) |
| severity | String | | severity_order | Alert severity: `error`, `warning`, `note` |
| severity_order | Int64 (hidden) | | | Sort key: error=1, warning=2, note=3 |
| state | String | | | Alert state: `open`, `fixed`, `dismissed` |
| tool_name | String | | | FK to `ScanTools` |
| estimated_savings | Decimal | `$#,##0.00` | | Estimated monthly savings in USD |
| resource_name | String | | | Azure resource name |
| created_at | DateTime | `yyyy-MM-dd` | | Alert creation timestamp |
| fixed_at | DateTime | `yyyy-MM-dd` | | Alert resolution timestamp (null if open) |

### Table 2: ScanTools (Dimension)

Source: Static data (entered directly in TMDL)

#### ScanTools TMDL Definition

```tmdl
table ScanTools

    column tool_name
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: tool_name
        isKey: true

    column tool_display_name
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: tool_display_name

    column tool_version
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: tool_version

    column scan_domain
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: scan_domain

    column tool_description
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: tool_description

    partition ScanTools = m
        mode: import
        source =
            let
                Source = Table.FromRows(
                    {
                        {"PSRule", "PSRule", "2.9.0", "FinOps", "Azure Well-Architected Framework rules for IaC"},
                        {"Checkov", "Checkov", "3.2", "FinOps", "Policy-as-code for IaC security and compliance"},
                        {"custodian-to-sarif", "Cloud Custodian", "1.0.0", "FinOps", "Cloud Custodian runtime governance policies"},
                        {"infracost-to-sarif", "Infracost", "1.0.0", "FinOps", "Infrastructure cost estimation and optimization"}
                    },
                    type table [
                        tool_name = text,
                        tool_display_name = text,
                        tool_version = text,
                        scan_domain = text,
                        tool_description = text
                    ]
                )
            in
                Source
```

#### Static Data

| tool_name | tool_display_name | tool_version | scan_domain | tool_description |
| --- | --- | --- | --- | --- |
| PSRule | PSRule | 2.9.0 | FinOps | Azure Well-Architected Framework rules for IaC |
| Checkov | Checkov | 3.2 | FinOps | Policy-as-code for IaC security and compliance |
| custodian-to-sarif | Cloud Custodian | 1.0.0 | FinOps | Cloud Custodian runtime governance policies |
| infracost-to-sarif | Infracost | 1.0.0 | FinOps | Infrastructure cost estimation and optimization |

### Table 3: GovernanceTags (Dimension)

Source: Azure Resource Graph (KQL query targeting `rg-finops-demo-*` resource groups)

#### GovernanceTags TMDL Definition

```tmdl
table GovernanceTags

    column resource_id
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: resource_id

    column resource_name
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: resource_name

    column resource_group
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: resource_group

    column resource_type
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: resource_type

    column tag_key
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: tag_key

    column tag_value
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: tag_value

    column compliance_status
        dataType: boolean
        isHidden: false
        summarizeBy: none
        sourceColumn: compliance_status

    partition GovernanceTags = m
        mode: import
        source =
            let
                Source = GovernanceTagsQuery
            in
                Source
```

#### GovernanceTags Column Reference

| Column | Data Type | Description |
| --- | --- | --- |
| resource_id | String | Azure resource ID |
| resource_name | String | Azure resource display name |
| resource_group | String | Resource group name |
| resource_type | String | Azure resource type (e.g., `Microsoft.Web/sites`) |
| tag_key | String | One of the 7 required tag names |
| tag_value | String | Tag value (null if tag is missing) |
| compliance_status | Boolean | `true` if tag is present and valid, `false` otherwise |

The 7 required governance tags evaluated per resource:

| # | Tag Key | Format Rule |
| --- | --- | --- |
| 1 | CostCenter | Must match `CC-\d{4,6}` |
| 2 | Owner | Must be a valid email address |
| 3 | Environment | Must be one of: `dev`, `staging`, `prod`, `shared` |
| 4 | Application | Must not be empty |
| 5 | Department | Must not be empty |
| 6 | Project | Must not be empty |
| 7 | ManagedBy | Must not be empty |

### Table 4: CostData (Fact)

Source: Azure FOCUS export via Cost Management (Parquet files in Blob Storage)

#### CostData TMDL Definition

```tmdl
table CostData

    column resource_id
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: resource_id

    column charge_period
        dataType: dateTime
        isHidden: false
        formatString: yyyy-MM-dd
        summarizeBy: none
        sourceColumn: charge_period

    column billed_cost
        dataType: decimal
        isHidden: false
        formatString: "$#,##0.00"
        summarizeBy: sum
        sourceColumn: billed_cost

    column service
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: service

    column department
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: department

    column resource_group
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: resource_group

    column subscription_id
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: subscription_id

    column currency
        dataType: string
        isHidden: false
        summarizeBy: none
        sourceColumn: currency

    partition CostData = m
        mode: import
        source =
            let
                Source = CostDataQuery
            in
                Source
```

#### CostData Column Reference

| Column | Data Type | Format | Description |
| --- | --- | --- | --- |
| resource_id | String | | Azure resource ID |
| charge_period | DateTime | `yyyy-MM-dd` | Date of the charge |
| billed_cost | Decimal | `$#,##0.00` | Billed cost amount |
| service | String | | Azure service name |
| department | String | | Department from resource tags |
| resource_group | String | | Resource group name |
| subscription_id | String | | Azure subscription ID |
| currency | String | | Billing currency code (e.g., USD) |

#### FOCUS Column Mapping

| FOCUS Export Column | CostData Column |
| --- | --- |
| ResourceId | resource_id |
| ChargePeriodStart | charge_period |
| BilledCost | billed_cost |
| ServiceName | service |
| ResourceGroupName | resource_group |
| SubAccountId | subscription_id |
| BillingCurrency | currency |

The `department` column is derived from the `Department` tag on each resource. If the tag is missing, the value defaults to `"Untagged"`.

## DAX Measures

All measures are defined on the `FinOpsAlerts` table unless otherwise noted. Each measure includes the table context for clarity.

### Core Alert Measures

```dax
Total Open =
CALCULATE(
    COUNTROWS(FinOpsAlerts),
    FinOpsAlerts[state] = "open"
)

Total Fixed =
CALCULATE(
    COUNTROWS(FinOpsAlerts),
    FinOpsAlerts[state] = "fixed"
)

Total Dismissed =
CALCULATE(
    COUNTROWS(FinOpsAlerts),
    FinOpsAlerts[state] = "dismissed"
)

Compliance Rate =
DIVIDE(
    [Total Fixed],
    [Total Fixed] + [Total Open] + [Total Dismissed],
    0
)
```

### Cost Measures

```dax
Cost Savings Potential =
CALCULATE(
    SUM(FinOpsAlerts[estimated_savings]),
    FinOpsAlerts[state] = "open"
)

Total Estimated Savings =
CALCULATE(
    SUM(FinOpsAlerts[estimated_savings]),
    FinOpsAlerts[state] = "open"
)

Avg Savings Per Resource =
DIVIDE(
    [Total Estimated Savings],
    CALCULATE(
        COUNTROWS(FinOpsAlerts),
        FinOpsAlerts[state] = "open",
        NOT ISBLANK(FinOpsAlerts[estimated_savings])
    ),
    0
)

Total Actual Spend =
SUM(CostData[billed_cost])

Monthly Spend =
CALCULATE(
    SUM(CostData[billed_cost]),
    DATESMTD(CostData[charge_period])
)

Budget Variance =
[Total Actual Spend] - [Total Budget]

Variance Percent =
DIVIDE([Budget Variance], [Total Budget], 0)
```

> The `Total Budget` measure references a Budget table that must be manually created or imported from an Azure Budget export. This table is not part of the automated data pipeline.

### Tagging Compliance Measures

```dax
Tagging Compliance =
DIVIDE(
    COUNTROWS(FILTER(GovernanceTags, GovernanceTags[compliance_status] = TRUE())),
    COUNTROWS(GovernanceTags),
    0
)

Fully Compliant Resources =
COUNTROWS(
    FILTER(
        SUMMARIZE(
            GovernanceTags,
            GovernanceTags[resource_id],
            "CompliantTags",
            CALCULATE(
                COUNTROWS(
                    FILTER(GovernanceTags, GovernanceTags[compliance_status] = TRUE())
                )
            )
        ),
        [CompliantTags] = 7
    )
)

Non-Compliant Resources =
COUNTROWS(
    FILTER(
        SUMMARIZE(
            GovernanceTags,
            GovernanceTags[resource_id],
            "CompliantTags",
            CALCULATE(
                COUNTROWS(
                    FILTER(GovernanceTags, GovernanceTags[compliance_status] = TRUE())
                )
            )
        ),
        [CompliantTags] < 7
    )
)
```

### Time-Based Measures

```dax
Mean Time to Remediate =
AVERAGEX(
    FILTER(FinOpsAlerts, FinOpsAlerts[state] = "fixed"),
    DATEDIFF(FinOpsAlerts[created_at], FinOpsAlerts[fixed_at], DAY)
)

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
```

### Severity Measures

```dax
Critical Findings =
COUNTROWS(
    FILTER(FinOpsAlerts, FinOpsAlerts[severity] = "error")
)

Warning Findings =
COUNTROWS(
    FILTER(FinOpsAlerts, FinOpsAlerts[severity] = "warning")
)

Note Findings =
COUNTROWS(
    FILTER(FinOpsAlerts, FinOpsAlerts[severity] = "note")
)
```

### Orphaned Resource Measures

```dax
Total Orphaned Resources =
CALCULATE(
    COUNTROWS(FinOpsAlerts),
    FinOpsAlerts[rule_id] = "FINOPS-ORPHAN-001"
        || FinOpsAlerts[rule_id] = "FINOPS-ORPHAN-002"
        || FinOpsAlerts[rule_id] = "FINOPS-ORPHAN-003",
    FinOpsAlerts[state] = "open"
)

Estimated Monthly Waste =
CALCULATE(
    SUM(FinOpsAlerts[estimated_savings]),
    FinOpsAlerts[rule_id] = "FINOPS-ORPHAN-001"
        || FinOpsAlerts[rule_id] = "FINOPS-ORPHAN-002"
        || FinOpsAlerts[rule_id] = "FINOPS-ORPHAN-003",
    FinOpsAlerts[state] = "open"
)

Avg Orphan Age Days =
AVERAGEX(
    FILTER(
        FinOpsAlerts,
        (FinOpsAlerts[rule_id] = "FINOPS-ORPHAN-001"
            || FinOpsAlerts[rule_id] = "FINOPS-ORPHAN-002"
            || FinOpsAlerts[rule_id] = "FINOPS-ORPHAN-003")
        && FinOpsAlerts[state] = "open"
    ),
    DATEDIFF(FinOpsAlerts[created_at], TODAY(), DAY)
)
```

### Right-Sizing Measures

```dax
Total Right-Sizing Recommendations =
CALCULATE(
    COUNTROWS(FinOpsAlerts),
    FinOpsAlerts[rule_id] = "FINOPS-SIZE-001"
        || FinOpsAlerts[rule_id] = "FINOPS-SIZE-002",
    FinOpsAlerts[state] = "open"
)
```

## Power Query M Expressions

Four Power Query M expressions load data into the semantic model. Each query is defined as a named expression in `expressions.tmdl` or as the partition source for its respective table.

### Parameters

Define these parameters in `expressions.tmdl`:

```tmdl
expression GitHubToken =
    ""
    metadata [IsParameterQuery = true, Type = "Text", IsParameterQueryRequired = true]

expression AzureSubscriptionId =
    ""
    metadata [IsParameterQuery = true, Type = "Text", IsParameterQueryRequired = true]

expression StorageAccountName =
    ""
    metadata [IsParameterQuery = true, Type = "Text", IsParameterQueryRequired = true]
```

### Query 1: FinOpsAlerts (GitHub Code Scanning API)

Retrieves FinOps scan results from the GitHub Code Scanning API using PAT authentication. Queries all 4 scanner tools and combines results into a single table.

```m
let
    GetAlertsByTool = (toolName as text) =>
        let
            Token = GitHubToken,
            BaseUrl = "https://api.github.com/orgs/devopsabcs-engineering/code-scanning/alerts",
            Source = Json.Document(
                Web.Contents(
                    BaseUrl,
                    [
                        Headers = [
                            #"Authorization" = "Bearer " & Token,
                            #"Accept" = "application/vnd.github+json",
                            #"X-GitHub-Api-Version" = "2022-11-28"
                        ],
                        Query = [
                            tool_name = toolName,
                            per_page = "100"
                        ]
                    ]
                )
            ),
            ToTable = Table.FromList(Source, Splitter.SplitByNothing()),
            Expanded = Table.ExpandRecordColumn(ToTable, "Column1", {
                "number", "rule", "tool", "state", "most_recent_instance",
                "created_at", "fixed_at", "repository"
            }),
            ExpandedRule = Table.ExpandRecordColumn(Expanded, "rule", {
                "id", "severity", "description"
            }, {"rule_id", "severity", "rule_description"}),
            ExpandedTool = Table.ExpandRecordColumn(ExpandedRule, "tool", {
                "name", "version"
            }, {"tool_name", "tool_version"}),
            ExpandedRepo = Table.ExpandRecordColumn(ExpandedTool, "repository", {
                "name", "full_name"
            }, {"repo_name", "repo_full_name"}),
            ExpandedInstance = Table.ExpandRecordColumn(ExpandedRepo, "most_recent_instance", {
                "location", "message"
            }, {"location", "message"}),
            TypedDates = Table.TransformColumnTypes(ExpandedInstance, {
                {"created_at", type datetimezone},
                {"fixed_at", type datetimezone}
            }),
            Renamed = Table.RenameColumns(TypedDates, {{"number", "alert_id"}}),
            AddSeverityOrder = Table.AddColumn(Renamed, "severity_order", each
                if [severity] = "error" then 1
                else if [severity] = "warning" then 2
                else 3,
                Int64.Type
            ),
            AddEstimatedSavings = Table.AddColumn(AddSeverityOrder, "estimated_savings", each
                if [tool_name] = "infracost-to-sarif" then
                    try Number.FromText(
                        Text.BetweenDelimiters([message], "$", "/month")
                    ) otherwise null
                else null,
                type number
            ),
            ExtractResourceName = Table.AddColumn(AddEstimatedSavings, "resource_name", each
                try Text.AfterDelimiter([location], "/providers/", {0, RelativePosition.FromEnd})
                otherwise [repo_name],
                type text
            ),
            SelectColumns = Table.SelectColumns(ExtractResourceName, {
                "alert_id", "repo_name", "rule_id", "severity", "severity_order",
                "state", "tool_name", "estimated_savings", "resource_name",
                "created_at", "fixed_at"
            })
        in
            SelectColumns,

    Tools = {"PSRule", "Checkov", "custodian-to-sarif", "infracost-to-sarif"},
    ToolTable = Table.FromList(Tools, Splitter.SplitByNothing(), {"ToolName"}),
    Results = Table.AddColumn(ToolTable, "Alerts", each GetAlertsByTool([ToolName])),
    Combined = Table.ExpandTableColumn(
        Results, "Alerts",
        {"alert_id", "repo_name", "rule_id", "severity", "severity_order",
         "state", "tool_name", "estimated_savings", "resource_name",
         "created_at", "fixed_at"}
    ),
    RemoveToolColumn = Table.RemoveColumns(Combined, {"ToolName"})
in
    RemoveToolColumn
```

Authentication: The `GitHubToken` parameter stores a GitHub PAT with the `security_events` scope for the `devopsabcs-engineering` organization. The data source privacy level should be set to `Organizational`. A pre-commit hook in the ADvSec repo blocks commits containing non-empty token values.

Pagination: The GitHub Code Scanning API returns a maximum of 100 results per page. For the 5 demo apps with 4 tools, pagination is unlikely to be required. If scaling beyond this, implement the `Link` header pagination pattern described in the [GitHub API documentation](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api).

### Query 2: GovernanceTags (Azure Resource Graph)

Queries Azure Resource Graph for resources in `rg-finops-demo-*` resource groups and evaluates each resource against the 7 required governance tags.

#### KQL Query

```kql
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
| extend TagCount = toint(isnotnull(CostCenter)) + toint(isnotnull(Owner))
    + toint(isnotnull(Environment)) + toint(isnotnull(Application))
    + toint(isnotnull(Department)) + toint(isnotnull(Project))
    + toint(isnotnull(ManagedBy))
| extend CompliancePercent = round(TagCount * 100.0 / 7, 1)
```

#### Power Query M Expression

```m
let
    SubscriptionId = AzureSubscriptionId,
    KqlQuery = "resources | where resourceGroup startswith 'rg-finops-demo-' | project id, name, type, resourceGroup, location, CostCenter = tags.CostCenter, Owner = tags.Owner, Environment = tags.Environment, Application = tags.Application, Department = tags.Department, Project = tags.Project, ManagedBy = tags.ManagedBy | extend TagCount = toint(isnotnull(CostCenter)) + toint(isnotnull(Owner)) + toint(isnotnull(Environment)) + toint(isnotnull(Application)) + toint(isnotnull(Department)) + toint(isnotnull(Project)) + toint(isnotnull(ManagedBy)) | extend CompliancePercent = round(TagCount * 100.0 / 7, 1)",
    RequestBody = Json.FromValue([
        subscriptions = {SubscriptionId},
        query = KqlQuery
    ]),
    Source = Json.Document(
        Web.Contents(
            "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01",
            [
                Headers = [#"Content-Type" = "application/json"],
                Content = RequestBody
            ]
        )
    ),
    Data = Source[data],
    Columns = Source[columns],
    ColumnNames = List.Transform(Columns, each [name]),
    FlatTable = Table.FromRows(Data, ColumnNames),
    TagColumns = {"CostCenter", "Owner", "Environment", "Application", "Department", "Project", "ManagedBy"},
    Unpivoted = Table.UnpivotOtherColumns(
        Table.SelectColumns(FlatTable, {"id", "name", "resourceGroup", "type"} & TagColumns),
        TagColumns,
        "tag_key",
        "tag_value"
    ),
    AddCompliance = Table.AddColumn(
        Unpivoted, "compliance_status",
        each [tag_value] <> null and [tag_value] <> "",
        type logical
    ),
    Renamed = Table.RenameColumns(AddCompliance, {
        {"id", "resource_id"},
        {"name", "resource_name"},
        {"type", "resource_type"},
        {"resourceGroup", "resource_group"}
    })
in
    Renamed
```

Authentication: Uses the Organizational account method in Power BI Desktop. Power BI acquires and refreshes OAuth2 tokens automatically. For unattended refresh in Power BI Service, configure a service principal with the Reader role on the target subscription.

### Query 3: CostData (Azure FOCUS Export)

Reads FOCUS-formatted cost data from Azure Blob Storage (Parquet files exported by Azure Cost Management).

```m
let
    AccountName = StorageAccountName,
    Source = AzureStorage.Blobs("https://" & AccountName & ".blob.core.windows.net"),
    CostExports = Source{[Name = "cost-exports"]}[Data],
    FocusFolder = Table.SelectRows(CostExports, each Text.StartsWith([Name], "focus/")),
    FilterParquet = Table.SelectRows(FocusFolder, each Text.EndsWith([Name], ".parquet")),
    SortByDate = Table.Sort(FilterParquet, {{"Date modified", Order.Descending}}),
    LatestFile = SortByDate{0},
    ImportedData = Parquet.Document(LatestFile[Content]),
    Mapped = Table.SelectColumns(ImportedData, {
        "ResourceId", "ChargePeriodStart", "BilledCost",
        "ServiceName", "ResourceGroupName", "SubAccountId", "BillingCurrency"
    }),
    Renamed = Table.RenameColumns(Mapped, {
        {"ResourceId", "resource_id"},
        {"ChargePeriodStart", "charge_period"},
        {"BilledCost", "billed_cost"},
        {"ServiceName", "service"},
        {"ResourceGroupName", "resource_group"},
        {"SubAccountId", "subscription_id"},
        {"BillingCurrency", "currency"}
    }),
    AddDepartment = Table.AddColumn(Renamed, "department", each
        let
            resId = [resource_id],
            tagMatch = try Table.SelectRows(GovernanceTags,
                each [resource_id] = resId and [tag_key] = "Department"
            ){0}[tag_value] otherwise "Untagged"
        in
            tagMatch,
        type text
    ),
    TypedColumns = Table.TransformColumnTypes(AddDepartment, {
        {"charge_period", type date},
        {"billed_cost", Currency.Type}
    })
in
    TypedColumns
```

Authentication: Uses the Storage account key or Organizational account in Power BI. The storage account URL is parameterized through the `StorageAccountName` parameter.

### Query 4: ADO Advanced Security API (Future Use)

This query is parameterized for future use when the data source transitions from GitHub Code Scanning to Azure DevOps Advanced Security. It mirrors the ADvSec report pattern.

```m
let
    OrgName = "MngEnvMCAP675646",
    ProjectName = "",  // Empty = all projects; set to specific project name to filter
    PatToken = "",     // ADO PAT with Advanced Security read scope
    BaseUrl = "https://advsec.dev.azure.com/" & OrgName,

    // Step 1: List projects (or use specific project)
    ProjectsUrl = "https://dev.azure.com/" & OrgName & "/_apis/projects?api-version=7.1",
    ProjectsResponse = Json.Document(
        Web.Contents(ProjectsUrl, [
            Headers = [
                #"Authorization" = "Basic " &
                    Binary.ToText(Text.ToBinary(":" & PatToken), BinaryEncoding.Base64)
            ]
        ])
    ),
    ProjectList = if ProjectName = "" then
        List.Transform(ProjectsResponse[value], each [name])
    else
        {ProjectName},

    // Step 2: For each project, list repositories
    GetReposForProject = (projName as text) =>
        let
            ReposUrl = "https://dev.azure.com/" & OrgName & "/" & projName
                & "/_apis/git/repositories?api-version=7.1",
            ReposResponse = Json.Document(
                Web.Contents(ReposUrl, [
                    Headers = [
                        #"Authorization" = "Basic " &
                            Binary.ToText(Text.ToBinary(":" & PatToken), BinaryEncoding.Base64)
                    ]
                ])
            )
        in
            List.Transform(ReposResponse[value], each [projName, repoId = [id], repoName = [name]]),

    // Step 3: For each repo, get alerts
    GetAlertsForRepo = (projName as text, repoId as text) =>
        let
            AlertsUrl = BaseUrl & "/" & projName
                & "/_apis/alert/repositories/" & repoId
                & "/alerts?api-version=7.2-preview.1",
            AlertsResponse = Json.Document(
                Web.Contents(AlertsUrl, [
                    Headers = [
                        #"Authorization" = "Basic " &
                            Binary.ToText(Text.ToBinary(":" & PatToken), BinaryEncoding.Base64)
                    ]
                ])
            )
        in
            AlertsResponse[value],

    // Placeholder: full implementation follows the ADvSec pattern
    // with pagination and alert expansion
    Output = #table(
        type table [
            alert_id = Int64.Type, repo_name = text, rule_id = text,
            severity = text, state = text, tool_name = text,
            estimated_savings = number, resource_name = text,
            created_at = datetimezone, fixed_at = datetimezone
        ],
        {}
    )
in
    Output
```

> This query is documented for reference. Activate it by replacing the `FinOpsAlertsQuery` partition source when the organization transitions to ADO Advanced Security as the primary scan results store.

## Report Pages

Six new pages extend the AdvSecReport. Each page follows the ADvSec accessibility page layout pattern: header bar, main chart (left 2/3), KPI cards (right column), slicer (below cards), and detail table (full width at bottom).

### Color Scheme

| Element | Color | Hex Code | Usage |
| --- | --- | --- | --- |
| Error/Critical | Red | `#D13438` | Error-severity findings, over-budget items |
| Warning | Amber | `#FF8C00` | Warning-severity findings, approaching limits |
| Note/Info | Blue | `#0078D4` | Note-severity findings, informational items |
| Compliant/Fixed | Green | `#107C10` | Compliant resources, fixed findings |
| Background | White | `#FFFFFF` | Page background |
| Text Primary | Dark Gray | `#323130` | Primary text |
| Accent | Teal | `#008575` | KPI cards, headers |

### Page 1: finops_compliance

FinOps Compliance: Findings by Repository

```text
┌─────────────────────────────────────────────────────────────────┐
│ [icon] FinOps Compliance - Findings by Repository               │
├──────────────────────────────────┬──────────┬──────────┐────────┤
│                                  │ Total    │ Total    │        │
│                                  │ Open     │ Fixed    │        │
│    Stacked Bar Chart             ├──────────┼──────────┤        │
│    (Repository × Severity)       │ Total    │Compliance│        │
│                                  │Dismissed │ Rate     │        │
│    820 × 420 px                  ├──────────┴──────────┤        │
│                                  │ Tool Name Slicer    │        │
│                                  │ Severity Slicer     │        │
│                                  │ Date Range Slicer   │        │
├──────────────────────────────────┴─────────────────────┴────────┤
│ Alert Details Table  1240 × 195 px                              │
│ Columns: Repository, Rule ID, Severity, Tool, State,           │
│          Created Date, Resource Name                            │
└─────────────────────────────────────────────────────────────────┘
```

| Visual | Type | Position | Size | Data |
| --- | --- | --- | --- | --- |
| header_bar | Shape | (0, 0) | 1280 × 50 | Teal background (#008575) |
| header_icon | Image | (10, 6) | 38 × 38 | FinOps icon |
| header_title | Textbox | (60, 6) | 500 × 40 | "FinOps Compliance - Findings by Repository" (bold, 14pt, Segoe UI) |
| stacked_bar_repo_severity | barChart | (20, 80) | 820 × 420 | X: repo_name, Y: COUNT(alert_id), Legend: severity |
| card_total_open | card | (860, 80) | 190 × 100 | [Total Open] |
| card_total_fixed | card | (1070, 80) | 190 × 100 | [Total Fixed] |
| card_total_dismissed | card | (860, 190) | 190 × 100 | [Total Dismissed] |
| card_compliance_rate | card | (1070, 190) | 190 × 100 | [Compliance Rate] (format: 0.0%) |
| slicer_tool | slicer | (860, 300) | 400 × 60 | ScanTools[tool_display_name] |
| slicer_severity | slicer | (860, 370) | 400 × 60 | FinOpsAlerts[severity] |
| slicer_date | slicer | (860, 440) | 400 × 60 | FinOpsAlerts[created_at] (date range) |
| tbl_details | tableEx | (20, 510) | 1240 × 195 | repo_name, rule_id, severity, tool_name, state, created_at, resource_name |

Conditional formatting:

- Stacked bar legend colors: error = `#D13438`, warning = `#FF8C00`, note = `#0078D4`
- Detail table severity column: background color mapped to severity
- Compliance Rate card: green if >= 80%, amber if >= 50%, red if < 50%

### Page 2: finops_trend

Cost Trend Analysis

```text
┌─────────────────────────────────────────────────────────────────┐
│ [icon] FinOps Trend - Open Alerts Over Time                     │
├──────────────────────────────────┬──────────┬──────────┐────────┤
│                                  │ Current  │ Fixed    │        │
│                                  │ Open     │This Month│        │
│    Line Chart                    ├──────────┼──────────┤        │
│    (Open Alerts Over Time)       │ Mean Time│ New This │        │
│    4-week moving average         │to Remed. │ Week     │        │
│    820 × 420 px                  ├──────────┴──────────┤        │
│                                  │ Repository Slicer   │        │
│                                  │ Date Range Slicer   │        │
│                                  │                     │        │
├──────────────────────────────────┴─────────────────────┴────────┤
│ Area Chart - New vs Fixed per Week  1240 × 195 px               │
│ Series 1: New alerts (red), Series 2: Fixed alerts (green)      │
└─────────────────────────────────────────────────────────────────┘
```

| Visual | Type | Position | Size | Data |
| --- | --- | --- | --- | --- |
| header_bar | Shape | (0, 0) | 1280 × 50 | Teal background |
| header_icon | Image | (10, 6) | 38 × 38 | Trend icon |
| header_title | Textbox | (60, 6) | 500 × 40 | "FinOps Trend - Open Alerts Over Time" |
| line_chart_trend | lineChart | (20, 80) | 820 × 420 | X: created_at (weekly), Y: COUNT where state="open", trendline: 4-week MA |
| card_current_open | card | (860, 80) | 190 × 100 | [Total Open] |
| card_fixed_month | card | (1070, 80) | 190 × 100 | [Fixed This Month] |
| card_mttr | card | (860, 190) | 190 × 100 | [Mean Time to Remediate] (format: #,##0 "days") |
| card_new_week | card | (1070, 190) | 190 × 100 | [New Alerts This Week] |
| slicer_repo | slicer | (860, 300) | 400 × 60 | Repositories[repo_name] |
| slicer_date | slicer | (860, 370) | 400 × 130 | FinOpsAlerts[created_at] (date range) |
| area_chart_new_fixed | areaChart | (20, 510) | 1240 × 195 | X: week, Y1: new (red #D13438, 50% opacity), Y2: fixed (green #107C10, 50% opacity) |

### Page 3: finops_tagging

Tagging Compliance

```text
┌─────────────────────────────────────────────────────────────────┐
│ [icon] FinOps Tagging - Governance Tag Compliance               │
├──────────────────────────────────┬──────────┬──────────┐────────┤
│                                  │Overall   │ Fully    │        │
│                                  │Compliance│Compliant │        │
│    Donut Chart                   ├──────────┼──────────┤        │
│    (Compliant vs Non-Compliant)  │ Non-     │          │        │
│    Center: Overall %             │Compliant │          │        │
│    410 × 420 px                  ├──────────┴──────────┤        │
│                                  │ Resource Group      │        │
│    Matrix (RG × Tag Key)         │ Slicer              │        │
│    410 × 420 px                  │ Tag Key Slicer      │        │
├──────────────────────────────────┴─────────────────────┴────────┤
│ Non-Compliant Resources Detail Table  1240 × 195 px             │
│ Columns: Resource Name, Resource Group, Type, Missing Tags      │
└─────────────────────────────────────────────────────────────────┘
```

| Visual | Type | Position | Size | Data |
| --- | --- | --- | --- | --- |
| header_bar | Shape | (0, 0) | 1280 × 50 | Teal background |
| header_title | Textbox | (60, 6) | 500 × 40 | "FinOps Tagging - Governance Tag Compliance" |
| donut_compliance | donutChart | (20, 80) | 410 × 420 | Values: compliant (#107C10) vs non-compliant (#D13438); center: [Tagging Compliance] |
| matrix_rg_tags | matrix | (440, 80) | 410 × 420 | Rows: resource_group, Columns: 7 tag_keys, Values: compliance icon |
| card_overall | card | (860, 80) | 190 × 100 | [Tagging Compliance] (format: 0.0%) |
| card_compliant | card | (1070, 80) | 190 × 100 | [Fully Compliant Resources] |
| card_noncompliant | card | (860, 190) | 190 × 100 | [Non-Compliant Resources] |
| slicer_rg | slicer | (860, 300) | 400 × 60 | GovernanceTags[resource_group] |
| slicer_tag | slicer | (860, 370) | 400 × 130 | GovernanceTags[tag_key] |
| tbl_noncompliant | tableEx | (20, 510) | 1240 × 195 | resource_name, resource_group, resource_type, tag_key (where compliance_status = false) |

Conditional formatting:

- Matrix cells: green (#107C10) checkmark for compliant, red (#D13438) X for non-compliant
- Overall Compliance card: green >= 90%, amber >= 70%, red < 70%

### Page 4: finops_rightsizing

Right-Sizing Recommendations

```text
┌─────────────────────────────────────────────────────────────────┐
│ [icon] FinOps Right-Sizing - Optimization Recommendations       │
├──────────────────────────────────┬──────────┬──────────┐────────┤
│                                  │ Total    │ Total    │        │
│                                  │ Recom.   │ Savings  │        │
│    Bar Chart                     ├──────────┼──────────┤        │
│    (Savings by Resource Group)   │ Avg Per  │          │        │
│    Teal bars (#008575)           │ Resource │          │        │
│    820 × 420 px                  ├──────────┴──────────┤        │
│                                  │ Resource Group      │        │
│                                  │ Slicer              │        │
│                                  │ Source Tool Slicer   │        │
├──────────────────────────────────┴─────────────────────┴────────┤
│ Right-Sizing Details Table  1240 × 195 px                       │
│ Columns: Resource Name, RG, Current SKU, Recommended,           │
│          Est. Monthly Savings, Tool, Detection Date              │
└─────────────────────────────────────────────────────────────────┘
```

| Visual | Type | Position | Size | Data |
| --- | --- | --- | --- | --- |
| header_bar | Shape | (0, 0) | 1280 × 50 | Teal background |
| header_title | Textbox | (60, 6) | 500 × 40 | "FinOps Right-Sizing - Optimization Recommendations" |
| bar_savings_rg | barChart | (20, 80) | 820 × 420 | X: resource_group (from resource_name parse), Y: SUM(estimated_savings), color: #008575 |
| card_total_recs | card | (860, 80) | 190 × 100 | [Total Right-Sizing Recommendations] |
| card_total_savings | card | (1070, 80) | 190 × 100 | [Total Estimated Savings] (format: $#,##0) |
| card_avg_savings | card | (860, 190) | 190 × 100 | [Avg Savings Per Resource] (format: $#,##0) |
| slicer_rg | slicer | (860, 300) | 400 × 60 | resource_group |
| slicer_tool | slicer | (860, 370) | 400 × 130 | ScanTools[tool_display_name] |
| tbl_rightsizing | tableEx | (20, 510) | 1240 × 195 | resource_name, resource_group, rule_id, estimated_savings, tool_name, created_at |

Conditional formatting:

- Estimated savings column: data bars in teal (#008575)
- Sort: estimated_savings descending

### Page 5: finops_orphans

Orphaned Resource Detection

```text
┌─────────────────────────────────────────────────────────────────┐
│ [icon] FinOps Orphans - Orphaned Resource Detection             │
├──────────────────────────────────┬──────────┬──────────┐────────┤
│                                  │ Total    │ Est.     │        │
│                                  │ Orphaned │ Monthly  │        │
│    Pie Chart                     ├──────────┤ Waste    │        │
│    (Orphaned Resources by Type)  │ Avg Age  ├──────────┤        │
│    Percentages on labels         │ (Days)   │          │        │
│    820 × 420 px                  ├──────────┴──────────┤        │
│                                  │ Resource Type       │        │
│                                  │ Slicer              │        │
│                                  │ Resource Group      │        │
│                                  │ Slicer              │        │
├──────────────────────────────────┴─────────────────────┴────────┤
│ Orphaned Resources Table  1240 × 195 px                         │
│ Columns: Resource Name, Type, RG, Age (Days), Est. Monthly      │
│          Cost, Detection Date, Status                            │
└─────────────────────────────────────────────────────────────────┘
```

| Visual | Type | Position | Size | Data |
| --- | --- | --- | --- | --- |
| header_bar | Shape | (0, 0) | 1280 × 50 | Teal background |
| header_title | Textbox | (60, 6) | 500 × 40 | "FinOps Orphans - Orphaned Resource Detection" |
| pie_by_type | pieChart | (20, 80) | 820 × 420 | Values: COUNT by resource_type (parsed from rule_id), labels: percentages |
| card_total_orphans | card | (860, 80) | 190 × 100 | [Total Orphaned Resources] |
| card_monthly_waste | card | (1070, 80) | 190 × 100 | [Estimated Monthly Waste] (format: $#,##0) |
| card_avg_age | card | (860, 190) | 190 × 100 | [Avg Orphan Age Days] (format: #,##0 "days") |
| slicer_type | slicer | (860, 300) | 400 × 60 | resource_type |
| slicer_rg | slicer | (860, 370) | 400 × 130 | resource_group |
| tbl_orphans | tableEx | (20, 510) | 1240 × 195 | resource_name, resource_type, resource_group, age_days (calculated), estimated_savings, created_at, state |

Conditional formatting:

- Age column: green < 30 days, amber (#FF8C00) 30 to 90 days, red (#D13438) > 90 days
- Sort: age descending

### Page 6: finops_budget

Budget vs Actual Spend

```text
┌─────────────────────────────────────────────────────────────────┐
│ [icon] FinOps Budget - Budget vs Actual Spend                   │
├──────────────────────────────────┬──────────┬──────────┐────────┤
│                                  │ Total    │ Total    │        │
│                                  │ Budget   │ Actual   │        │
│    Waterfall Chart               ├──────────┼──────────┤        │
│    (Spend by Department)         │ Variance │          │        │
│    Dark blue increases / light   │ %        │          │        │
│    820 × 420 px                  ├──────────┴──────────┤        │
│                                  │ Department Slicer   │        │
│                                  │ Month/Year Slicer   │        │
│                                  │ Subscription Slicer │        │
├──────────────────────────────────┴─────────────────────┴────────┤
│ Clustered Column Chart - Budget vs Actual by Month              │
│ 1240 × 195 px                                                   │
│ Blue outline = Budget, Solid fill = Actual (green/red)          │
└─────────────────────────────────────────────────────────────────┘
```

| Visual | Type | Position | Size | Data |
| --- | --- | --- | --- | --- |
| header_bar | Shape | (0, 0) | 1280 × 50 | Teal background |
| header_title | Textbox | (60, 6) | 500 × 40 | "FinOps Budget - Budget vs Actual Spend" |
| waterfall_dept | waterfallChart | (20, 80) | 820 × 420 | Category: department, Values: SUM(billed_cost), total bar at end |
| card_budget | card | (860, 80) | 190 × 100 | [Total Budget] |
| card_actual | card | (1070, 80) | 190 × 100 | [Total Actual Spend] (format: $#,##0) |
| card_variance | card | (860, 190) | 190 × 100 | [Variance Percent] (format: 0.0%; red if positive, green if negative) |
| slicer_dept | slicer | (860, 300) | 400 × 40 | department |
| slicer_month | slicer | (860, 350) | 400 × 50 | CostData[charge_period] (month/year) |
| slicer_sub | slicer | (860, 410) | 400 × 90 | CostData[subscription_id] |
| clustered_budget_actual | clusteredColumnChart | (20, 510) | 1240 × 195 | X: month, Y1: budget (blue outline), Y2: actual (solid, green if under / red if over) |

> Budget data must be manually entered or imported from an Azure Budget export. The `Total Budget` measure references a Budget table not included in the automated data pipeline.

### Cross-Page Interactions

All 6 FinOps pages share these behaviors:

| Source Visual | Target Visual | Interaction |
| --- | --- | --- |
| Repository slicer | All visuals on page | Filter |
| Severity slicer | Charts and tables | Filter |
| Date range slicer | Time-based charts | Filter |
| Bar/pie chart click | Detail table | Cross-highlight |
| KPI card | No interaction | Display only |

Drill-through is enabled from any FinOps page to `finops_compliance` using `repo_name` as the drill-through field.

### Page Order

Add the 6 FinOps pages after the existing pages in `pages.json`:

```json
{
  "pageOrder": [
    "advsec_dashboard",
    "overview",
    "severity_detail",
    "executive_summary",
    "critical_alerts",
    "alerts_by_type",
    "alerts_over_time",
    "alerts_by_project",
    "trend_analysis",
    "severity_by_alerttype",
    "alerts_summary",
    "accessibility_compliance",
    "finops_compliance",
    "finops_trend",
    "finops_tagging",
    "finops_rightsizing",
    "finops_orphans",
    "finops_budget"
  ]
}
```

## Implementation Path

This section provides step-by-step instructions for creating the PBIP files in the existing AdvSecReport project.

### Prerequisites

- Power BI Desktop (latest version) with PBIP format enabled
- Clone of the `advsec-pbi-report-ado` repository
- GitHub PAT with `security_events` scope for `devopsabcs-engineering`
- Azure subscription with Reader access to `rg-finops-demo-*` resource groups
- Azure Storage account with FOCUS export configured

### Step 1: Add Parameters to the Semantic Model

Edit `AdvSecReport.SemanticModel/definition/expressions.tmdl` and add the 3 new parameters (GitHubToken, AzureSubscriptionId, StorageAccountName) after the existing `PatToken` and `OrganizationName` parameters.

File: `AdvSecReport.SemanticModel/definition/expressions.tmdl`

### Step 2: Create Table TMDL Files

Create 4 new files in the semantic model tables directory:

| File Path | Content Source |
| --- | --- |
| `AdvSecReport.SemanticModel/definition/tables/FinOpsAlerts.tmdl` | FinOpsAlerts TMDL definition from this document |
| `AdvSecReport.SemanticModel/definition/tables/ScanTools.tmdl` | ScanTools TMDL definition (static data) |
| `AdvSecReport.SemanticModel/definition/tables/GovernanceTags.tmdl` | GovernanceTags TMDL definition |
| `AdvSecReport.SemanticModel/definition/tables/CostData.tmdl` | CostData TMDL definition |

Each file contains the full TMDL definition including column metadata, partition source (Power Query M expression), and DAX measures. Copy the TMDL blocks from the [Semantic Model Additions](#semantic-model-additions) section.

### Step 3: Add Relationships

Append to `AdvSecReport.SemanticModel/definition/relationships.tmdl`:

```tmdl
relationship FinOpsAlerts_Repositories
    fromColumn: FinOpsAlerts.repo_name
    toColumn: Dim_Repository.RepositoryName
    crossFilteringBehavior: singleDirection

relationship FinOpsAlerts_ScanTools
    fromColumn: FinOpsAlerts.tool_name
    toColumn: ScanTools.tool_name
    crossFilteringBehavior: singleDirection

relationship CostData_GovernanceTags
    fromColumn: CostData.resource_id
    toColumn: GovernanceTags.resource_id
    crossFilteringBehavior: singleDirection
    securityFilteringBehavior: none
    // Many-to-Many: use with caution
```

### Step 4: Create Report Page Directories

Create 6 page directories under `AdvSecReport.Report/definition/pages/`:

```text
AdvSecReport.Report/definition/pages/
├── finops_compliance/
│   ├── page.json
│   └── visuals/
│       ├── header_bar/visual.json
│       ├── header_icon/visual.json
│       ├── header_title/visual.json
│       ├── stacked_bar_repo_severity/visual.json
│       ├── card_total_open/visual.json
│       ├── card_total_fixed/visual.json
│       ├── card_total_dismissed/visual.json
│       ├── card_compliance_rate/visual.json
│       ├── slicer_tool/visual.json
│       ├── slicer_severity/visual.json
│       ├── slicer_date/visual.json
│       └── tbl_details/visual.json
├── finops_trend/
│   ├── page.json
│   └── visuals/ ...
├── finops_tagging/
│   ├── page.json
│   └── visuals/ ...
├── finops_rightsizing/
│   ├── page.json
│   └── visuals/ ...
├── finops_orphans/
│   ├── page.json
│   └── visuals/ ...
└── finops_budget/
    ├── page.json
    └── visuals/ ...
```

Each `page.json` follows this template:

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/1.0.0/schema.json",
  "name": "finops_compliance",
  "displayName": "FinOps Compliance",
  "displayOption": "FitToPage",
  "height": 720,
  "width": 1280
}
```

Each `visual.json` follows the pattern established by the accessibility_compliance page visuals: position (x, y), size (width, height), visual type, data bindings, and conditional formatting rules. Refer to the per-page visual specification tables in the [Report Pages](#report-pages) section for exact coordinates and data mappings.

### Step 5: Update pages.json

Edit `AdvSecReport.Report/definition/pages/pages.json` to append the 6 new FinOps page entries after `accessibility_compliance`. Use the page order defined in the [Page Order](#page-order) section.

### Step 6: Configure Data Sources

1. Open `AdvSecReport.pbip` in Power BI Desktop
2. Navigate to Transform Data (Power Query Editor)
3. Set parameter values:
   - `GitHubToken`: your GitHub PAT (will be cleared before commit by pre-commit hook)
   - `AzureSubscriptionId`: target subscription ID
   - `StorageAccountName`: storage account hosting FOCUS exports
4. Verify each query loads data successfully
5. Close and apply

### Step 7: Test and Validate

1. Verify all 4 new tables appear in the semantic model with correct columns and types
2. Confirm relationships are active and match the specification
3. Check each DAX measure returns expected values:
   - `Total Open` > 0 (if scan results exist)
   - `Tagging Compliance` returns a percentage between 0 and 1
   - `Cost Savings Potential` returns a dollar amount
   - `Mean Time to Remediate` returns a day count (or blank if no fixed alerts)
4. Navigate to each of the 6 FinOps pages and verify:
   - Header bar, icon, and title render correctly
   - Main chart displays data with correct axes and legend
   - KPI cards show formatted values
   - Slicers filter all visuals on the page
   - Detail table shows appropriate columns
5. Test drill-through from any FinOps page to `finops_compliance` by right-clicking a repository

### Refresh Schedule

| Data Source | Frequency | Timing | Notes |
| --- | --- | --- | --- |
| GitHub Code Scanning API | Weekly | Sunday 6:00 AM UTC | 4 hours after scan pipeline |
| Azure Resource Graph | Weekly | Sunday 5:00 AM UTC | After scan pipeline completes |
| Azure FOCUS Export | Daily | Automatic | Azure Cost Management export |
| Power BI Dataset | Weekly | Sunday 7:00 AM UTC | After all sources refresh |

Configure scheduled refresh in Power BI Service under Dataset settings > Scheduled refresh. Enable failure notifications to the dataset owner.

## References

- [Power BI Dashboard Design](power-bi-dashboard-design.md): original 6-page layout specification
- [Power BI Data Model](power-bi-data-model.md): star schema with 5 tables
- [Power Query: FinOps Alerts](power-query-finops-alerts.md): GitHub Code Scanning API connection
- [Power Query: Resource Graph](power-query-resource-graph.md): Azure Resource Graph KQL and M expression
- [FinOps Toolkit Integration](finops-toolkit-integration.md): FOCUS export setup and column mapping
- [FinOps Governance Rules](../.github/instructions/finops-governance.instructions.md): required 7 tags and compliance policies
- [Microsoft FinOps Toolkit](https://github.com/microsoft/finops-toolkit): official Power BI templates (v13)
- [FOCUS Specification](https://focus.finops.org/): FinOps Open Cost and Usage Specification
