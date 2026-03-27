---
title: "Power Query — GitHub Code Scanning API (FinOps Alerts)"
description: "Power Query M expressions for pulling FinOps scan results from the GitHub Code Scanning API into Power BI."
ms.date: 2026-03-27
ms.topic: how-to
author: devopsabcs-engineering
keywords:
  - power-query
  - github-api
  - code-scanning
  - finops
  - sarif
---

## Overview

This guide describes how to connect Power BI to the GitHub Code Scanning API to pull FinOps scan results.
The scanner pipeline uploads SARIF results from four tools (PSRule, Checkov, Cloud Custodian, Infracost) to GitHub Code Scanning.
Power Query retrieves these alerts and transforms them into the `FinOpsAlerts` fact table defined in the data model.

## Prerequisites

- **GitHub Personal Access Token (PAT)** with the `security_events` scope
- The PAT must have access to the `devopsabcs-engineering` organization
- Power BI Desktop (latest version) or Power BI Service with gateway for scheduled refresh

### Token Configuration

1. Go to **GitHub > Settings > Developer settings > Personal access tokens > Fine-grained tokens**
2. Create a token with:
   - **Resource owner**: `devopsabcs-engineering`
   - **Repository access**: All repositories (or select the 5 demo app repos + scanner repo)
   - **Permissions**: Code scanning alerts (read)
3. Store the token securely — it is used as a Power BI parameter

## Power Query M Expression

### Parameter Setup

Create a Power BI parameter named `GitHubToken` of type `Text` to store your PAT securely.

### Organization-Level Alerts Query

This query pulls all code scanning alerts for the organization, filtered by tool name.

```powerquery
let
    Token = Excel.CurrentWorkbook(){[Name="GitHubToken"]}[Content]{0}[Column1],
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
                    tool_name = "PSRule",
                    per_page = "100",
                    state = "open"
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
    RenamedColumns = Table.RenameColumns(TypedDates, {
        {"number", "alert_number"}
    })
in
    RenamedColumns
```

### Multi-Tool Query

To pull alerts for all four FinOps tools, create a function and invoke it for each tool:

```powerquery
let
    GetAlertsByTool = (toolName as text) =>
        let
            Token = Excel.CurrentWorkbook(){[Name="GitHubToken"]}[Content]{0}[Column1],
            Source = Json.Document(
                Web.Contents(
                    "https://api.github.com/orgs/devopsabcs-engineering/code-scanning/alerts",
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
            })
        in
            Expanded,
    Tools = {"PSRule", "Checkov", "custodian-to-sarif", "infracost-to-sarif"},
    ToolTable = Table.FromList(Tools, Splitter.SplitByNothing(), {"ToolName"}),
    Results = Table.AddColumn(ToolTable, "Alerts", each GetAlertsByTool([ToolName])),
    Combined = Table.ExpandTableColumn(Results, "Alerts", Table.ColumnNames(Results{0}[Alerts]))
in
    Combined
```

## Pagination Handling

The GitHub Code Scanning API returns a maximum of **100 results per page** and supports up to **5,000 alerts** per query.

To handle pagination:

1. Check the `Link` response header for `rel="next"` URLs
2. Continue fetching until no `next` link is present
3. Use the `page` query parameter to request subsequent pages

For most FinOps scan results (5 demo apps × 4 tools), pagination is unlikely to be needed.
If your organization scales to many repositories, implement the pagination function:

```powerquery
let
    GetAllPages = (baseUrl as text, token as text) =>
        let
            GetPage = (url as text) =>
                let
                    Response = Web.Contents(url, [
                        Headers = [
                            #"Authorization" = "Bearer " & token,
                            #"Accept" = "application/vnd.github+json",
                            #"X-GitHub-Api-Version" = "2022-11-28"
                        ],
                        ManualStatusHandling = {404}
                    ]),
                    Data = Json.Document(Response)
                in
                    Data,
            FirstPage = GetPage(baseUrl & "?per_page=100&page=1")
        in
            FirstPage
in
    GetAllPages
```

## Transform to FinOpsAlerts Fact Table

After expanding the API response, apply these transformations to match the `FinOpsAlerts` fact table schema:

1. **Rename columns** to match the data model (`number` → `alert_number`, etc.)
2. **Parse dates** — Convert `created_at` and `fixed_at` from ISO 8601 strings to `datetimezone`
3. **Extract severity** — Map GitHub severity levels (`error`, `warning`, `note`) directly
4. **Add estimated_savings** — Set to `null` for PSRule/Checkov alerts; populate from Infracost alerts
5. **Add scan_domain** — Set to `"FinOps"` for all records from this query

## Refresh Schedule

Align the Power BI data refresh with the scanner pipeline schedule:

| Schedule | Frequency | Notes |
| ---------- | ----------- | ------- |
| FinOps scan pipeline | Weekly (Sunday 2:00 AM UTC) | GitHub Actions `cron` schedule |
| Power BI refresh | Weekly (Sunday 6:00 AM UTC) | 4 hours after scan completes |
| Cost data (FOCUS export) | Daily | Azure Cost Management export |

Configure the refresh in Power BI Service under **Dataset settings > Scheduled refresh**.
Use a gateway if the data source requires on-premises connectivity.
