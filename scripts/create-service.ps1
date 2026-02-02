[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Service name (folder in services/)")]
    [string]$ProjectName,
    
    [Parameter(Mandatory=$false, HelpMessage="Cluster name (e.g., cluster-dev)")]
    [string]$ClusterName,
    
    [Parameter(Mandatory=$false, HelpMessage="Path to kubeseal certificate (.pem)")]
    [string]$CertPath,
    
    [Parameter(Mandatory=$false, HelpMessage="Preview actions without executing")]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false, HelpMessage="Show detailed validation output")]
    [switch]$VerboseOutput
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$libPath = Join-Path $scriptRoot "lib"

if (!(Test-Path (Join-Path $libPath "common.ps1")) -or !(Test-Path (Join-Path $libPath "validation.ps1"))) {
    Write-Error "Required library files not found in $libPath. Please ensure lib/common.ps1 and lib/validation.ps1 exist."
    exit 1
}

. (Join-Path $libPath "common.ps1")
. (Join-Path $libPath "validation.ps1")


function Write-Banner {
    param([string]$Text)
    $border = "=" * 60
    Write-Host ""
    Write-Host $border -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host $border -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "> $Text" -ForegroundColor Yellow
    Write-Host ("-" * 60) -ForegroundColor DarkGray
}

function Get-UserInput {
    param(
        [string]$Prompt,
        [string[]]$Suggestions = @(),
        [bool]$Required = $true
    )
    
    if ($Suggestions.Count -gt 0) {
        Write-Host "`nAvailable options:" -ForegroundColor Cyan
        $Suggestions | ForEach-Object { Write-Host "  * $_" -ForegroundColor Gray }
        Write-Host ""
    }
    
    do {
        $input = Read-Host $Prompt
        $valid = !$Required -or ($input -and $input.Trim() -ne "")
        
        if (!$valid) {
            Write-Host "This field is required. Please enter a value." -ForegroundColor Red
        }
    } while (!$valid)
    
    return $input.Trim()
}

try {
    Clear-Host
    
    Write-Banner "Kubernetes Service Deployment Tool"
    Write-Host "This script will deploy a service configuration to your cluster"
    Write-Host "using GitOps pattern with ArgoCD." -ForegroundColor Gray
    Write-Host ""

    Write-Section "Step 1/6: Checking Dependencies"
    
    try {
        $warnings = Test-Dependencies
        Write-ColorOutput "All required dependencies are installed" -Type Success
        
        if ($warnings -and $warnings.Count -gt 0) {
            foreach ($warning in $warnings) {
                Write-ColorOutput $warning -Type Warning
            }
        }
    }
    catch {
        Write-ColorOutput "Dependency check failed" -Type Error
        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""
        Write-Host "Please install missing dependencies and try again." -ForegroundColor Yellow
        exit 1
    }

    Write-Section "Step 2/6: Locating Project Root"
    
    try {
        $rootDir = Get-ProjectRoot
        Write-ColorOutput "Project root: $rootDir" -Type Success
    }
    catch {
        Write-ColorOutput "Failed to locate project root" -Type Error
        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
    
    Write-Section "Step 3/6: Service Selection"
    
    if (!$ProjectName) {
        $servicesPath = Join-Path $rootDir "services"
        $availableServices = @()
        
        if (Test-Path $servicesPath) {
            $availableServices = Get-ChildItem -Path $servicesPath -Directory | 
                Select-Object -ExpandProperty Name
        }
        
        $ProjectName = Get-UserInput -Prompt "Enter service name" -Suggestions $availableServices
    }
    
    try {
        $serviceDir = Test-ServiceDirectory -ProjectName $ProjectName -RootDir $rootDir
        Write-ColorOutput "Service directory validated: $serviceDir" -Type Success
        
        $serviceConfig = Get-ServiceConfig -ServiceDir $serviceDir
        Test-ServiceSchema -Config $serviceConfig
        
        Write-Host ""
        Write-Host "Service Configuration:" -ForegroundColor Cyan
        Write-Host "  Name: $($serviceConfig.service.name)" -ForegroundColor Gray
        Write-Host "  Image: $($serviceConfig.image.repository):$($serviceConfig.image.tag)" -ForegroundColor Gray
        Write-Host "  Port: $($serviceConfig.network.port)" -ForegroundColor Gray
        Write-Host "  Replicas: $($serviceConfig.replicas)" -ForegroundColor Gray
        
        if ($VerboseOutput) {
            $envValidation = Test-EnvironmentFiles -ServiceDir $serviceDir
            Write-Host "  Environment Variables:" -ForegroundColor Gray
            Write-Host "    Total: $($envValidation.EnvVarCount)" -ForegroundColor Gray
            Write-Host "    Secrets: $($envValidation.SecretVarCount)" -ForegroundColor Gray
            Write-Host "    Config: $($envValidation.ConfigVarCount)" -ForegroundColor Gray
            
            if ($envValidation.Warnings.Count -gt 0) {
                foreach ($warning in $envValidation.Warnings) {
                    Write-ColorOutput $warning -Type Warning
                }
            }
        }
    }
    catch {
        Write-ColorOutput "Service validation failed" -Type Error
        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
    
    Write-Section "Step 4/6: Cluster Selection"
    
    if (!$ClusterName) {
        $availableClusters = Get-ChildItem -Path $rootDir -Filter "cluster-*" -Directory | 
            Select-Object -ExpandProperty Name
        
        $ClusterName = Get-UserInput -Prompt "Enter cluster name" -Suggestions $availableClusters
    }
    
    try {
        $clusterPath = Test-ClusterDirectory -ClusterName $ClusterName -RootDir $rootDir
        Write-ColorOutput "Cluster directory validated: $clusterPath" -Type Success
    }
    catch {
        Write-ColorOutput "Cluster validation failed" -Type Error
        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
    
    Write-Section "Step 5/6: Certificate Selection"
    
    if (!$CertPath) {
        try {
            $CertPath = Get-CertificateFile -RootDir $rootDir -Interactive $true
        }
        catch {
            Write-ColorOutput "Certificate selection failed" -Type Error
            Write-Host ""
            Write-Host $_.Exception.Message -ForegroundColor Red
            exit 1
        }
    }
    else {
        if (!(Test-Path $CertPath)) {
            Write-ColorOutput "Certificate file not found: $CertPath" -Type Error
            exit 1
        }
        $CertPath = Resolve-Path $CertPath
    }
    
    Write-ColorOutput "Using certificate: $CertPath" -Type Success
    
    Write-Section "Step 6/6: Deployment Execution"
    
    if ($DryRun) {
        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Yellow
        Write-Host "  DRY RUN MODE - No changes will be made" -ForegroundColor Yellow
        Write-Host "=======================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Would execute the following commands:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "1. Generate tenant folder:" -ForegroundColor White
        Write-Host "   $scriptRoot\gen-folder.ps1 -ClusterName $ClusterName" -ForegroundColor Gray
        Write-Host ""
        Write-Host "2. Generate Helm values:" -ForegroundColor White
        Write-Host "   $scriptRoot\gen-values.ps1 -ClusterName $ClusterName" -ForegroundColor Gray
        Write-Host ""
        Write-Host "3. Seal secrets:" -ForegroundColor White
        Write-Host "   $scriptRoot\seal-env.ps1 -CertPath $CertPath -ClusterName $ClusterName" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Output directory:" -ForegroundColor White
        Write-Host "   $clusterPath\tenants\$($serviceConfig.service.name)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Re-run without -DryRun to execute deployment." -ForegroundColor Yellow
        exit 0
    }
    
    $originalLocation = Get-Location
    
    try {
        Set-Location $serviceDir
        Write-ColorOutput "Working directory: $serviceDir" -Type Info
        Write-Host ""
        
        Write-Host "[1/3] Generating tenant folder structure..." -ForegroundColor Cyan
        try {
            & (Join-Path $scriptRoot "gen-folder.ps1") -ClusterName $ClusterName
            if ($LASTEXITCODE -ne 0) { throw "gen-folder.ps1 exited with code $LASTEXITCODE" }
            Write-ColorOutput "Tenant folder structure created" -Type Success
        }
        catch {
            throw "Failed to generate folder structure: $($_.Exception.Message)"
        }
        
        Write-Host ""
        
        Write-Host "[2/3] Generating Helm values from service configuration..." -ForegroundColor Cyan
        try {
            & (Join-Path $scriptRoot "gen-values.ps1") -ClusterName $ClusterName
            if ($LASTEXITCODE -ne 0) { throw "gen-values.ps1 exited with code $LASTEXITCODE" }
            Write-ColorOutput "Helm values.yaml created" -Type Success
        }
        catch {
            throw "Failed to generate Helm values: $($_.Exception.Message)"
        }
        
        Write-Host ""
        

        Write-Host "[3/3] Sealing environment variables with kubeseal..." -ForegroundColor Cyan
        try {
            & (Join-Path $scriptRoot "seal-env.ps1") -CertPath $CertPath -ClusterName $ClusterName
            if ($LASTEXITCODE -ne 0) { throw "seal-env.ps1 exited with code $LASTEXITCODE" }
            Write-ColorOutput "Secrets sealed successfully" -Type Success
        }
        catch {
            throw "Failed to seal secrets: $($_.Exception.Message)"
        }
        
        Write-Host "" 
        Write-Host "=======================================================" -ForegroundColor Green
        Write-Host "  [+] Deployment configuration completed successfully!" -ForegroundColor Green
        Write-Host "=======================================================" -ForegroundColor Green
        Write-Host ""
        
        $tenantDir = Join-Path $clusterPath "tenants\$($serviceConfig.service.name)"
        
        Write-Host "Deployment Details:" -ForegroundColor Cyan
        Write-Host "  Service:   $($serviceConfig.service.name)" -ForegroundColor White
        Write-Host "  Cluster:   $ClusterName" -ForegroundColor White
        Write-Host "  Namespace: $($serviceConfig.service.name)" -ForegroundColor White
        Write-Host "  Output:    $tenantDir" -ForegroundColor White
        Write-Host ""
        
        Write-Host "Generated Files:" -ForegroundColor Cyan
        $generatedFiles = @(
            "namespace.yaml",
            "kustomization.yaml",
            "values.yaml",
            "configmap.yaml",
            "sealed-secret.yaml"
        )
        foreach ($file in $generatedFiles) {
            $filePath = Join-Path $tenantDir $file
            if (Test-Path $filePath) {
                $size = (Get-Item $filePath).Length
                Write-Host "  [+] $file ($size bytes)" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }
    finally {
        Set-Location $originalLocation
    }
}
catch {
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Red
    Write-Host "  [X] Deployment Failed" -ForegroundColor Red
    Write-Host "=========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($VerboseOutput) {
        Write-Host ""
        Write-Host "Stack Trace:" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    }
    
    Write-Host ""
    Write-Host "Troubleshooting Tips:" -ForegroundColor Yellow
    Write-Host "  * Check that all required files exist in services/$ProjectName/" -ForegroundColor Gray
    Write-Host "  * Verify service.yaml has all required fields" -ForegroundColor Gray
    Write-Host "  * Ensure cluster directory $ClusterName exists" -ForegroundColor Gray
    Write-Host "  * Confirm kubectl and kubeseal are installed" -ForegroundColor Gray
    Write-Host "  * Run with -VerboseOutput for more details" -ForegroundColor Gray
    Write-Host ""
    
    exit 1
}

