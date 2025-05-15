# Azure Export Automations

This project provides automation scripts for exporting Azure Resource Graph data to CSV, JSON, and individual JSON files. It supports configurable queries, output formats, and automatic upload to Azure Blob Storage.

## Overview

The Azure Export Automations project enables you to:

- Run queries against Azure Resource Graph
- Export results in multiple formats (CSV, JSON, individual JSON files)
- Compress output files with ZIP option
- Upload results to Azure Blob Storage
- Run as part of Azure DevOps pipelines

## Project Structure

```
├── pipeline/                           # Azure DevOps pipeline definitions
│   ├── pipeline.resource-graph.export.config.template.yml  # Template pipeline
│   ├── pipeline.resource-graph.export.run.yml              # Pipeline runner
│   └── script/                         # PowerShell scripts
│       ├── ExportOutputToAzureBlobStorage.ps1    # Upload to blob storage
│       ├── ExportResourceGraph.ps1               # Core export script
│       ├── ExportResourceGraphFromConfig.ps1     # Config-based runner
│       ├── config/                     # YAML configuration files
│       │   ├── all_extracts.yaml       # Production configuration
│       │   └── test.yaml               # Test configuration
│       ├── kustoQuery/                 # KQL queries organized by domain
│       │   ├── landingZone/            # Management group queries
│       │   ├── policy/                 # Policy-related queries
│       │   ├── recommendation/         # Advisor recommendations
│       │   └── resource/               # Resource queries
│       └── test/                       # Test scripts
│           └── TestExportResourceGraphFromConfig.ps1  # Test script
```

## Usage

### Running Queries from Configuration

To run queries defined in a YAML configuration file:

```powershell
.\pipeline\script\ExportResourceGraphFromConfig.ps1 -ConfigFileName "all_extracts.yaml"
```

To run a specific query from the configuration:

```powershell
.\pipeline\script\ExportResourceGraphFromConfig.ps1 -ConfigFileName "all_extracts.yaml" -QueryName "policyAssignments"
```

### Running Direct Queries

To run a single query directly:

```powershell
.\pipeline\script\ExportResourceGraph.ps1 -KustoQueryFilepath ".\pipeline\script\kustoQuery\policy\policyAssignments.kql" `
    -ExportCsvFormat $true `
    -ExportJsonFormat $true `
    -OutputFolderName "output" `
    -ExportFileName "policyAssignments" `
    -ZipOutput $true
```

### Configuration File Format

The YAML configuration files follow this format:

```yaml
outputFolder: output  # Default output folder for all queries
queries:
  - name: policyAssignments  # Unique name for the query
    file: policy/policyAssignments.kql  # Path to KQL file (relative to kustoQuery folder)
    extractType: [csv, json]  # Output formats (csv, json, individualJson)
    outputFilename: policyAssignments  # Base filename for output
    zipOutput: true  # Whether to compress output files
```

### Azure DevOps Integration

To run in Azure DevOps, create a pipeline using the template:

```yaml
trigger: none

parameters:
  - name: configFileName
    type: string
    default: all_extracts.yaml
  - name: specificQueryName
    type: string
    default: ' '

variables:
  - name: azureServiceConnectionName
    value: 'yourServiceConnection'
  - name: storageAccountName
    value: 'yourstorageaccount'
  - name: containerName
    value: 'resourcegraph'

stages:
- stage: RunExportTemplate
  displayName: 'Run Resource Graph Export Template'
  jobs:
  - template: pipeline/pipeline.resource-graph.export.config.template.yml
    parameters:
      configFileName: ${{ parameters.configFileName }}
      specificQueryName: ${{ parameters.specificQueryName }}
      azureServiceConnectionName: $(azureServiceConnectionName)
      storageAccountName: $(storageAccountName)
      containerName: $(containerName)
      blobDestinationFolderName: $[format('{0:yyyyMMdd}-{1}', pipeline.startTime, variables['Build.BuildId'])]
```

## Features

### Zip Output

The `zipOutput` parameter (available in both script parameters and YAML configuration) enables compression:

- For CSV and JSON files: Creates a ZIP file with the same base name and removes the original file
- For individual JSON folders: Compresses the entire folder into a single ZIP file and removes the original folder

### Output Formats

- **CSV**: Single CSV file with all results
- **JSON**: Single JSON file with all results in an array
- **Individual JSON**: Each resource is saved as a separate JSON file in a folder

## Testing

Run the test script to verify functionality:

```powershell
.\pipeline\script\test\TestExportResourceGraphFromConfig.ps1
```

## Requirements

- PowerShell 7.0+
- Az PowerShell module
- powershell-yaml module (installed automatically if missing)
- Azure authentication with sufficient permissions to query Resource Graph