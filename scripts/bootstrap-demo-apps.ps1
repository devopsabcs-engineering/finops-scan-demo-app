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

$OrgAdminToken = $env:ORG_ADMIN_TOKEN
if (-not $OrgAdminToken) {
    $OrgAdminToken = Read-Host -Prompt 'Enter ORG_ADMIN_TOKEN for wiki push (or press Enter to skip)'
}

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

    # Check if repo has any commits (diskUsage is unreliable — check for default branch commits instead)
    $localAppDir = Join-Path $PSScriptRoot "..\finops-demo-app-$($app.Number)"
    $commitCount = gh api "repos/$fullRepo/commits?per_page=1" --jq 'length' 2>&1
    $repoIsEmpty = ($LASTEXITCODE -ne 0) -or ($commitCount -eq '0') -or ([string]::IsNullOrWhiteSpace($commitCount))

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
            git push -u origin main 2>&1
            if ($LASTEXITCODE -ne 0) {
                Pop-Location
                Write-Host "  ERROR: Push failed. Repo may already have content." -ForegroundColor Red
            }
            else {
                Pop-Location
                Write-Host "  Demo app content pushed successfully." -ForegroundColor Green
            }
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

    if ($OrgAdminToken) {
        Write-Host "  Configuring ORG_ADMIN_TOKEN for wiki push..." -ForegroundColor Gray
        try {
            gh secret set ORG_ADMIN_TOKEN --repo $fullRepo --body $OrgAdminToken
            Write-Host "  ORG_ADMIN_TOKEN configured." -ForegroundColor Green
        }
        catch {
            Write-Host "  Warning: Could not configure ORG_ADMIN_TOKEN: $_" -ForegroundColor Yellow
        }
    }

    # Configure VM_ADMIN_PASSWORD for app-004 (VM deployment)
    if ($app.Number -eq '004') {
        $VmAdminPassword = $env:VM_ADMIN_PASSWORD
        if (-not $VmAdminPassword) {
            $defaultPassword = 'F1nOps#Demo2026!'
            $VmAdminPassword = Read-Host -Prompt "Enter VM_ADMIN_PASSWORD for app-004 (or press Enter for default: $defaultPassword)"
            if (-not $VmAdminPassword) { $VmAdminPassword = $defaultPassword }
        }
        Write-Host "  Configuring VM_ADMIN_PASSWORD..." -ForegroundColor Gray
        try {
            gh secret set VM_ADMIN_PASSWORD --repo $fullRepo --body $VmAdminPassword
            Write-Host "  VM_ADMIN_PASSWORD configured." -ForegroundColor Green
        }
        catch {
            Write-Host "  Warning: Could not configure VM_ADMIN_PASSWORD: $_" -ForegroundColor Yellow
        }
    }

    # Initialize wiki (required before workflows can push to it)
    if ($OrgAdminToken) {
        Write-Host "  Initializing wiki..." -ForegroundColor Gray
        $wikiUrl = "https://x-access-token:${OrgAdminToken}@github.com/${fullRepo}.wiki.git"
        $wikiTempDir = Join-Path ([System.IO.Path]::GetTempPath()) "wiki-init-$($app.Number)-$(Get-Random)"
        try {
            $null = git clone --depth 1 $wikiUrl $wikiTempDir 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    Wiki already initialized." -ForegroundColor Green
            }
            else {
                # Wiki doesn't exist yet — create it with a Home page
                New-Item -ItemType Directory -Path $wikiTempDir -Force | Out-Null
                Push-Location $wikiTempDir
                git init -b master 2>&1 | Out-Null
                git remote add origin $wikiUrl
                "# $repoName`n`nWiki for $($app.Description).`n`n- [Deployment](Deployment)" | Set-Content -Path 'Home.md'
                git add -A
                git commit -m "Initialize wiki" 2>&1 | Out-Null
                git push -u origin master 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    Wiki initialized." -ForegroundColor Green
                }
                else {
                    Write-Host "    Could not initialize wiki." -ForegroundColor Yellow
                }
                Pop-Location
            }
        }
        catch {
            Write-Host "    Warning: Wiki init failed: $_" -ForegroundColor Yellow
            if ((Get-Location).Path -ne $PSScriptRoot) { Pop-Location }
        }
        finally {
            if (Test-Path $wikiTempDir) { Remove-Item -Recurse -Force $wikiTempDir -ErrorAction SilentlyContinue }
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

# Configure ORG_ADMIN_TOKEN on the scanner repo
if ($OrgAdminToken) {
    Write-Host "Configuring ORG_ADMIN_TOKEN on $scannerFullRepo..." -ForegroundColor Cyan
    gh secret set ORG_ADMIN_TOKEN --repo $scannerFullRepo --body $OrgAdminToken
    Write-Host "ORG_ADMIN_TOKEN configured." -ForegroundColor Green

    # Initialize scanner repo wiki
    Write-Host "Initializing scanner repo wiki..." -ForegroundColor Cyan
    $scannerWikiUrl = "https://x-access-token:${OrgAdminToken}@github.com/${scannerFullRepo}.wiki.git"
    $scannerWikiDir = Join-Path ([System.IO.Path]::GetTempPath()) "wiki-scanner-$(Get-Random)"
    try {
        $null = git clone --depth 1 $scannerWikiUrl $scannerWikiDir 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Scanner wiki already initialized." -ForegroundColor Green
        }
        else {
            New-Item -ItemType Directory -Path $scannerWikiDir -Force | Out-Null
            Push-Location $scannerWikiDir
            git init -b master 2>&1 | Out-Null
            git remote add origin $scannerWikiUrl
            @"
# FinOps Cost Governance Scanner

Central scanner for 5 FinOps demo apps.

- [Deployments](Deployments)

## Demo App Repos

| App | Violation | Wiki |
|-----|-----------|------|
| [finops-demo-app-001](https://github.com/$Org/finops-demo-app-001) | Missing Tags | [Deployment](https://github.com/$Org/finops-demo-app-001/wiki/Deployment) |
| [finops-demo-app-002](https://github.com/$Org/finops-demo-app-002) | Oversized Resources | [Deployment](https://github.com/$Org/finops-demo-app-002/wiki/Deployment) |
| [finops-demo-app-003](https://github.com/$Org/finops-demo-app-003) | Orphaned Resources | [Deployment](https://github.com/$Org/finops-demo-app-003/wiki/Deployment) |
| [finops-demo-app-004](https://github.com/$Org/finops-demo-app-004) | No Auto-Shutdown | [Deployment](https://github.com/$Org/finops-demo-app-004/wiki/Deployment) |
| [finops-demo-app-005](https://github.com/$Org/finops-demo-app-005) | Redundant Resources | [Deployment](https://github.com/$Org/finops-demo-app-005/wiki/Deployment) |
"@ | Set-Content -Path 'Home.md'
            git add -A
            git commit -m "Initialize wiki" 2>&1 | Out-Null
            git push -u origin master 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Scanner wiki initialized." -ForegroundColor Green
            }
            else {
                Write-Host "  Could not initialize scanner wiki." -ForegroundColor Yellow
            }
            Pop-Location
        }
    }
    catch {
        Write-Host "  Warning: Scanner wiki init failed: $_" -ForegroundColor Yellow
        if ((Get-Location).Path -ne $PSScriptRoot) { Pop-Location }
    }
    finally {
        if (Test-Path $scannerWikiDir) { Remove-Item -Recurse -Force $scannerWikiDir -ErrorAction SilentlyContinue }
    }
}

Write-Host "`nBootstrap complete. Created/verified $($DemoApps.Count) demo app repos." -ForegroundColor Cyan
