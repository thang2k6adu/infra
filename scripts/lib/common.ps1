function Get-ProjectRoot {
    $current = Get-Location
    $maxDepth = 10
    $depth = 0
    
    while ($current -and $depth -lt $maxDepth) {
        if (Test-Path (Join-Path $current ".gitignore")) {
            return $current
        }
        
        $parent = Split-Path $current -Parent
        if (!$parent -or $parent -eq $current) {
            break
        }
        
        $current = $parent
        $depth++
    }
    
    throw "Cannot find project root (looking for .gitignore). Make sure you're inside the project directory."
}

function Get-ServiceConfig {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceDir
    )
    
    $serviceFile = Join-Path $ServiceDir "service.yaml"
    
    if (!(Test-Path $serviceFile)) {
        throw "service.yaml not found in $ServiceDir"
    }
    
    try {
        $config = Get-Content $serviceFile -Raw | ConvertFrom-Yaml
        
        # Validate basic structure
        if (!$config.service) {
            throw "Invalid service.yaml: missing 'service' section"
        }
        
        return $config
    }
    catch {
        throw "Failed to parse service.yaml: $($_.Exception.Message)"
    }
}

function Test-Dependencies {
    $missing = @()
    $warnings = @()
    
    # Check PowerShell module
    if (!(Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
        $missing += "powershell-yaml module`n  Install: Install-Module -Name powershell-yaml -Scope CurrentUser"
    }
    
    # Check kubectl
    if (!(Get-Command kubectl -ErrorAction SilentlyContinue)) {
        $missing += "kubectl`n  Install: https://kubernetes.io/docs/tasks/tools/"
    }
    
    # Check kubeseal
    if (!(Get-Command kubeseal -ErrorAction SilentlyContinue)) {
        $missing += "kubeseal`n  Install: https://github.com/bitnami-labs/sealed-secrets#kubeseal"
    }
    
    if ($missing.Count -gt 0) {
        $errorMsg = "Missing required dependencies:`n`n"
        $errorMsg += ($missing | ForEach-Object { "  • $_" }) -join "`n"
        throw $errorMsg
    }
    
    return $warnings
}

function Write-ColorOutput {
    <#
    .SYNOPSIS
        Write formatted output with color and icons
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Step')]
        [string]$Type = 'Info'
    )
    
    switch ($Type) {
        'Success' {
            Write-Host "[+] $Message" -ForegroundColor Green
        }
        'Error' {
            Write-Host "[X] $Message" -ForegroundColor Red
        }
        'Warning' {
            Write-Host "[!] $Message" -ForegroundColor Yellow
        }
        'Step' {
            Write-Host "`n[>] $Message" -ForegroundColor Cyan
        }
        'Info' {
            Write-Host "  $Message" -ForegroundColor Gray
        }
    }
}

function Invoke-WithErrorHandling {
    param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,
        
        [Parameter(Mandatory=$true)]
        [string]$ErrorMessage
    )
    
    try {
        & $ScriptBlock
        
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "$ErrorMessage (exit code: $LASTEXITCODE)"
        }
    }
    catch {
        throw "$ErrorMessage - $($_.Exception.Message)"
    }
}