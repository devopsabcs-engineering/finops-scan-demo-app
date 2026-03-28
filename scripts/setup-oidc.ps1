#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sets up OIDC federation for GitHub Actions to authenticate with Azure.

.DESCRIPTION
    Creates or retrieves an Azure AD app registration, federated credential,
    service principal, and Reader role assignment for the finops-scan-demo-app
    repository. Idempotent — safe to run multiple times.

.EXAMPLE
    ./scripts/setup-oidc.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AppName = 'finops-scanner-github-actions'
$RepoOwner = 'devopsabcs-engineering'
$ScannerRepo = 'finops-scan-demo-app'
$Issuer = 'https://token.actions.githubusercontent.com'
$Audience = 'api://AzureADTokenExchange'

# All repos that need federated credentials (scanner + 5 demo apps)
$FederatedRepos = @(
    @{ Repo = $ScannerRepo;          CredName = 'github-actions-scanner-main';  Description = "GitHub Actions OIDC for $RepoOwner/$ScannerRepo main branch" }
    @{ Repo = 'finops-demo-app-001'; CredName = 'github-actions-demo-001-main'; Description = "GitHub Actions OIDC for $RepoOwner/finops-demo-app-001 main branch" }
    @{ Repo = 'finops-demo-app-002'; CredName = 'github-actions-demo-002-main'; Description = "GitHub Actions OIDC for $RepoOwner/finops-demo-app-002 main branch" }
    @{ Repo = 'finops-demo-app-003'; CredName = 'github-actions-demo-003-main'; Description = "GitHub Actions OIDC for $RepoOwner/finops-demo-app-003 main branch" }
    @{ Repo = 'finops-demo-app-004'; CredName = 'github-actions-demo-004-main'; Description = "GitHub Actions OIDC for $RepoOwner/finops-demo-app-004 main branch" }
    @{ Repo = 'finops-demo-app-005'; CredName = 'github-actions-demo-005-main'; Description = "GitHub Actions OIDC for $RepoOwner/finops-demo-app-005 main branch" }
)

Write-Host '=== OIDC Federation Setup ===' -ForegroundColor Cyan

# Step 1: Get or create app registration
Write-Host "`n[1/5] Checking for existing app registration '$AppName'..."
$existingApp = az ad app list --display-name $AppName --query '[0]' -o json 2>$null | ConvertFrom-Json

if ($existingApp) {
    $appId = $existingApp.appId
    $objectId = $existingApp.id
    Write-Host "  Found existing app: $appId" -ForegroundColor Green
} else {
    Write-Host "  Creating app registration..."
    $newApp = az ad app create --display-name $AppName -o json | ConvertFrom-Json
    $appId = $newApp.appId
    $objectId = $newApp.id
    Write-Host "  Created app: $appId" -ForegroundColor Green
}

# Step 2: Create or verify federated credentials for all repos
Write-Host "`n[2/5] Configuring federated credentials for $($FederatedRepos.Count) repos..."
foreach ($fedRepo in $FederatedRepos) {
    $credName = $fedRepo.CredName
    $subject = "repo:${RepoOwner}/$($fedRepo.Repo):ref:refs/heads/main"
    Write-Host "  Checking credential '$credName' (subject: $subject)..."

    $existingCred = az ad app federated-credential list --id $objectId --query "[?name=='$credName']" -o json 2>$null | ConvertFrom-Json

    if ($existingCred -and $existingCred.Count -gt 0) {
        Write-Host "    Already exists" -ForegroundColor Green
    } else {
        Write-Host "    Creating..."
        $credBody = @{
            name        = $credName
            issuer      = $Issuer
            subject     = $subject
            audiences   = @($Audience)
            description = $fedRepo.Description
        } | ConvertTo-Json -Compress

        $credBody | az ad app federated-credential create --id $objectId --parameters "@-" -o none
        Write-Host "    Created" -ForegroundColor Green
    }
}

# Step 3: Create or get service principal
Write-Host "`n[3/5] Checking for existing service principal..."
$existingSp = az ad sp list --filter "appId eq '$appId'" --query '[0]' -o json 2>$null | ConvertFrom-Json

if ($existingSp) {
    $spObjectId = $existingSp.id
    Write-Host "  Service principal exists: $spObjectId" -ForegroundColor Green
} else {
    Write-Host "  Creating service principal..."
    $newSp = az ad sp create --id $appId -o json | ConvertFrom-Json
    $spObjectId = $newSp.id
    Write-Host "  Created service principal: $spObjectId" -ForegroundColor Green
}

# Step 4: Assign Contributor role on subscription (required for deployments)
Write-Host "`n[4/5] Checking Contributor role assignment..."
$subscriptionId = az account show --query 'id' -o tsv
$existingRole = az role assignment list `
    --assignee $appId `
    --role 'Contributor' `
    --scope "/subscriptions/$subscriptionId" `
    --query '[0]' -o json 2>$null | ConvertFrom-Json

if ($existingRole) {
    Write-Host "  Contributor role already assigned" -ForegroundColor Green
} else {
    Write-Host "  Assigning Contributor role on subscription..."
    az role assignment create `
        --assignee $appId `
        --role 'Contributor' `
        --scope "/subscriptions/$subscriptionId" `
        -o none
    Write-Host "  Contributor role assigned" -ForegroundColor Green
}

# Step 5: Output configuration
$tenantId = az account show --query 'tenantId' -o tsv

Write-Host "`n[5/5] Configuration for GitHub Secrets:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AZURE_CLIENT_ID:       $appId"
Write-Host "  AZURE_TENANT_ID:       $tenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID: $subscriptionId"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nFederated credentials configured for:" -ForegroundColor Yellow
foreach ($fedRepo in $FederatedRepos) {
    Write-Host "  - $RepoOwner/$($fedRepo.Repo)" -ForegroundColor Yellow
}
Write-Host "`nAdd these as repository secrets via the bootstrap script:" -ForegroundColor Yellow
Write-Host "  ./scripts/bootstrap-demo-apps.ps1" -ForegroundColor Yellow
