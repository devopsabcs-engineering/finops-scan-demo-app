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
$RepoName = 'finops-scan-demo-app'
$Issuer = 'https://token.actions.githubusercontent.com'
$Subject = "repo:${RepoOwner}/${RepoName}:ref:refs/heads/main"
$Audience = 'api://AzureADTokenExchange'
$CredentialName = 'github-actions-main'

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

# Step 2: Create or verify federated credential
Write-Host "`n[2/5] Checking for existing federated credential..."
$existingCred = az ad app federated-credential list --id $objectId --query "[?name=='$CredentialName']" -o json 2>$null | ConvertFrom-Json

if ($existingCred -and $existingCred.Count -gt 0) {
    Write-Host "  Federated credential '$CredentialName' already exists" -ForegroundColor Green
} else {
    Write-Host "  Creating federated credential..."
    $credBody = @{
        name        = $CredentialName
        issuer      = $Issuer
        subject     = $Subject
        audiences   = @($Audience)
        description = "GitHub Actions OIDC for $RepoOwner/$RepoName main branch"
    } | ConvertTo-Json -Compress

    $credBody | az ad app federated-credential create --id $objectId --parameters "@-" -o none
    Write-Host "  Federated credential created" -ForegroundColor Green
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

# Step 4: Assign Reader role on subscription
Write-Host "`n[4/5] Checking Reader role assignment..."
$subscriptionId = az account show --query 'id' -o tsv
$existingRole = az role assignment list `
    --assignee $appId `
    --role 'Reader' `
    --scope "/subscriptions/$subscriptionId" `
    --query '[0]' -o json 2>$null | ConvertFrom-Json

if ($existingRole) {
    Write-Host "  Reader role already assigned" -ForegroundColor Green
} else {
    Write-Host "  Assigning Reader role on subscription..."
    az role assignment create `
        --assignee $appId `
        --role 'Reader' `
        --scope "/subscriptions/$subscriptionId" `
        -o none
    Write-Host "  Reader role assigned" -ForegroundColor Green
}

# Step 5: Output configuration
$tenantId = az account show --query 'tenantId' -o tsv

Write-Host "`n[5/5] Configuration for GitHub Secrets:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AZURE_CLIENT_ID:       $appId"
Write-Host "  AZURE_TENANT_ID:       $tenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID: $subscriptionId"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nAdd these as repository secrets in GitHub:" -ForegroundColor Yellow
Write-Host "  https://github.com/$RepoOwner/$RepoName/settings/secrets/actions" -ForegroundColor Yellow
