param(
    [string]$ClusterName
)

# Stop on any error
$ErrorActionPreference = "Stop"

try {

if (-not $ClusterName -or $ClusterName.Trim() -eq "") {
    $ClusterName = Read-Host "Enter cluster name (ex: cluster-dev)"
}

# baseDir = services/<project>
$baseDir = Get-Location

$serviceFile = Join-Path $baseDir "service.yaml"
if (!(Test-Path $serviceFile)) {
    Write-Error "service.yaml not found in $baseDir"
    exit 1
}

$svc = Get-Content $serviceFile -Raw | ConvertFrom-Yaml

if (-not $svc.service.name) { Write-Error "Missing service.name"; exit 1 }
if (-not $svc.service.releaseName) { Write-Error "Missing service.releaseName"; exit 1 }
if (-not $svc.service.chartRepo) { Write-Error "Missing service.chartRepo"; exit 1 }
if (-not $svc.service.chartName) { Write-Error "Missing service.chartName"; exit 1 }

$name = $svc.service.name
$releaseName = $svc.service.releaseName
$chartRepo = $svc.service.chartRepo
$chartName = $svc.service.chartName

# ===== rootDir = go up from services/<project> to repo root =====
$rootDir = Resolve-Path (Join-Path $baseDir "..\..")
$clusterPath = Join-Path $rootDir $ClusterName

if (!(Test-Path $clusterPath)) {
    Write-Error "Cluster not found: $ClusterName"
    exit 1
}

$serviceDir = Join-Path $clusterPath "tenants\$name"
New-Item -ItemType Directory -Force -Path $serviceDir | Out-Null

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateDir = Join-Path $scriptDir "templates"

if (!(Test-Path $templateDir)) {
    Write-Error "templates folder not found: $templateDir"
    exit 1
}

$namespaceTplPath = Join-Path $templateDir "namespace.tpl.yaml"
$kustomizeTplPath = Join-Path $templateDir "kustomization.tpl.yaml"

if (!(Test-Path $namespaceTplPath)) {
    Write-Error "Missing template file: namespace.tpl.yaml"
    exit 1
}

if (!(Test-Path $kustomizeTplPath)) {
    Write-Error "Missing template file: kustomization.tpl.yaml"
    exit 1
}
$namespaceTpl = Get-Content $namespaceTplPath -Raw
$kustomizeTpl = Get-Content $kustomizeTplPath -Raw

$vars = @{
  SERVICE_NAME = $name
  CHART_NAME   = $chartName
  CHART_REPO   = $chartRepo
  RELEASE_NAME = $releaseName
}

foreach ($key in $vars.Keys) {
  $namespaceTpl  = $namespaceTpl  -replace "{{${key}}}", $vars[$key]
  $kustomizeTpl = $kustomizeTpl -replace "{{${key}}}", $vars[$key]
}

$namespaceTpl  | Set-Content (Join-Path $serviceDir "namespace.yaml") -Encoding utf8
$kustomizeTpl | Set-Content (Join-Path $serviceDir "kustomization.yaml") -Encoding utf8

Write-Host "Tenant created at: $serviceDir"

# Explicitly exit with success code
exit 0
}
catch {
    Write-Error "Failed to generate folder structure: $($_.Exception.Message)"
    exit 1
}
