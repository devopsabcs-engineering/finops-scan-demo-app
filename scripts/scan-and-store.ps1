<#
.SYNOPSIS
    Transforms SARIF scan results to FinOps schema and uploads to Azure Blob Storage.

.DESCRIPTION
    Parses SARIF v2.1.0 files from PSRule, Checkov, and Cloud Custodian scans,
    maps each finding to the Fact_FinOpsFindings schema, and uploads date-partitioned
    JSON files to Azure Blob Storage using Entra ID authentication.

.PARAMETER StorageAccount
    Azure Storage Account name for blob upload.

.PARAMETER ContainerName
    Blob container name within the storage account.

.PARAMETER AppIds
    Comma-separated list of demo app identifiers (e.g. "001,002,003,004,005").
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $StorageAccount,
    [Parameter(Mandatory)] [string] $ContainerName,
    [Parameter(Mandatory)] [string] $AppIds
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Constants ---
$ScanRunId  = [guid]::NewGuid().ToString()
$ScanDate   = (Get-Date).ToUniversalTime().ToString('o')
$DateFolder = (Get-Date).ToUniversalTime().ToString('yyyy/MM/dd')

$SeverityMap = @{
    'error'   = 'Critical'
    'warning' = 'Medium'
    'note'    = 'Low'
}

# --- Helper functions ---

function Get-Sha256Hash {
    param([string] $InputString)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
        $hash  = $sha.ComputeHash($bytes)
        return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertFrom-SarifFile {
    <#
    .SYNOPSIS
        Parses a single SARIF v2.1.0 file into Fact_FinOpsFindings objects.
    #>
    param(
        [string] $Path,
        [string] $AppId
    )

    if (-not (Test-Path $Path)) {
        Write-Warning "SARIF file not found: $Path"
        return @()
    }

    $sarif = Get-Content -Path $Path -Raw | ConvertFrom-Json

    $findings = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($run in $sarif.runs) {
        $toolName = $run.tool.driver.name

        foreach ($result in $run.results) {
            # Handle both ruleId (Checkov, Custodian) and rule.id (PSRule) formats
            $ruleId = if ($result.PSObject.Properties['ruleId'] -and $result.ruleId) {
                $result.ruleId
            }
            elseif ($result.PSObject.Properties['rule'] -and $result.rule.PSObject.Properties['id']) {
                $result.rule.id
            }
            else {
                'UNKNOWN'
            }

            $ruleDescription = ''
            if ($result.PSObject.Properties['message'] -and $result.message.PSObject.Properties['text']) {
                $ruleDescription = $result.message.text
            }

            $levelRaw = if ($result.PSObject.Properties['level']) { $result.level } else { 'warning' }
            $severity = if ($SeverityMap.ContainsKey($levelRaw)) { $SeverityMap[$levelRaw] } else { 'Medium' }

            # Extract location info
            $filePath   = ''
            $lineNumber = 0
            if ($result.PSObject.Properties['locations'] -and $result.locations.Count -gt 0) {
                $loc = $result.locations[0]
                if ($loc.PSObject.Properties['physicalLocation']) {
                    $phys = $loc.physicalLocation
                    if ($phys.PSObject.Properties['artifactLocation'] -and
                        $phys.artifactLocation.PSObject.Properties['uri']) {
                        $filePath = $phys.artifactLocation.uri
                    }
                    if ($phys.PSObject.Properties['region'] -and
                        $phys.region.PSObject.Properties['startLine']) {
                        $lineNumber = [int]$phys.region.startLine
                    }
                }
            }

            $findingId = Get-Sha256Hash -InputString "$ruleId|$filePath|$lineNumber"

            $finding = [PSCustomObject]@{
                FindingId        = $findingId
                RuleId           = $ruleId
                RuleDescription  = $ruleDescription
                Severity         = $severity
                SeverityKey      = $levelRaw
                State            = 'open'
                ToolName         = $toolName
                RepositoryKey    = "finops-demo-app-$AppId"
                ResourceName     = $filePath
                FilePath         = $filePath
                LineNumber       = $lineNumber
                EstimatedSavings = $null
                ScanDate         = $ScanDate
                FixedDate        = $null
                ScanRunId        = $ScanRunId
            }

            $findings.Add($finding)
        }
    }

    return $findings.ToArray()
}

function Upload-ToBlob {
    param(
        [PSCustomObject[]] $Findings,
        [string] $AppId,
        [string] $ToolName,
        [string] $TempDir
    )

    if ($Findings.Count -eq 0) {
        Write-Host "  No findings for $ToolName app $AppId — skipping upload."
        return
    }

    $safeTool     = $ToolName -replace '[^a-zA-Z0-9_-]', ''
    $blobPath     = "$DateFolder/$AppId-$safeTool.json"
    $tempFilePath = Join-Path $TempDir "$AppId-$safeTool.json"

    $Findings | ConvertTo-Json -Depth 10 | Out-File -FilePath $tempFilePath -Encoding utf8

    Write-Host "  Uploading $($Findings.Count) findings → $blobPath"

    $uploadOutput = $null
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        $uploadOutput = az storage blob upload `
            --account-name $StorageAccount `
            --container-name $ContainerName `
            --name $blobPath `
            --file $tempFilePath `
            --auth-mode login `
            --overwrite 2>&1
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
    }
    catch {
        $exitCode = 1
        $ErrorActionPreference = 'Stop'
    }

    if ($exitCode -ne 0) {
        Write-Warning "Upload failed for $blobPath (exit code $exitCode)"
        $script:uploadFailures++
    }
    else {
        Write-Host "  Upload succeeded: $blobPath"
    }
}

# --- Main ---

$script:uploadFailures = 0

Write-Host "=== FinOps Scan-and-Store ==="
Write-Host "ScanRunId   : $ScanRunId"
Write-Host "ScanDate    : $ScanDate"
Write-Host "BlobDatePath: $DateFolder"
Write-Host ""

$appIdList = $AppIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

# Create temp directory for staging JSON files
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "finops-scan-$ScanRunId"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    foreach ($appId in $appIdList) {
        Write-Host "--- Processing app $appId ---"

        # SARIF file paths per scanner (matching finops-scan.yml output naming)
        $sarifFiles = @{
            PSRule          = "reports/psrule-$appId.sarif"
            Checkov         = "reports/checkov-$appId.sarif"
            CloudCustodian  = "results/custodian-$appId.sarif"
            Infracost       = "reports/infracost-$appId.sarif"
        }

        foreach ($entry in $sarifFiles.GetEnumerator()) {
            $scannerLabel = $entry.Key
            $sarifPath    = $entry.Value

            Write-Host "  Scanner: $scannerLabel → $sarifPath"

            $findings = @(ConvertFrom-SarifFile -Path $sarifPath -AppId $appId)

            if ($findings -and $findings.Count -gt 0) {
                # Use the actual tool name from SARIF (not our label) for the blob path
                $actualToolName = $findings[0].ToolName
                Upload-ToBlob -Findings $findings -AppId $appId -ToolName $actualToolName -TempDir $tempDir
            }
            else {
                Write-Host "  No findings or file missing for $scannerLabel."
            }
        }

        Write-Host ""
    }

    Write-Host "=== Scan-and-Store complete ==="
    if ($script:uploadFailures -gt 0) {
        Write-Warning "$($script:uploadFailures) upload(s) failed — check RBAC permissions on the storage account."
    }
}
finally {
    # Clean up temp directory
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Cleaned up temp directory: $tempDir"
    }
}

# Exit 0 even if some uploads failed (warnings already emitted)
exit 0
