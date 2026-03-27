<#
.SYNOPSIS
    Bootstrap 5 FinOps demo app repositories under the devopsabcs-engineering organization.

.DESCRIPTION
    Creates finops-demo-app-001 through finops-demo-app-005 using GitHub CLI.
    Idempotent: skips repos that already exist.
    Enables code scanning, sets topics, and configures OIDC secrets.

.NOTES
    Prerequisites:
    - GitHub CLI (gh) installed and authenticated with org admin permissions
    - Environment variables or prompted input for OIDC secrets
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Org = 'devopsabcs-engineering',

    [Parameter()]
    [string]$ScannerRepo = 'finops-scan-demo-app'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Violation descriptions for each demo app
$DemoApps = @(
    @{ Number = '001'; Description = 'FinOps demo app 001 - Missing required tags violation';         Violations = 'missing-tags' }
    @{ Number = '002'; Description = 'FinOps demo app 002 - Oversized resources violation';           Violations = 'oversized-resources' }
    @{ Number = '003'; Description = 'FinOps demo app 003 - Orphaned resources violation';            Violations = 'orphaned-resources' }
    @{ Number = '004'; Description = 'FinOps demo app 004 - No auto-shutdown violation';              Violations = 'no-auto-shutdown' }
    @{ Number = '005'; Description = 'FinOps demo app 005 - Redundant and expensive resources';       Violations = 'redundant-resources' }
)

$Topics = @('finops', 'demo', 'azure', 'cost-governance')

# Collect OIDC values from environment variables or prompt
$AzureClientId = $env:AZURE_CLIENT_ID
$AzureTenantId = $env:AZURE_TENANT_ID
$AzureSubscriptionId = $env:AZURE_SUBSCRIPTION_ID

if (-not $AzureClientId) {
    $AzureClientId = Read-Host -Prompt 'Enter AZURE_CLIENT_ID (or press Enter to skip secret configuration)'
}
if ($AzureClientId -and -not $AzureTenantId) {
    $AzureTenantId = Read-Host -Prompt 'Enter AZURE_TENANT_ID'
}
if ($AzureClientId -and -not $AzureSubscriptionId) {
    $AzureSubscriptionId = Read-Host -Prompt 'Enter AZURE_SUBSCRIPTION_ID'
}

$ConfigureSecrets = [bool]$AzureClientId

foreach ($app in $DemoApps) {
    $repoName = "finops-demo-app-$($app.Number)"
    $fullRepo = "$Org/$repoName"

    Write-Host "Processing $fullRepo..." -ForegroundColor Cyan

    # Check if repo already exists
    $repoExists = $false
    try {
        gh repo view $fullRepo --json name 2>$null | Out-Null
        $repoExists = $true
    }
    catch {
        $repoExists = $false
    }

    if ($repoExists) {
        Write-Host "  Repo $fullRepo already exists, skipping creation." -ForegroundColor Yellow
    }
    else {
        Write-Host "  Creating $fullRepo..." -ForegroundColor Green
        gh repo create $fullRepo `
            --public `
            --description $app.Description `
            --confirm
    }

    # Set topics
    Write-Host "  Setting topics..." -ForegroundColor Gray
    $topicArgs = ($Topics | ForEach-Object { $_ }) -join ','
    gh repo edit $fullRepo --add-topic $topicArgs

    # Enable code scanning default setup
    Write-Host "  Enabling code scanning default setup..." -ForegroundColor Gray
    try {
        gh api "repos/$fullRepo/code-scanning/default-setup" `
            -X PATCH `
            -f state=configured 2>$null
        Write-Host "  Code scanning enabled." -ForegroundColor Green
    }
    catch {
        Write-Host "  Could not enable code scanning (may require GHAS license)." -ForegroundColor Yellow
    }

    # Configure OIDC secrets
    if ($ConfigureSecrets) {
        Write-Host "  Configuring OIDC secrets..." -ForegroundColor Gray
        gh secret set AZURE_CLIENT_ID --repo $fullRepo --body $AzureClientId
        gh secret set AZURE_TENANT_ID --repo $fullRepo --body $AzureTenantId
        gh secret set AZURE_SUBSCRIPTION_ID --repo $fullRepo --body $AzureSubscriptionId
        Write-Host "  OIDC secrets configured." -ForegroundColor Green
    }
}

# Configure INFRACOST_API_KEY on the scanner repo
$scannerFullRepo = "$Org/$ScannerRepo"
$InfracostApiKey = $env:INFRACOST_API_KEY
if (-not $InfracostApiKey) {
    $InfracostApiKey = Read-Host -Prompt 'Enter INFRACOST_API_KEY for scanner repo (or press Enter to skip)'
}
if ($InfracostApiKey) {
    Write-Host "Configuring INFRACOST_API_KEY on $scannerFullRepo..." -ForegroundColor Cyan
    gh secret set INFRACOST_API_KEY --repo $scannerFullRepo --body $InfracostApiKey
    Write-Host "INFRACOST_API_KEY configured." -ForegroundColor Green
}

Write-Host "`nBootstrap complete. Created/verified $($DemoApps.Count) demo app repos." -ForegroundColor Cyan
