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

    # Check if repo already exists (use $LASTEXITCODE since gh is a native command)
    $null = gh repo view $fullRepo --json name 2>&1
    $repoExists = ($LASTEXITCODE -eq 0)

    if ($repoExists) {
        Write-Host "  Repo $fullRepo already exists, skipping creation." -ForegroundColor Yellow
    }
    else {
        Write-Host "  Creating $fullRepo..." -ForegroundColor Green
        gh repo create $fullRepo `
            --public `
            --description $app.Description
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ERROR: Failed to create $fullRepo. Skipping." -ForegroundColor Red
            continue
        }
    }

    # Check if repo is empty (size 0 means no commits) and push demo app content
    $localAppDir = Join-Path $PSScriptRoot "..\finops-demo-app-$($app.Number)"
    $repoSize = gh repo view $fullRepo --json diskUsage --jq '.diskUsage' 2>&1
    $repoIsEmpty = ($LASTEXITCODE -ne 0) -or ([int]$repoSize -eq 0)

    if ($repoIsEmpty -and (Test-Path $localAppDir)) {
        Write-Host "  Repo is empty. Pushing demo app content from $localAppDir..." -ForegroundColor Green
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "finops-demo-app-$($app.Number)-$(Get-Random)"
        try {
            # Initialize a new git repo and point it at the remote
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            Push-Location $tempDir
            git init -b main 2>&1 | Out-Null
            git remote add origin "https://github.com/$fullRepo.git"
            # Copy all files (including hidden dirs like .github) using robocopy for accuracy
            $resolvedAppDir = (Resolve-Path $localAppDir).Path
            Get-ChildItem -Path $resolvedAppDir -Force | ForEach-Object {
                if ($_.PSIsContainer) {
                    Copy-Item -Path $_.FullName -Destination (Join-Path $tempDir $_.Name) -Recurse -Force
                }
                else {
                    Copy-Item -Path $_.FullName -Destination $tempDir -Force
                }
            }
            git add -A
            git commit -m "feat: add FinOps demo app $($app.Number) with intentional $($app.Violations) violations AB#2118"
            git push -u origin main
            Pop-Location
            Write-Host "  Demo app content pushed successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "  Warning: Could not push demo app content: $_" -ForegroundColor Yellow
            if ((Get-Location).Path -ne $PSScriptRoot) { Pop-Location }
        }
        finally {
            if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    elseif ($repoIsEmpty) {
        Write-Host "  Repo is empty but no local content found at $localAppDir. Skipping push." -ForegroundColor Yellow
        Write-Host "  Topics, code scanning, and secrets require at least one commit. Skipping..." -ForegroundColor Yellow
        continue
    }

    # Set topics (requires repo to have at least one commit)
    Write-Host "  Setting topics..." -ForegroundColor Gray
    foreach ($topic in $Topics) {
        gh repo edit $fullRepo --add-topic $topic 2>$null
    }

    # Enable code scanning default setup
    Write-Host "  Enabling code scanning default setup..." -ForegroundColor Gray
    try {
        $result = gh api "repos/$fullRepo/code-scanning/default-setup" `
            -X PATCH `
            -f state=configured 2>&1
        if ($result -match '"message"') {
            Write-Host "  Could not enable code scanning (may require GHAS license or repo visibility change)." -ForegroundColor Yellow
        }
        else {
            Write-Host "  Code scanning enabled." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  Could not enable code scanning (may require GHAS license)." -ForegroundColor Yellow
    }

    # Configure OIDC secrets (requires repo to have at least one commit)
    if ($ConfigureSecrets) {
        Write-Host "  Configuring OIDC secrets..." -ForegroundColor Gray
        try {
            gh secret set AZURE_CLIENT_ID --repo $fullRepo --body $AzureClientId
            gh secret set AZURE_TENANT_ID --repo $fullRepo --body $AzureTenantId
            gh secret set AZURE_SUBSCRIPTION_ID --repo $fullRepo --body $AzureSubscriptionId
            Write-Host "  OIDC secrets configured." -ForegroundColor Green
        }
        catch {
            Write-Host "  Warning: Could not configure secrets: $_" -ForegroundColor Yellow
        }
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
