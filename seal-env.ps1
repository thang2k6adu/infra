param(
  [string]$Namespace,
  [string]$SecretName,
  [string]$CertPath
)

$TenantDir = Get-Location
$EnvFile = "$TenantDir\.env"
$WhitelistFile = "$TenantDir\secrets.whitelist"

if (!(Test-Path $EnvFile)) { Write-Error ".env not found"; exit 1 }
if (!(Test-Path $WhitelistFile)) { Write-Error "secrets.whitelist not found"; exit 1 }

$CertPath = Resolve-Path $CertPath

$envLines = Get-Content $EnvFile | Where-Object { $_ -and -not $_.StartsWith("#") }
$whitelist = Get-Content $WhitelistFile

$secretData = @()
$configData = @()

foreach ($line in $envLines) {
  $key, $value = $line -split "=",2
  if ($whitelist -contains $key) {
    $secretData += "$key=$value"
  } else {
    $configData += "$key=$value"
  }
}

$configData | Out-File config.env -Encoding utf8
$secretData | Out-File secret.env -Encoding utf8

kubectl create configmap app-config `
  --from-env-file=config.env `
  -n $Namespace `
  --dry-run=client -o yaml > configmap.yaml

kubectl create secret generic $SecretName `
  --from-env-file=secret.env `
  -n $Namespace `
  --dry-run=client -o yaml > secret.yaml

Get-Content secret.yaml | kubeseal `
  --cert $CertPath `
  --namespace $Namespace `
  --format yaml > sealed-secret.yaml

Remove-Item config.env, secret.env, secret.yaml -Force

Write-Host "Done. Generated configmap.yaml and sealed-secret.yaml"
