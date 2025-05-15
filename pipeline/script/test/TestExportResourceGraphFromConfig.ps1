# Test script for ExportResourceGraphFromConfig.ps1 using test.yaml

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$testConfig = Join-Path $scriptDir '../config/test.yaml'
$outputRoot = './output'

# Parse test.yaml to get query names and expected outputs
Import-Module powershell-yaml
$config = ConvertFrom-Yaml (Get-Content $testConfig -Raw)

$allPassed = $true

foreach ($query in $config.queries) {
    $queryName = $query.name
    $outputFilename = $query.outputFilename
    $extractTypes = $query.extractType
    $outputFolder = if ($query.outputFolder) { $query.outputFolder } else { '' }
    $zipOutput = if ($null -ne $query.zipOutput) { [bool]$query.zipOutput } else { $false }
    $expectedFiles = @()
      # Determine expected files based on extraction type and zip setting
    if ($extractTypes -contains 'csv') { 
        if ($zipOutput) {
            $expectedFiles += Join-Path $outputRoot ("$outputFilename.zip") 
        } else {
            $expectedFiles += Join-Path $outputRoot ("$outputFilename.csv")
        }
    }
    if ($extractTypes -contains 'json') { 
        if ($zipOutput) {
            $expectedFiles += Join-Path $outputRoot ("$outputFilename.zip")
        } else {
            $expectedFiles += Join-Path $outputRoot ("$outputFilename.json")
        }
    }    if ($extractTypes -contains 'individualJson') {
        if ($zipOutput) {
            $expectedFiles += Join-Path $outputRoot ("${outputFilename}_json.zip")
        } else {
            $expectedFiles += Join-Path $outputRoot ("${outputFilename}_json")
        }
    }Write-Host "`n--- Testing query: $queryName ---"    # Run the export script for this query
    # Clean up any existing output files first
    foreach ($file in $expectedFiles) {
        if (Test-Path $file) {
            Write-Host "Removing existing file: $file"
            if ($file -like "*_json") {
                Remove-Item $file -Recurse -Force
            } else {
                Remove-Item $file -Force
            }
        }
    }
    
    # Run the export script
    & (Join-Path $scriptDir '../ExportResourceGraphFromConfig.ps1') -ConfigFileName "test.yaml" -QueryName $queryName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Export script failed for query $queryName"
        $allPassed = $false
        continue
    }
    
    # Validate output files/folders
    foreach ($file in $expectedFiles) {
        # Handle regular CSV/JSON files
        if ($file -like "*.csv" -or $file -like "*.json") {
            if (-not (Test-Path $file)) {
                Write-Host "[FAIL] Expected file not found: $file"
                $allPassed = $false
                continue
            }
            $lines = Get-Content $file
            if ($lines.Count -le 2) {
                Write-Host "[FAIL] File $file has $($lines.Count) lines (expected > 2)"
                $allPassed = $false
            } else {
                Write-Host "[PASS] File $file exists and has $($lines.Count) lines."
            }
        }
        # Handle ZIP files
        elseif ($file -like "*.zip") {
            if (-not (Test-Path $file)) {
                Write-Host "[FAIL] Expected ZIP file not found: $file"
                $allPassed = $false
                continue
            }
              # Check if the zip file has content
            try {
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                $zip = [System.IO.Compression.ZipFile]::OpenRead($file)
                $entriesCount = $zip.Entries.Count
                $zip.Dispose()
                
                if ($entriesCount -eq 0) {
                    Write-Host "[FAIL] ZIP file $file has no entries"
                    $allPassed = $false
                } else {
                    Write-Host "[PASS] ZIP file $file exists and has $entriesCount entries."
                }            } 
            catch {
                $errorMsg = $_.Exception.Message
                Write-Host ("[FAIL] Error checking ZIP file {0}: {1}" -f $file, $errorMsg)
                $allPassed = $false
            }
        }
        # Handle folders (individualJson)
        elseif (Test-Path $file) {
            # For individualJson, check that the folder exists and has at least 1 file
            $jsonFiles = Get-ChildItem -Path $file -Filter *.json -File -Recurse -ErrorAction SilentlyContinue
            if ($jsonFiles.Count -eq 0) {
                Write-Host "[FAIL] No JSON files found in $file"
                $allPassed = $false
            } else {
                Write-Host "[PASS] $($jsonFiles.Count) JSON files found in $file."
            }
        } else {
            Write-Host "[FAIL] Expected output folder not found: $file"
            $allPassed = $false
        }
    }

    # # Clean up
    # foreach ($file in $expectedFiles) {
    #     if ($file -like "*.json" -or $file -like "*.csv") {
    #         if (Test-Path $file) { Remove-Item $file -Force }
    #     } elseif (Test-Path $file) {
    #         Remove-Item $file -Recurse -Force
    #     }
    # }
}

if ($allPassed) {
    Write-Host "`nAll tests passed."
    exit 0
} else {
    Write-Host "`nSome tests failed."
    exit 1
}
