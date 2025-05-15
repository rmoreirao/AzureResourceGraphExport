param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    [Parameter(Mandatory=$true)]
    [string]$ContainerName,
    [Parameter(Mandatory=$true)]
    [string]$BlobDestinationFolderName
)

# Ensure container exists
Write-Host "Ensuring container $ContainerName exists..."
New-AzStorageContainer -Name $ContainerName -Context (New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount) -ErrorAction SilentlyContinue

# Set destination path
$destinationPath = $BlobDestinationFolderName
if ($BlobDestinationFolderName -ne "" -and -not $BlobDestinationFolderName.EndsWith('/')) {
    $destinationPath += '/'
}

$storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount

if (Test-Path $Path -PathType Container) {
    # Folder: upload all files recursively
    Write-Host "Uploading folder $Path to container $ContainerName with prefix $destinationPath..."
    
    $files = Get-ChildItem $Path -Recurse -File
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($Path.Length).TrimStart('\', '/')
        $blobName = "$destinationPath$relativePath".Replace('\', '/')
        
        Write-Host "Uploading $($file.FullName) to $blobName"
        Set-AzStorageBlobContent -File $file.FullName -Container $ContainerName -Blob $blobName -Context $storageContext -Force | Out-Null
    }
} 
elseif (Test-Path $Path -PathType Leaf) {
    # Single file
    $fileName = Split-Path $Path -Leaf
    $blobName = "$destinationPath$fileName"
    
    Write-Host "Uploading file $Path to container $ContainerName as $blobName..."
    Set-AzStorageBlobContent -File $Path -Container $ContainerName -Blob $blobName -Context $storageContext -Force | Out-Null
} 
else {
    Write-Host "[ERROR] Path not found: $Path"
    exit 1
}

Write-Host "Upload complete."