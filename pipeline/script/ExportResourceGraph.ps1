# Connect-AzAccount

param(
    [Parameter(Mandatory = $true)]
    [string]$KustoQueryFilepath,
    [Parameter(Mandatory = $false)]
    [bool]$ExportCsvFormat = $false,
    [Parameter(Mandatory = $false)]
    [bool]$ExportJsonFormat = $false,
    [Parameter(Mandatory = $false)]
    [bool]$ExportIndividualJson = $false,
    [Parameter(Mandatory = $true)]
    [string]$OutputFolderName,
    [Parameter(Mandatory = $true)]
    [string]$ExportFileName,
    [Parameter(Mandatory = $false)]
    [bool]$ZipOutput = $false
)


# Add this function to handle file zipping
function Compress-OutputFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    # Create zip file path (same name with .zip extension)
    $zipPath = [System.IO.Path]::ChangeExtension($FilePath, "zip")
    
    # Ensure the System.IO.Compression namespace is available
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    # Create the zip file
    Write-Host "Creating zip file: $zipPath"
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    
    # Get just the filename without path
    $fileName = [System.IO.Path]::GetFileName($FilePath)
    
    # Create the zip and add the file
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
    $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
    $entry = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $FilePath, $fileName, $compressionLevel)
    $zip.Dispose()
    
    # Remove the original file
    Write-Host "Removing original file: $FilePath"
    Remove-Item $FilePath -Force
    
    return $zipPath
}

function Compress-OutputFolder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FolderPath
    )
    
    # Create zip file path
    $zipPath = "$FolderPath.zip"
    
    # Ensure the System.IO.Compression namespace is available
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    # Create the zip file
    Write-Host "Creating zip file from folder: $zipPath"
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    
    # Zip all files in the folder
    [System.IO.Compression.ZipFile]::CreateFromDirectory($FolderPath, $zipPath, 
        [System.IO.Compression.CompressionLevel]::Optimal, $false)
    
    # Remove the original folder
    Write-Host "Removing original folder: $FolderPath"
    Remove-Item $FolderPath -Recurse -Force
    
    return $zipPath
}

function ResourceGraphQueryAndExportToCsv {
    param (
        [string]$kqlQuery,
        [string]$csvFilePath = $null,
        [string]$jsonFilePath = $null,
        [string]$individualJsonFolder = $null
    )

    $batchSize = 1000
    $skipResult = 0
    $kqlResultCount = 0

    $graphResult = $null

    # Prepare for streaming storage if needed
    $streamJsonFile = $null
    if ($jsonFilePath) {
        # Make path relative to current working directory if not absolute
        if (-not [System.IO.Path]::IsPathRooted($jsonFilePath)) {
            $jsonFilePath = Join-Path -Path (Get-Location) -ChildPath $jsonFilePath
        }
        Write-Host "Opening JSON output file for streaming: $jsonFilePath"
        $streamJsonFile = [System.IO.StreamWriter]::new($jsonFilePath, $false, [System.Text.Encoding]::UTF8)
        $streamJsonFile.WriteLine('[')
    }

    $firstBatch = $true
    $firstCsvBatch = $true
    $hasMoreResults = $true

    Write-Host "Query: $kqlQuery"

    while ($hasMoreResults) {
        if ($skipResult -gt 0) {
            Write-Host "Processing next batch of $batchSize records. Current total: $($kqlResultCount)"
            # For subsequent batches, we use -Skip to get the next set of results
            # We use -ErrorAction Continue to avoid stopping the script on errors
            $graphResult = Search-AzGraph -Query $kqlQuery -First $batchSize -Skip $skipResult -UseTenantScope -ErrorAction Continue
        }
        else {
            Write-Host "Processing first batch of $batchSize records"
            # if there's an error on the first run, we want to stop the script
            # so we use -ErrorAction Stop to catch it
            $graphResult = Search-AzGraph -Query $kqlQuery -First $batchSize -UseTenantScope -ErrorAction Stop
        }

        if ($null -eq $graphResult -or $null -eq $graphResult.data -or $graphResult.data.Count -eq 0) {
            Write-Host "No data returned from Search-AzGraph. Ending batch processing."
            $hasMoreResults = $false
            continue
        }

        $batchObjects = @()
        foreach ($item in $graphResult.data) {
            $kqlResultCount++
            $batchObjects += $item
            if ($jsonFilePath) {
                if (-not $firstBatch) { $streamJsonFile.WriteLine(',') }
                $streamJsonFile.Write((ConvertTo-Json $item -Depth 40))
                $firstBatch = $false
            }
            if ($individualJsonFolder) {
                if (-not (Test-Path $individualJsonFolder)) {
                    New-Item -ItemType Directory -Path $individualJsonFolder | Out-Null
                }
                if ($item.PSObject.Properties["id"] -and $item.id) {
                    # Replace all non-alphanumeric characters with "_"
                    $fileName = ($item.id -replace '[^a-zA-Z0-9]', '_')
                    if ($fileName.StartsWith('_')) { $fileName = $fileName.Substring(1) }
                    $maxLength = 250 - 40 # Reserve space for hash and extension
                    if ($fileName.Length -gt $maxLength) {
                        # Compute hash of original filename
                        $hash = [System.BitConverter]::ToString((New-Object -TypeName System.Security.Cryptography.SHA256Managed).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($fileName))).Replace("-", "").Substring(0, 16)
                        $fileName = $fileName.Substring(0, $maxLength) + "_" + $hash
                    }
                    $fileName += ".json"
                    $filePath = Join-Path $individualJsonFolder $fileName
                    $item | ConvertTo-Json -Depth 20 | Set-Content -Path $filePath -Force
                }
            }
        }

        # Stream CSV batch to file
        if ($csvFilePath -and $batchObjects.Count -gt 0) {
            $flattened = $batchObjects | ForEach-Object {
                $obj = [ordered]@{}
                foreach ($prop in $_.PSObject.Properties) {
                    if ($prop.Value -is [System.Collections.IEnumerable] -and $prop.Value -notlike '*[System.*]*' -and $prop.Value -isnot [string]) {
                        $obj[$prop.Name] = $prop.Value -join '; '
                    }
                    else {
                        $obj[$prop.Name] = $prop.Value
                    }
                }
                [PSCustomObject]$obj
            }
            if ($firstCsvBatch) {
                $flattened | Export-Csv -Path $csvFilePath -NoTypeInformation -Force
                $firstCsvBatch = $false
            }
            else {
                $flattened | Export-Csv -Path $csvFilePath -NoTypeInformation -Append
            }
        }


        $hasMoreResults = $graphResult.data.Count -eq $batchSize

        if ($hasMoreResults) {
            $skipResult += $batchSize
        }
    }

    if ($jsonFilePath -and $streamJsonFile) {
        $streamJsonFile.WriteLine(']')
        $streamJsonFile.Close()
    }

    Write-Host "Total records processed: $($kqlResultCount)"
}

# Prepare output paths based on parameters
$csvFilePath = if ($ExportCsvFormat) { Join-Path $OutputFolderName ("$ExportFileName.csv") } else { $null }
$jsonFilePath = if ($ExportJsonFormat) { Join-Path $OutputFolderName ("$ExportFileName.json") } else { $null }
$individualJsonFolder = if ($ExportIndividualJson) { Join-Path $OutputFolderName ("${ExportFileName}_json") } else { $null }

# Ensure output folder exists (for all output types) with logging
foreach ($folder in @($OutputFolderName, $individualJsonFolder)) {
    if ($folder -and -not (Test-Path $folder)) {
        Write-Host "Creating output folder: $folder"
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    elseif ($folder) {
        Write-Host "Output folder already exists: $folder"
    }
}

Write-Host "Processing file $KustoQueryFilepath..."
$kqlQuery = Get-Content -Path $KustoQueryFilepath -Raw
ResourceGraphQueryAndExportToCsv -kqlQuery $kqlQuery -csvFilePath $csvFilePath -jsonFilePath $jsonFilePath -individualJsonFolder $individualJsonFolder

# Handle zipping of output files if requested
if ($ZipOutput) {
    Write-Host "Compressing output files..."
    
    # Zip CSV if it exists
    if ($ExportCsvFormat -and (Test-Path $csvFilePath)) {
        $zippedCsvPath = Compress-OutputFile -FilePath $csvFilePath
        Write-Host "Compressed CSV to: $zippedCsvPath"
    }
    
    # Zip JSON if it exists
    if ($ExportJsonFormat -and (Test-Path $jsonFilePath)) {
        $zippedJsonPath = Compress-OutputFile -FilePath $jsonFilePath
        Write-Host "Compressed JSON to: $zippedJsonPath"
    }
    
    # Zip individualJson folder if it exists
    if ($ExportIndividualJson -and (Test-Path $individualJsonFolder)) {
        $zippedFolderPath = Compress-OutputFolder -FolderPath $individualJsonFolder
        Write-Host "Compressed individual JSON files to: $zippedFolderPath"
    }
}