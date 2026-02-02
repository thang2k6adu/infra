#!/usr/bin/env bash
set -euo pipefail

# Parse parameters
CertPath=""
ClusterName=""
TenantsPath="tenants"  # Default value
RootDir=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --CertPath) CertPath="$2"; shift 2 ;;
    --ClusterName) ClusterName="$2"; shift 2 ;;
    --TenantsPath) TenantsPath="$2"; shift 2 ;;
    --RootDir) RootDir="$2"; shift 2 ;;
    --ProjectName) ProjectName="$2"; shift 2 ;;
    *) 
      # Handle positional arguments for backward compatibility
      if [[ -z "$CertPath" ]]; then
        CertPath="$1"
        shift
      elif [[ -z "$ClusterName" ]]; then
        ClusterName="$1"
        shift
      elif [[ "$TenantsPath" == "tenants" ]]; then
        TenantsPath="$1"
        shift
      elif [[ -z "$RootDir" ]]; then
        RootDir="$1"
        shift
      else
        echo "Unknown parameter: $1"
        exit 1
      fi
      ;;
  esac
done

# Backward compatibility: handle positional arguments if still empty
if [[ -z "$CertPath" && $# -gt 0 ]]; then
  CertPath="$1"
  shift
fi

if [[ -z "$ClusterName" && $# -gt 0 ]]; then
  ClusterName="$1"
  shift
fi

if [[ "$TenantsPath" == "tenants" && $# -gt 0 ]]; then
  TenantsPath="$1"
  shift
fi

if [[ -z "$RootDir" && $# -gt 0 ]]; then
  RootDir="$1"
fi

if [[ -z "${CertPath:-}" || -z "${ClusterName:-}" ]]; then
  echo "Usage: $0 <CertPath> <ClusterName> [TenantsPath] [RootDir]"
  echo "       $0 --CertPath <CertPath> --ClusterName <ClusterName> [--TenantsPath <TenantsPath>] [--RootDir <RootDir>]"
  exit 1
fi

echo "Using TenantsPath: $TenantsPath"
if [[ -n "$RootDir" ]]; then
  echo "Using RootDir: $RootDir"
fi

scriptRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$scriptRoot/lib/common.sh"

serviceDir="$(pwd)"

envFile="$serviceDir/.env"
whitelistFile="$serviceDir/secrets.whitelist"

if [[ ! -f "$envFile" ]]; then
  echo ".env file not found in $serviceDir

Please create a .env file with your environment variables."
  exit 1
fi

if [[ ! -f "$whitelistFile" ]]; then
  echo "secrets.whitelist file not found in $serviceDir

Please create a secrets.whitelist file listing variables that should be sealed as secrets."
  exit 1
fi

if [[ ! -f "$CertPath" ]]; then
  echo "Certificate file not found: $CertPath

Please provide a valid kubeseal certificate (.pem file)."
  exit 1
fi

CertPath="$(realpath "$CertPath")"

serviceName="$(yq '.service.name' service.yaml)"
namespace="$serviceName"

if [[ -z "$serviceName" || "$serviceName" == "null" ]]; then
  echo "service.name is required in service.yaml"
  exit 1
fi

baseName="${serviceName%-api}"
configMapName="${baseName}-config"
secretName="${baseName}-secret"

echo "Processing environment variables:"
echo "  Service:    $serviceName"
echo "  Namespace:  $namespace"
echo "  ConfigMap:  $configMapName"
echo "  Secret:     $secretName"
echo ""

# Sử dụng RootDir nếu được cung cấp, nếu không thì dùng GetProjectRoot
if [[ -n "$RootDir" ]]; then
  if [[ ! -d "$RootDir" ]]; then
    echo "Root directory not found: $RootDir"
    exit 1
  fi
  rootDir="$RootDir"
else
  rootDir="$(GetProjectRoot)"
fi

clusterPath="$rootDir/$ClusterName"

# Use TenantsPath instead of hardcoded "tenants"
tenantDir="$clusterPath/$TenantsPath/$serviceName"

if [[ ! -d "$tenantDir" ]]; then
  echo "Tenant directory not found: $tenantDir

Please run gen-folder.sh first to create the tenant structure."
  exit 1
fi

originalLocation="$(pwd)"

cleanup() {
  rm -f config.env secret.env secret.yaml 2>/dev/null || true
}
trap cleanup ERR

cd "$tenantDir"

envLines=$(grep -v '^\s*#' "$envFile" | grep -v '^\s*$')
whitelist=$(grep -v '^\s*#' "$whitelistFile" | grep -v '^\s*$' | sed 's/^[ \t]*//;s/[ \t]*$//')

secretData=()
configData=()
varCount=0

while IFS= read -r line; do
  if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
    key="$(echo "${BASH_REMATCH[1]}" | xargs)"
    value="${BASH_REMATCH[2]}"
    ((++varCount))

    if [[ " $whitelist " == *"$key"* ]]; then
  secretData+=("$key=$value")
else
  configData+=("$key=$value")
fi
  else
    echo "Skipping invalid line in .env: $line"
  fi
done <<< "$envLines"

echo "  Variables:  $varCount total"
echo "    Config:   ${#configData[@]}"
echo "    Secrets:  ${#secretData[@]}"
echo ""

printf "%s\n" "${configData[@]}" > config.env
printf "%s\n" "${secretData[@]}" > secret.env

echo "Creating ConfigMap..."
kubectl create configmap "$configMapName" \
  --from-env-file=config.env \
  -n "$namespace" \
  --dry-run=client \
  -o yaml > configmap.yaml

echo "  [+] configmap.yaml created"

echo "Creating Secret..."
kubectl create secret generic "$secretName" \
  --from-env-file=secret.env \
  -n "$namespace" \
  --dry-run=client \
  -o yaml > secret.yaml

echo "  [+] secret.yaml created"

echo "Sealing Secret with kubeseal..."
kubeseal --cert "$CertPath" --namespace "$namespace" --format yaml < secret.yaml > sealed-secret.yaml

echo "  [+] sealed-secret.yaml created"

cleanup

kustomizationFile="kustomization.yaml"

if [[ ! -f "$kustomizationFile" ]]; then
  echo "kustomization.yaml not found in $tenantDir

Please run gen-folder.sh first."
  exit 1
fi

mapfile -t lines < "$kustomizationFile"

hasConfigMap=false
hasSealedSecret=false
resourcesLine=-1

for i in "${!lines[@]}"; do
  [[ "${lines[$i]}" =~ ^[[:space:]]*-\s*configmap\.yaml ]] && hasConfigMap=true
  [[ "${lines[$i]}" =~ ^[[:space:]]*-\s*sealed-secret\.yaml ]] && hasSealedSecret=true
  [[ "${lines[$i]}" =~ ^resources: ]] && resourcesLine=$i
done

updatedLines=()

if [[ $resourcesLine -eq -1 ]]; then
  updatedLines=("${lines[@]}")
  updatedLines+=("")
  updatedLines+=("resources:")
  updatedLines+=("  - configmap.yaml")
  updatedLines+=("  - sealed-secret.yaml")
else
  for ((i=0;i<=resourcesLine;i++)); do
    updatedLines+=("${lines[$i]}")
  done

  [[ "$hasConfigMap" == false ]] && updatedLines+=("  - configmap.yaml")
  [[ "$hasSealedSecret" == false ]] && updatedLines+=("  - sealed-secret.yaml")

  for ((i=resourcesLine+1;i<${#lines[@]};i++)); do
    line="${lines[$i]}"
    if [[ "$line" =~ configmap\.yaml || "$line" =~ sealed-secret\.yaml ]]; then
      continue
    fi
    updatedLines+=("$line")
  done
fi

printf "%s\n" "${updatedLines[@]}" > "$kustomizationFile"

echo "  [+] kustomization.yaml updated"
echo ""
echo "[+] Environment variables sealed successfully!"
echo ""
echo "Generated files in $tenantDir:"
echo "  * configmap.yaml     (${#configData[@]} variables)"
echo "  * sealed-secret.yaml (${#secretData[@]} variables)"
echo ""

if [[ ${#secretData[@]} -gt 0 ]]; then
  echo "Security Notes:"
  echo "  * Secret values are encrypted with kubeseal"
  echo "  * Only the target cluster can decrypt them"
  echo "  * Safe to commit sealed-secret.yaml to Git"
  echo "  * Never commit the original .env file"
  echo ""
fi

cd "$originalLocation"
exit 0