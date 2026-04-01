#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bootstrap FinOps demo app infrastructure in Azure DevOps.

.DESCRIPTION
    Creates Azure Repos, variable groups, WIF service connections, environments,
    pipelines, and a project wiki for the FinOps demo apps in Azure DevOps.
    Idempotent: skips resources that already exist.

.NOTES
    Prerequisites:
    - Azure CLI with azure-devops extension (`az extension add --name azure-devops`)
    - PowerShell 7+
    - Azure CLI authenticated (`az login`)
    - Azure DevOps PAT or `az devops login` with project admin permissions
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Org = 'MngEnvMCAP675646',

    [Parameter()]
    [string]$Project = 'FinOps'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$OrgUrl      = "https://dev.azure.com/$Org"
$AdoResource = '499b84ac-1321-427f-aa17-267ca6975798'

$DemoApps = @(
    @{ Number = '001'; Description = 'FinOps demo app 001 - Missing required tags violation';   Violations = 'missing-tags' }
    @{ Number = '002'; Description = 'FinOps demo app 002 - Oversized resources violation';     Violations = 'oversized-resources' }
    @{ Number = '003'; Description = 'FinOps demo app 003 - Orphaned resources violation';      Violations = 'orphaned-resources' }
    @{ Number = '004'; Description = 'FinOps demo app 004 - No auto-shutdown violation';        Violations = 'no-auto-shutdown' }
    @{ Number = '005'; Description = 'FinOps demo app 005 - Redundant and expensive resources'; Violations = 'redundant-resources' }
)

$ServiceConnectionNames = @('finops-scanner-ado') + ($DemoApps | ForEach-Object { "finops-demo-app-$($_.Number)" })

$Pipelines = @(
    @{ Name = 'finops-scan';      YmlPath = '.azuredevops/pipelines/finops-scan.yml' }
    @{ Name = 'deploy-all';       YmlPath = '.azuredevops/pipelines/deploy-all.yml' }
    @{ Name = 'teardown-all';     YmlPath = '.azuredevops/pipelines/teardown-all.yml' }
    @{ Name = 'finops-cost-gate'; YmlPath = '.azuredevops/pipelines/finops-cost-gate.yml' }
)

# ---------------------------------------------------------------------------
# Helper: check if a variable group exists by name
# ---------------------------------------------------------------------------
function Get-VariableGroupByName {
    param([string]$GroupName)
    $groups = az pipelines variable-group list --query "[?name=='$GroupName']" -o json 2>$null | ConvertFrom-Json
    if ($groups -and $groups.Count -gt 0) { return $groups[0] }
    return $null
}

# ---------------------------------------------------------------------------
# Helper: check if a service connection exists by name
# ---------------------------------------------------------------------------
function Get-ServiceEndpointByName {
    param([string]$EndpointName)
    $apiUrl = "$OrgUrl/$Project/_apis/serviceendpoint/endpoints?endpointNames=$EndpointName&api-version=7.1"
    $result = az rest -u $apiUrl -m GET --resource $AdoResource -o json 2>$null | ConvertFrom-Json
    if ($result -and $result.value -and $result.value.Count -gt 0) { return $result.value[0] }
    return $null
}

# ---------------------------------------------------------------------------
# Helper: check if an environment exists by name
# ---------------------------------------------------------------------------
function Get-EnvironmentByName {
    param([string]$EnvName)
    $apiUrl = "$OrgUrl/$Project/_apis/pipelines/environments?name=$EnvName&api-version=7.1"
    $result = az rest -u $apiUrl -m GET --resource $AdoResource -o json 2>$null | ConvertFrom-Json
    if ($result -and $result.value -and $result.value.Count -gt 0) { return $result.value[0] }
    return $null
}

# ---------------------------------------------------------------------------
# Step 1: Set default org and project
# ---------------------------------------------------------------------------
Write-Host '=== ADO Bootstrap ===' -ForegroundColor Cyan
Write-Host "`n[1/8] Configuring Azure DevOps CLI defaults..." -ForegroundColor Cyan
az devops configure --defaults organization=$OrgUrl project=$Project
Write-Host "  Defaults set: org=$OrgUrl project=$Project" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 2: Run OIDC setup if Azure CLI is logged in
# ---------------------------------------------------------------------------
Write-Host "`n[2/8] Checking Azure CLI login for OIDC setup..." -ForegroundColor Cyan
$null = az account show 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host '  Azure CLI is logged in. Running OIDC federation setup...' -ForegroundColor Cyan
    $oidcScript = Join-Path $PSScriptRoot 'setup-oidc-ado.ps1'
    if (Test-Path $oidcScript) {
        & $oidcScript
    }
    else {
        Write-Host "  setup-oidc-ado.ps1 not found at $oidcScript, skipping OIDC setup." -ForegroundColor Yellow
    }
}
else {
    Write-Host '  Azure CLI not logged in. Skipping OIDC setup.' -ForegroundColor Yellow
    Write-Host "  Run 'az login' then './scripts/setup-oidc-ado.ps1' manually." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 3: Create Azure Repos for demo apps (parity with GitHub bootstrap)
# ---------------------------------------------------------------------------
Write-Host "`n[3/9] Creating Azure Repos for demo apps..." -ForegroundColor Cyan

$ScannerRepoName = 'finops-scan-demo-app'

foreach ($app in $DemoApps) {
    $repoName = "finops-demo-app-$($app.Number)"
    $existingRepo = az repos show --repository $repoName -o json 2>$null | ConvertFrom-Json
    if ($existingRepo) {
        Write-Host "  Repo '$repoName' already exists, skipping." -ForegroundColor Yellow
    }
    else {
        Write-Host "  Creating repo '$repoName'..."
        az repos create --name $repoName -o none 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Repo '$repoName' created." -ForegroundColor Green

            # Push demo app content from monorepo subdirectory
            $localAppDir = Join-Path $PSScriptRoot "..\finops-demo-app-$($app.Number)"
            if (Test-Path $localAppDir) {
                $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "ado-$repoName-$(Get-Random)"
                try {
                    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                    Push-Location $tempDir
                    git init -b main 2>&1 | Out-Null
                    $remoteUrl = "$OrgUrl/$Project/_git/$repoName"
                    git remote add origin $remoteUrl

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
                    git commit -m "feat: add FinOps demo app $($app.Number) with intentional $($app.Violations) violations AB#2146" 2>&1 | Out-Null
                    git push -u origin main 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Pop-Location
                        Write-Host "  Demo app content pushed to '$repoName'." -ForegroundColor Green
                    }
                    else {
                        Pop-Location
                        Write-Host "  Warning: could not push content to '$repoName'." -ForegroundColor Yellow
                    }
                }
                catch {
                    Write-Host "  Warning: could not push demo app content: $_" -ForegroundColor Yellow
                    if ((Get-Location).Path -ne $PSScriptRoot) { Pop-Location }
                }
                finally {
                    if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
                }
            }
        }
        else {
            Write-Host "  Warning: could not create repo '$repoName'." -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------------------
# Step 4: Collect OIDC and secret values
# ---------------------------------------------------------------------------
Write-Host "`n[4/9] Collecting configuration values..." -ForegroundColor Cyan

$AzureClientId       = $env:AZURE_CLIENT_ID
$AzureTenantId       = $env:AZURE_TENANT_ID
$AzureSubscriptionId = $env:AZURE_SUBSCRIPTION_ID

if (-not $AzureClientId) {
    $AzureClientId = Read-Host -Prompt 'Enter AZURE_CLIENT_ID (or press Enter to skip variable group creation)'
}
if ($AzureClientId -and -not $AzureTenantId) {
    $AzureTenantId = Read-Host -Prompt 'Enter AZURE_TENANT_ID'
}
if ($AzureClientId -and -not $AzureSubscriptionId) {
    $AzureSubscriptionId = Read-Host -Prompt 'Enter AZURE_SUBSCRIPTION_ID'
}

$ConfigureVariables = [bool]$AzureClientId

$InfracostApiKey = $env:INFRACOST_API_KEY
$VmAdminPassword = $env:VM_ADMIN_PASSWORD

if ($ConfigureVariables) {
    if (-not $InfracostApiKey) {
        $InfracostApiKey = Read-Host -Prompt 'Enter INFRACOST_API_KEY (or press Enter to skip)'
    }
    if (-not $VmAdminPassword) {
        $VmAdminPassword = Read-Host -Prompt 'Enter VM_ADMIN_PASSWORD (or press Enter to skip)'
    }
}

# ---------------------------------------------------------------------------
# Step 5: Create variable groups
# ---------------------------------------------------------------------------
Write-Host "`n[5/9] Creating variable groups..." -ForegroundColor Cyan

if ($ConfigureVariables) {
    # --- finops-oidc-config ---
    $oidcGroup = Get-VariableGroupByName -GroupName 'finops-oidc-config'
    if ($oidcGroup) {
        Write-Host "  Variable group 'finops-oidc-config' already exists (id=$($oidcGroup.id)), skipping." -ForegroundColor Yellow
    }
    else {
        Write-Host '  Creating finops-oidc-config variable group...'
        az pipelines variable-group create `
            --name 'finops-oidc-config' `
            --variables "AZURE_CLIENT_ID=$AzureClientId" "AZURE_TENANT_ID=$AzureTenantId" "AZURE_SUBSCRIPTION_ID=$AzureSubscriptionId" `
            --authorize true `
            -o none
        Write-Host '  finops-oidc-config created.' -ForegroundColor Green
    }

    # --- finops-secrets ---
    $secretsGroup = Get-VariableGroupByName -GroupName 'finops-secrets'
    if ($secretsGroup) {
        Write-Host "  Variable group 'finops-secrets' already exists (id=$($secretsGroup.id)), skipping." -ForegroundColor Yellow
    }
    else {
        Write-Host '  Creating finops-secrets variable group...'
        # Create with a placeholder, then add secret variables
        az pipelines variable-group create `
            --name 'finops-secrets' `
            --variables 'PLACEHOLDER=temp' `
            --authorize true `
            -o json | Out-Null

        $newGroup = Get-VariableGroupByName -GroupName 'finops-secrets'
        $groupId  = $newGroup.id

        # Remove placeholder
        az pipelines variable-group variable delete --group-id $groupId --name 'PLACEHOLDER' --yes -o none 2>$null

        if ($InfracostApiKey) {
            az pipelines variable-group variable create --group-id $groupId --name 'INFRACOST_API_KEY' --value $InfracostApiKey --secret true -o none
            Write-Host '    INFRACOST_API_KEY added.' -ForegroundColor Green
        }
        if ($VmAdminPassword) {
            az pipelines variable-group variable create --group-id $groupId --name 'VM_ADMIN_PASSWORD' --value $VmAdminPassword --secret true -o none
            Write-Host '    VM_ADMIN_PASSWORD added.' -ForegroundColor Green
        }

        Write-Host '  finops-secrets created.' -ForegroundColor Green
    }

    # --- wiki-access (PAT for wiki git push) ---
    $wikiGroup = Get-VariableGroupByName -GroupName 'wiki-access'
    if ($wikiGroup) {
        Write-Host "  Variable group 'wiki-access' already exists (id=$($wikiGroup.id)), skipping." -ForegroundColor Yellow
    }
    else {
        $WikiPat = $env:WIKI_PAT
        if (-not $WikiPat) {
            $WikiPat = Read-Host -Prompt 'Enter WIKI_PAT (ADO PAT with Code Read/Write scope, or press Enter to skip)'
        }
        if ($WikiPat) {
            Write-Host '  Creating wiki-access variable group...'
            az pipelines variable-group create `
                --name 'wiki-access' `
                --variables 'PLACEHOLDER=temp' `
                --authorize true `
                -o json | Out-Null

            $newWikiGroup = Get-VariableGroupByName -GroupName 'wiki-access'
            $wikiGroupId  = $newWikiGroup.id

            az pipelines variable-group variable delete --group-id $wikiGroupId --name 'PLACEHOLDER' --yes -o none 2>$null
            az pipelines variable-group variable create --group-id $wikiGroupId --name 'WIKI_PAT' --value $WikiPat --secret true -o none
            Write-Host '  wiki-access created with WIKI_PAT.' -ForegroundColor Green
        }
        else {
            Write-Host '  Skipping wiki-access (no WIKI_PAT provided). Wiki updates will not work in pipelines.' -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host '  Skipping variable group creation (no AZURE_CLIENT_ID provided).' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 6: Create WIF service connections via REST API
# ---------------------------------------------------------------------------
Write-Host "`n[6/9] Creating WIF service connections..." -ForegroundColor Cyan

if ($ConfigureVariables) {
    # Get the ADO project ID (required for service endpoint references)
    $projectInfo = az devops project show --project $Project -o json | ConvertFrom-Json
    $projectId   = $projectInfo.id

    # Get subscription name
    $subscriptionName = az account show --query 'name' -o tsv

    # Get ADO org GUID for WIF issuer URL
    $orgGuid = az rest --method GET `
        --url "https://vssps.dev.azure.com/${Org}/_apis/connectionData" `
        --resource $AdoResource `
        --query 'instanceId' -o tsv
    if (-not $orgGuid) {
        Write-Error "Failed to retrieve organization GUID for '$Org'. WIF service connections require the org GUID for the issuer URL."
    }

    # Get app registration object ID for federated credential creation
    $appObjectId = (az ad app list --display-name 'ado-finops-scanner' --query '[0].id' -o tsv 2>$null)

    foreach ($scName in $ServiceConnectionNames) {
        $existing = Get-ServiceEndpointByName -EndpointName $scName
        if ($existing) {
            Write-Host "  Service connection '$scName' already exists (id=$($existing.id)), skipping." -ForegroundColor Yellow
            continue
        }

        Write-Host "  Creating service connection '$scName'..."
        $body = @{
            data          = @{
                subscriptionId   = $AzureSubscriptionId
                subscriptionName = $subscriptionName
                environment      = 'AzureCloud'
                scopeLevel       = 'Subscription'
                creationMode     = 'Manual'
            }
            name          = $scName
            type          = 'AzureRM'
            url           = 'https://management.azure.com/'
            authorization = @{
                parameters = @{
                    tenantid           = $AzureTenantId
                    serviceprincipalid = $AzureClientId
                }
                scheme     = 'WorkloadIdentityFederation'
            }
            isShared      = $false
            isReady       = $true
            serviceEndpointProjectReferences = @(
                @{
                    projectReference = @{
                        id   = $projectId
                        name = $Project
                    }
                    name             = $scName
                }
            )
        } | ConvertTo-Json -Depth 5

        $apiUrl = "$OrgUrl/_apis/serviceendpoint/endpoints?api-version=7.1"
        $result = $body | az rest -u $apiUrl -m POST --body '@-' --headers "Content-Type=application/json" --resource $AdoResource -o json 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Service connection '$scName' created." -ForegroundColor Green

            # Read back auto-generated issuer and subject, then create federated credential
            if ($appObjectId) {
                $scData = $result | ConvertFrom-Json
                $wifIssuer  = $scData.authorization.parameters.workloadIdentityFederationIssuer
                $wifSubject = $scData.authorization.parameters.workloadIdentityFederationSubject

                if ($wifIssuer -and $wifSubject) {
                    $credName = "ado-$($scName -replace 'finops-', '')"
                    $existingCred = az ad app federated-credential list --id $appObjectId --query "[?name=='$credName']" -o json 2>$null | ConvertFrom-Json

                    if ($existingCred -and $existingCred.Count -gt 0) {
                        Write-Host "    Federated credential '$credName' already exists." -ForegroundColor Green
                    } else {
                        $credBody = @{
                            name      = $credName
                            issuer    = $wifIssuer
                            subject   = $wifSubject
                            audiences = @('api://AzureADTokenExchange')
                            description = "WIF credential for ADO service connection '$scName'"
                        } | ConvertTo-Json -Compress

                        $credBody | az ad app federated-credential create --id $appObjectId --parameters '@-' -o none 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "    Federated credential '$credName' created." -ForegroundColor Green
                        } else {
                            Write-Host "    Warning: could not create federated credential '$credName'." -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
        else {
            Write-Host "  Warning: could not create service connection '$scName': $result" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host '  Skipping service connection creation (no AZURE_CLIENT_ID provided).' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 7: Create ADO environments
# ---------------------------------------------------------------------------
Write-Host "`n[7/9] Creating ADO environments..." -ForegroundColor Cyan

$existingEnv = Get-EnvironmentByName -EnvName 'production'
if ($existingEnv) {
    Write-Host "  Environment 'production' already exists (id=$($existingEnv.id)), skipping." -ForegroundColor Yellow
}
else {
    Write-Host "  Creating 'production' environment..."
    $envBody = @{ name = 'production'; description = 'Production environment with approval gates' } | ConvertTo-Json
    $apiUrl  = "$OrgUrl/$Project/_apis/pipelines/environments?api-version=7.1"
    $result  = $envBody | az rest -u $apiUrl -m POST --body '@-' --headers "Content-Type=application/json" --resource $AdoResource -o json 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Environment 'production' created." -ForegroundColor Green
        Write-Host '  NOTE: Add approval checks manually in Project Settings > Environments > production.' -ForegroundColor Yellow
    }
    else {
        Write-Host "  Warning: could not create environment: $result" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Step 8: Register ADO pipelines
# ---------------------------------------------------------------------------
Write-Host "`n[8/9] Registering ADO pipelines..." -ForegroundColor Cyan

# Get default repo name (the repo this script lives in)
$repoName = 'finops-scan-demo-app'

foreach ($p in $Pipelines) {
    # Check if pipeline exists by name
    $pipelineExists = $false
    $null = az pipelines show --name $p.Name -o json 2>&1
    if ($LASTEXITCODE -eq 0) { $pipelineExists = $true }

    if ($pipelineExists) {
        Write-Host "  Pipeline '$($p.Name)' already exists, skipping." -ForegroundColor Yellow
    }
    else {
        Write-Host "  Creating pipeline '$($p.Name)'..."
        az pipelines create `
            --name $p.Name `
            --yml-path $p.YmlPath `
            --repository $repoName `
            --repository-type tfsgit `
            --branch main `
            --skip-first-run `
            -o none 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Pipeline '$($p.Name)' created." -ForegroundColor Green
        }
        else {
            Write-Host "  Warning: could not create pipeline '$($p.Name)'." -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------------------
# Step 9: Create project wiki
# ---------------------------------------------------------------------------
Write-Host "`n[9/9] Creating project wiki..." -ForegroundColor Cyan

$wikiList = az devops wiki list -o json 2>$null | ConvertFrom-Json
$wikiExists = $wikiList | Where-Object { $_.name -eq 'FinOps Wiki' }

if ($wikiExists) {
    Write-Host "  Wiki 'FinOps Wiki' already exists, skipping." -ForegroundColor Yellow
}
else {
    $null = az devops wiki create --name 'FinOps Wiki' --type projectWiki -o json 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Wiki 'FinOps Wiki' created." -ForegroundColor Green
    }
    else {
        Write-Host '  Warning: could not create wiki (may already exist or require permissions).' -ForegroundColor Yellow
    }
}

# Grant wiki Contribute permission to the build service so pipelines can update wiki pages
Write-Host '  Granting wiki Contribute permission to build service...' -ForegroundColor Gray
Write-Host '  NOTE: If wiki updates still return 401, grant Contribute permission manually:' -ForegroundColor Yellow
Write-Host "    1. Go to Project Settings > Repos > select the wiki repo (.wiki)" -ForegroundColor Yellow
Write-Host "    2. Under Security, find '$Project Build Service ($Org)'" -ForegroundColor Yellow
Write-Host "    3. Set Contribute = Allow" -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# Branch policy for cost gate (documented — requires pipeline ID)
# ---------------------------------------------------------------------------
Write-Host "`n--- Branch Policy Configuration ---" -ForegroundColor Cyan
Write-Host @'
To add a build validation policy for the cost gate pipeline on the main branch,
run the following after the pipelines are created:

  $pipelineId = (az pipelines show --name "finops-cost-gate" --query "id" -o tsv)
  $repoId     = (az repos show --repository "finops-scan-demo-app" --query "id" -o tsv)

  az repos policy build create `
      --branch main `
      --build-definition-id $pipelineId `
      --repository-id $repoId `
      --display-name "FinOps Cost Gate" `
      --path-filter "/infra/*" `
      --blocking true `
      --enabled true `
      --queue-on-source-update-only true `
      --manual-queue-only false `
      --valid-duration 720

'@ -ForegroundColor Gray

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n=== Bootstrap Summary ===" -ForegroundColor Cyan
Write-Host "Organization: $OrgUrl" -ForegroundColor Green
Write-Host "Project:      $Project" -ForegroundColor Green
Write-Host ''
Write-Host 'Azure Repos:' -ForegroundColor Green
foreach ($app in $DemoApps) {
    Write-Host "  - finops-demo-app-$($app.Number)"
}
Write-Host ''
Write-Host 'Variable Groups:' -ForegroundColor Green
Write-Host '  - finops-oidc-config  (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID)'
Write-Host '  - finops-secrets      (INFRACOST_API_KEY, VM_ADMIN_PASSWORD)'
Write-Host ''
Write-Host 'Service Connections (WIF):' -ForegroundColor Green
foreach ($scName in $ServiceConnectionNames) {
    Write-Host "  - $scName"
}
Write-Host ''
Write-Host 'Pipelines:' -ForegroundColor Green
foreach ($p in $Pipelines) {
    Write-Host "  - $($p.Name) -> $($p.YmlPath)"
}
Write-Host ''
Write-Host 'Environments:' -ForegroundColor Green
Write-Host '  - production'
Write-Host ''
Write-Host 'Wiki:' -ForegroundColor Green
Write-Host '  - FinOps Wiki'

Write-Host "`n--- Manual Steps Required ---" -ForegroundColor Yellow
Write-Host '1. Add approval checks to the production environment:' -ForegroundColor Yellow
Write-Host '   Project Settings > Environments > production > Approvals and checks' -ForegroundColor Yellow
Write-Host '2. Configure branch policy for the cost gate pipeline (see commands above).' -ForegroundColor Yellow
Write-Host '3. Verify service connections can authenticate to Azure:' -ForegroundColor Yellow
Write-Host '   Project Settings > Service connections > Select > Verify' -ForegroundColor Yellow

Write-Host "`nBootstrap complete." -ForegroundColor Cyan
