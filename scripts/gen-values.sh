#!/usr/bin/env bash

set -e

# Parse parameters
ClusterName=""
TenantsPath="tenants"  # Default value
RootDir=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --ClusterName) ClusterName="$2"; shift 2 ;;
    --TenantsPath) TenantsPath="$2"; shift 2 ;;
    --RootDir) RootDir="$2"; shift 2 ;;
    --ProjectName) ProjectName="$2"; shift 2 ;;
    *) 
      # Handle positional arguments for backward compatibility
      if [[ -z "$ClusterName" ]]; then
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

if [[ -z "$ClusterName" ]]; then
  echo "ClusterName is required"
  exit 1
fi

echo "Using TenantsPath: $TenantsPath"
if [[ -n "$RootDir" ]]; then
  echo "Using RootDir: $RootDir"
fi

scriptRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$scriptRoot/lib/common.sh"

trap 'echo "Failed to generate values.yaml: $ERR"; exit 1' ERR

try() { "$@"; }

serviceDir="$(pwd)"
svc="$(GetServiceConfig "$serviceDir")"

name="$(yq '.service.name' "$serviceDir/service.yaml")"
if [[ -z "$name" || "$name" == "null" ]]; then
  echo "service.name is required in service.yaml"
  exit 1
fi

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
if [[ ! -d "$clusterPath" ]]; then
  echo "Cluster directory not found: $clusterPath"
  exit 1
fi

# Use TenantsPath instead of hardcoded "tenants"
tenantDir="$clusterPath/$TenantsPath/$name"
if [[ ! -d "$tenantDir" ]]; then
  echo "Tenant directory not found: $tenantDir"
  echo "Please run gen-folder.sh first to create the tenant directory"
  exit 1
fi

valuesFile="$tenantDir/values.yaml"

templatePath="$scriptRoot/templates/values.tpl.yaml"
if [[ ! -f "$templatePath" ]]; then
  echo "Template not found: $templatePath"
  exit 1
fi

serviceYaml="$serviceDir/service.yaml"
if [[ ! -f "$serviceYaml" ]]; then
  echo "service.yaml not found in $serviceDir"
  exit 1
fi

serviceYaml="$(realpath "$serviceYaml")"

# Require gomplate (giữ nguyên kiểm tra 2 lần như PowerShell)
if ! command -v gomplate >/dev/null 2>&1; then
  echo "gomplate is not installed. Install from https://github.com/hairyhenderson/gomplate"
  exit 1
fi

if ! command -v gomplate >/dev/null 2>&1; then
  echo "gomplate is not installed. Install from https://github.com/hairyhenderson/gomplate"
  exit 1
fi

echo "SERVICE YAML = $serviceYaml"
cat "$serviceYaml"

echo "SERVICE YAML = $serviceYaml"
cat "$serviceYaml"

serviceYaml="$(realpath "$serviceYaml")"

json="$(yq -o=json "$serviceYaml")"

echo "$json" | gomplate \
  -c ".=stdin:?type=application/json" \
  -f "$templatePath" \
  -o "$valuesFile"

echo "[+] values.yaml generated successfully"
echo "File: $valuesFile"

echo "[+] values.yaml generated successfully"
echo "[+] values.yaml generated successfully"
echo "File: $valuesFile"

exit 0