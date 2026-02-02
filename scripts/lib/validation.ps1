function Test-ServiceDirectory {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectName,
        
        [Parameter(Mandatory=$true)]
        [string]$RootDir
    )
    
    $serviceDir = Join-Path $RootDir "services\$ProjectName"
    
    if (!(Test-Path $serviceDir)) {
        $available = Get-ChildItem -Path (Join-Path $RootDir "services") -Directory -ErrorAction SilentlyContinue
        
        $errorMsg = "Service directory not found: $serviceDir"
        if ($available) {
            $errorMsg += "`n`nAvailable services:`n"
            $errorMsg += ($available | ForEach-Object { "  • $($_.Name)" }) -join "`n"
        }
        throw $errorMsg
    }
    
    $requiredFiles = @{
        "service.yaml" = "Service configuration file"
        ".env" = "Environment variables file"
        "secrets.whitelist" = "Secret variables whitelist file"
    }
    
    $missing = @()
    
    foreach ($file in $requiredFiles.Keys) {
        $filePath = Join-Path $serviceDir $file
        if (!(Test-Path $filePath)) {
            $missing += "$file - $($requiredFiles[$file])"
        }
    }
    
    if ($missing.Count -gt 0) {
        $errorMsg = "Missing required files in services/$ProjectName`:`n`n"
        $errorMsg += ($missing | ForEach-Object { "  • $_" }) -join "`n"
        $errorMsg += "`n`nPlease ensure all required files exist before running deployment."
        throw $errorMsg
    }
    
    return $serviceDir
}

function Test-ClusterDirectory {

    param(
        [Parameter(Mandatory=$true)]
        [string]$ClusterName,
        
        [Parameter(Mandatory=$true)]
        [string]$RootDir
    )
    
    $clusterPath = Join-Path $RootDir $ClusterName
    
    if (!(Test-Path $clusterPath)) {
        $available = Get-ChildItem -Path $RootDir -Filter "cluster-*" -Directory -ErrorAction SilentlyContinue
        
        $errorMsg = "Cluster directory not found: $ClusterPath"
        if ($available) {
            $errorMsg += "`n`nAvailable clusters:`n"
            $errorMsg += ($available | ForEach-Object { "  • $($_.Name)" }) -join "`n"
        }
        else {
            $errorMsg += "`n`nNo cluster directories found. Expected format: cluster-<name>"
        }
        throw $errorMsg
    }
    
    $expectedDirs = @("tenants", "core", "components")
    $hasStructure = $false
    
    foreach ($dir in $expectedDirs) {
        if (Test-Path (Join-Path $clusterPath $dir)) {
            $hasStructure = $true
            break
        }
    }
    
    if (!$hasStructure) {
        Write-Warning "Cluster directory exists but doesn't have expected structure (tenants/core/components)"
        Write-Warning "This might be OK if it's a new cluster, but verify the path is correct."
    }
    
    return $clusterPath
}

function Get-CertificateFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RootDir,
        
        [Parameter(Mandatory=$false)]
        [bool]$Interactive = $true
    )
    
    $pemFiles = Get-ChildItem -Path $RootDir -Filter "*.pem" -File
    
    if ($pemFiles.Count -eq 0) {
        throw "No .pem certificate file found in root directory ($RootDir)`n`nPlease ensure your kubeseal certificate is in the project root."
    }
    
    if ($pemFiles.Count -eq 1) {
        return $pemFiles[0].FullName
    }
    
    if (!$Interactive) {
        Write-Warning "Multiple certificate files found. Using first one: $($pemFiles[0].Name)"
        Write-Warning "Use -CertPath parameter to specify a different certificate."
        return $pemFiles[0].FullName
    }
    
    Write-Host "`nMultiple certificate files found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $pemFiles.Count; $i++) {
        $fileInfo = $pemFiles[$i]
        $size = "{0:N2} KB" -f ($fileInfo.Length / 1KB)
        $modified = $fileInfo.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        Write-Host "  [$i] $($fileInfo.Name) - $size - Modified: $modified"
    }
    Write-Host ""
    
    do {
        $choice = Read-Host "Select certificate [0-$($pemFiles.Count - 1)]"
        $valid = $choice -match '^\d+$' -and [int]$choice -ge 0 -and [int]$choice -lt $pemFiles.Count
        
        if (!$valid) {
            Write-Host "Invalid selection. Please enter a number between 0 and $($pemFiles.Count - 1)." -ForegroundColor Red
        }
    } while (!$valid)
    
    return $pemFiles[[int]$choice].FullName
}

function Test-ServiceSchema {

    param(
        [Parameter(Mandatory=$true)]
        $Config
    )
    
    $errors = @()
    
    # Required fields with paths
    $requiredFields = @{
        "service.name" = { $Config.service.name }
        "service.releaseName" = { $Config.service.releaseName }
        "service.chartRepo" = { $Config.service.chartRepo }
        "image.repository" = { $Config.image.repository }
        "image.tag" = { $Config.image.tag }
        "image.pullPolicy" = { $Config.image.pullPolicy }
        "network.port" = { $Config.network.port }
        "resources.cpu.request" = { $Config.resources.cpu.request }
        "resources.cpu.limit" = { $Config.resources.cpu.limit }
        "resources.memory.request" = { $Config.resources.memory.request }
        "resources.memory.limit" = { $Config.resources.memory.limit }
        "healthcheck.liveness.path" = { $Config.healthcheck.liveness.path }
        "healthcheck.readiness.path" = { $Config.healthcheck.readiness.path }
        "healthcheck.startup.path" = { $Config.healthcheck.startup.path }
    }
    
    foreach ($field in $requiredFields.Keys) {
        $value = & $requiredFields[$field]
        if (!$value -or [string]::IsNullOrWhiteSpace($value)) {
            $errors += "Missing or empty field: $field"
        }
    }
    
    if ($Config.network.port) {
        $port = $Config.network.port
        if ($port -lt 1 -or $port -gt 65535) {
            $errors += "network.port must be between 1 and 65535 (got: $port)"
        }
    }
    
    if ($Config.replicas) {
        if ($Config.replicas -lt 1) {
            $errors += "replicas must be at least 1 (got: $($Config.replicas))"
        }
    }
    
    if ($Config.autoscaling) {
        if ($Config.autoscaling.min -and $Config.autoscaling.max) {
            if ($Config.autoscaling.min -gt $Config.autoscaling.max) {
                $errors += "autoscaling.min ($($Config.autoscaling.min)) cannot be greater than autoscaling.max ($($Config.autoscaling.max))"
            }
        }
    }
    
    if ($errors.Count -gt 0) {
        $errorMsg = "Invalid service.yaml configuration:`n`n"
        $errorMsg += ($errors | ForEach-Object { "  • $_" }) -join "`n"
        throw $errorMsg
    }
}

function Test-EnvironmentFiles {

    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceDir
    )
    
    $envFile = Join-Path $ServiceDir ".env"
    $whitelistFile = Join-Path $ServiceDir "secrets.whitelist"
    
    $envLines = Get-Content $envFile -ErrorAction Stop | 
        Where-Object { $_ -and !$_.StartsWith("#") -and $_.Trim() -ne "" }
    
    $whitelist = Get-Content $whitelistFile -ErrorAction Stop | 
        Where-Object { $_ -and !$_.StartsWith("#") -and $_.Trim() -ne "" }
    
    $warnings = @()
    
    $envVars = @()
    foreach ($line in $envLines) {
        if ($line -match '^([^=]+)=') {
            $envVars += $matches[1].Trim()
        }
    }
    
    foreach ($var in $whitelist) {
        if ($envVars -notcontains $var) {
            $warnings += "Variable '$var' is in secrets.whitelist but not in .env"
        }
    }
    
    $duplicates = $envVars | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($duplicates) {
        foreach ($dup in $duplicates) {
            $warnings += "Duplicate variable in .env: $($dup.Name) (appears $($dup.Count) times)"
        }
    }
    
    return @{
        EnvVarCount = $envVars.Count
        SecretVarCount = ($whitelist | Where-Object { $envVars -contains $_ }).Count
        ConfigVarCount = ($envVars | Where-Object { $whitelist -notcontains $_ }).Count
        Warnings = $warnings
    }
}