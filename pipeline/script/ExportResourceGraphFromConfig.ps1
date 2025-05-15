param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigFileName,
    [Parameter(Mandatory=$false)]
    [string]$QueryName
)

# Requires powershell-yaml module
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host "powershell-yaml module not found. Installing..."
    Install-Module -Name powershell-yaml -Force -Scope CurrentUser
}
Import-Module powershell-yaml

$hasError = $false
$errors = @()
$successCount = 0

# Check if QueryName is empty or just whitespace
if ([string]::IsNullOrWhiteSpace($QueryName)) {
    Write-Host "QueryName is empty or contains only whitespace, running all queries"
    $QueryName = $null
} else {
    # Trim any leading/trailing whitespace
    $QueryName = $QueryName.Trim()
    Write-Host "Running only query: '$QueryName'"
}

# Build config file path from name
$ConfigFilePath = Join-Path (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "config") $ConfigFileName

# Load YAML config with logging
Write-Host ("Loading YAML config from: $ConfigFilePath")
try {
    $config = ConvertFrom-Yaml (Get-Content $ConfigFilePath -Raw)
    Write-Host "YAML config loaded successfully."
} catch {
    Write-Host ("[ERROR] Failed to load YAML config: $_")
    exit 1
}

# Determine default output folder if present
$defaultOutputFolder = $null
$defaultZipOutput = $false
if ($config.outputFolder) {
    $defaultOutputFolder = $config.outputFolder
}
if ($null -ne $config.zipOutput) {
    $defaultZipOutput = [bool]$config.zipOutput
}

for ($i = 0; $i -lt $config.queries.Count; $i++) {
    $query = $config.queries[$i]

    Write-Host ("`n--- Processing query $($i): $($query.name) ---")

    if ($QueryName -and $query.name -ne $QueryName) {
        Write-Host ("Skipping query $($query.name) as it does not match the specified QueryName: $QueryName")
        continue
    }
    if (-not $query.file -or -not $query.extractType -or -not $query.outputFilename) {
        $hasError = $true
        
        # Determine which fields are missing
        $missingFields = @()
        if (-not $query.file) { $missingFields += "file" }
        if (-not $query.extractType) { $missingFields += "extractType" }
        if (-not $query.outputFilename) { $missingFields += "outputFilename" }
        
        # Enhanced logging with query details
        $queryName = if ($query.name) { $query.name } else { "unnamed" }
        $missingFieldsStr = $missingFields -join ", "
        
        $errorMsg = "Skipping query at index $i (name: $queryName) due to missing required fields: $missingFieldsStr"
        $errors += $errorMsg
        Write-Host ("[ERROR] $errorMsg")
        
        # Log as much of the query object as possible for debugging
        Write-Host "Query object content:"
        $query | ConvertTo-Json -Depth 1 | Write-Host
        
        continue
    }



    $file = $query.file
    $extractTypes = $query.extractType
    $outputFilename = $query.outputFilename
    $outputFolder = if ($query.outputFolder) { $query.outputFolder } elseif ($defaultOutputFolder) { $defaultOutputFolder } else { "output" }
    
    # Get zipOutput parameter from query or use default
    $zipOutput = if ($null -ne $query.zipOutput) { [bool]$query.zipOutput } else { $defaultZipOutput }

    $ExportCsvFormat = $false
    $ExportJsonFormat = $false
    $ExportIndividualJson = $false
    if ($extractTypes) {
        if ($extractTypes -contains "csv") { $ExportCsvFormat = $true }
        if ($extractTypes -contains "json") { $ExportJsonFormat = $true }
        if ($extractTypes -contains "individualJson") { $ExportIndividualJson = $true }
    }

    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $kqlFilePath = Join-Path $scriptDir "kustoQuery\$file"
    $kqlFilePath = [System.IO.Path]::GetFullPath($kqlFilePath)
    if (-not (Test-Path $kqlFilePath)) {
        $hasError = $true
        $errors += ("KQL file not found: $($kqlFilePath) for query $($file). Skipping.")
        Write-Host ("[ERROR] KQL file not found: $($kqlFilePath) for query $($file). Skipping.")
        continue
    }

    Write-Host ("`n--- Exporting: $($file) ---")
    Write-Host ("    csv: $ExportCsvFormat")
    Write-Host ("    json: $ExportJsonFormat")
    Write-Host ("    individualJson: $ExportIndividualJson")
    Write-Host ("    outputFolder: $outputFolder")
    Write-Host ("    outputFilename: $outputFilename")
    Write-Host ("    kqlFilePath: $kqlFilePath")
    Write-Host ("    zipOutput: $zipOutput")
    
    try {
        $scriptExitCode = 0
        & (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'ExportResourceGraph.ps1') `
            -KustoQueryFilepath $kqlFilePath `
            -ExportCsvFormat:$ExportCsvFormat `
            -ExportJsonFormat:$ExportJsonFormat `
            -ExportIndividualJson:$ExportIndividualJson `
            -OutputFolderName $outputFolder `
            -ExportFileName $outputFilename `
            -ZipOutput:$zipOutput
            
        # Save exit code immediately after running the script
        if ($?) {
            $scriptExitCode = 0  # Success
        } else {
            $scriptExitCode = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 1 }
        }
        
        if ($scriptExitCode -ne 0) {
            $hasError = $true
            $errors += @("Error exporting $file. Script exited with code $scriptExitCode.")
            Write-Host ("[ERROR] Error exporting $file. Script exited with code $scriptExitCode.")
        } else {
            $successCount++
        }
    }
    catch {
        $hasError = $true
        $errors += @("Error exporting $file. $_")
        Write-Host ("[ERROR] $_")
    }
}

if ($hasError) {
    Write-Host "\nSome queries failed to export:"
    $errors | ForEach-Object { Write-Host $_ }
    Write-Host ("\nSuccessfully exported $successCount queries.")
    exit 1
} else {
    Write-Host ("\nAll queries exported successfully. ($successCount queries)")
    exit 0
}
