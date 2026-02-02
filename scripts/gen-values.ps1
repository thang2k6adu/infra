<#
.SYNOPSIS
    Generate Helm values.yaml from service.yaml configuration

.DESCRIPTION
    Reads the service.yaml configuration and generates a complete
    Helm values.yaml file with all necessary Kubernetes configurations
    including deployment, service, ingress, autoscaling, health checks, etc.
    
    This script should be run from the service directory (services/<project>)

.PARAMETER ClusterName
    Name of the target cluster (e.g., cluster-dev)

.EXAMPLE
    cd services/myapp
    ..\..\scripts\gen-values.ps1 -ClusterName cluster-dev

.NOTES
    This script is typically called by create-service.ps1
    Requires: tenant directory to exist (run gen-folder.ps1 first)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ClusterName
)

$ErrorActionPreference = "Stop"

# Import common functions
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "lib\common.ps1")

try {
    # We're running from services/<project> directory
    $serviceDir = Get-Location
    
    # Parse service configuration
    Write-Verbose "Reading service configuration"
    $svc = Get-ServiceConfig -ServiceDir $serviceDir
    $name = $svc.service.name
    
    if (!$name) {
        throw "service.name is required in service.yaml"
    }
    
    # Get project root and resolve paths
    $rootDir = Get-ProjectRoot
    $clusterPath = Join-Path $rootDir $ClusterName
    
    if (!(Test-Path $clusterPath)) {
        throw "Cluster directory not found: $clusterPath`n`nPlease ensure the cluster exists or run gen-folder.ps1 first."
    }
    
    $tenantDir = Join-Path $clusterPath "tenants\$name"
    if (!(Test-Path $tenantDir)) {
        throw "Tenant directory not found: $tenantDir`n`nPlease run gen-folder.ps1 first to create the tenant structure."
    }
    
    $valuesFile = Join-Path $tenantDir "values.yaml"
    
    Write-Verbose "Generating values.yaml for service: $name"
    Write-Verbose "Output: $valuesFile"
    
    # Helper function to get value with fallback
    function Get-ConfigValue {
        param($Path, $Default = "")
        
        $segments = $Path -split '\.'
        $current = $svc
        
        foreach ($segment in $segments) {
            if ($current -and $current.$segment) {
                $current = $current.$segment
            }
            else {
                return $Default
            }
        }
        
        if ($null -ne $current) {
            return $current
        } else {
            return $Default
        }
    }
    
    # Generate ConfigMap/Secret names (strip -api suffix if present)
    $baseName = $name -replace '-api$', ''
    $configMapName = "$baseName-config"
    $secretName = "$baseName-secret"
    
    # Get configuration values with defaults
    $imageRepo = Get-ConfigValue "image.repository" "nginx"
    $imageTag = Get-ConfigValue "image.tag" "latest"
    $imagePullPolicy = Get-ConfigValue "image.pullPolicy" "IfNotPresent"
    $replicas = Get-ConfigValue "replicas" 1
    $port = Get-ConfigValue "network.port" 8080
    $domain = Get-ConfigValue "network.domain" "example.com"
    
    # Resources
    $cpuRequest = Get-ConfigValue "resources.cpu.request" "100m"
    $cpuLimit = Get-ConfigValue "resources.cpu.limit" "500m"
    $memRequest = Get-ConfigValue "resources.memory.request" "128Mi"
    $memLimit = Get-ConfigValue "resources.memory.limit" "512Mi"
    
    # Health checks
    $livenessPath = Get-ConfigValue "healthcheck.liveness.path" "/health"
    $readinessPath = Get-ConfigValue "healthcheck.readiness.path" "/ready"
    $startupPath = Get-ConfigValue "healthcheck.startup.path" "/health"
    
    # Autoscaling
    $autoscalingEnabled = Get-ConfigValue "autoscaling.enabled" $true
    $minReplicas = Get-ConfigValue "autoscaling.min" 2
    $maxReplicas = Get-ConfigValue "autoscaling.max" 10
    $cpuTarget = Get-ConfigValue "autoscaling.cpuTarget" 80
    $memTarget = Get-ConfigValue "autoscaling.memoryTarget" 80
    
    # Persistence
    $persistenceEnabled = Get-ConfigValue "persistence.enabled" $false
    $persistenceSize = Get-ConfigValue "persistence.size" "10Gi"
    $persistencePath = Get-ConfigValue "persistence.mountPath" "/data"
    
    # Convert boolean to lowercase string for YAML
    $autoscalingEnabledStr = $autoscalingEnabled.ToString().ToLower()
    $persistenceEnabledStr = $persistenceEnabled.ToString().ToLower()
    
    Write-Verbose "Image: $imageRepo`:$imageTag"
    Write-Verbose "Port: $port"
    Write-Verbose "Replicas: $replicas"
    Write-Verbose "Autoscaling: $autoscalingEnabledStr (min:$minReplicas, max:$maxReplicas)"
    
    # Generate values.yaml content
    $valuesContent = @"
# Helm values for $name
# Generated from service.yaml configuration

# Container image configuration
image:
  repository: $imageRepo
  pullPolicy: $imagePullPolicy
  tag: "$imageTag"

imagePullSecrets: []

# Service naming
nameOverride: "$name"
fullnameOverride: ""

# Deployment configuration
replicaCount: $replicas

strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0

# Service account
serviceAccount:
  create: true
  automount: true
  annotations: {}
  name: ""

# Pod annotations and labels
podAnnotations: {}
podLabels: {}

# Security contexts
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1001
  fsGroup: 1001
  seccompProfile:
    type: RuntimeDefault

securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL

# Kubernetes Service
service:
  type: ClusterIP
  port: $port
  targetPort: $port
  annotations: {}

# Ingress configuration
ingress:
  enabled: false
  className: "nginx"
  annotations: {}
  hosts:
    - host: $domain
      paths:
        - path: /
          pathType: Prefix

# Resource limits and requests
resources:
  requests:
    cpu: "$cpuRequest"
    memory: "$memRequest"
  limits:
    cpu: "$cpuLimit"
    memory: "$memLimit"

# Health check probes
livenessProbe:
  httpGet:
    path: $livenessPath
    port: $port
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  successThreshold: 1
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: $readinessPath
    port: $port
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  successThreshold: 1
  failureThreshold: 3

startupProbe:
  httpGet:
    path: $startupPath
    port: $port
  initialDelaySeconds: 0
  periodSeconds: 10
  timeoutSeconds: 3
  successThreshold: 1
  failureThreshold: 30

# Horizontal Pod Autoscaler
autoscaling:
  enabled: $autoscalingEnabledStr
  minReplicas: $minReplicas
  maxReplicas: $maxReplicas
  targetCPUUtilizationPercentage: $cpuTarget
  targetMemoryUtilizationPercentage: $memTarget

# Environment variables from ConfigMap and Secret
envFrom:
  - configMapRef:
      name: $configMapName
  - secretRef:
      name: $secretName

# ConfigMap configuration (managed separately)
configMap:
  enabled: false
  data: {}

# Secrets configuration (managed separately via SealedSecret)
secrets:
  enabled: false
  data: {}

# Volumes for writable directories
volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}

volumeMounts:
  - name: tmp
    mountPath: /tmp
  - name: cache
    mountPath: /app/cache

# Persistent storage
persistence:
  enabled: $persistenceEnabledStr
  storageClass: ""
  accessMode: ReadWriteOnce
  size: $persistenceSize
  mountPath: $persistencePath
  annotations: {}

# Pod Disruption Budget
podDisruptionBudget:
  enabled: true
  minAvailable: 1

# Node selection
nodeSelector: {}

# Tolerations
tolerations: []

# Pod anti-affinity for high availability
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - $name
          topologyKey: kubernetes.io/hostname

# Prometheus ServiceMonitor
serviceMonitor:
  enabled: false
  interval: 30s
  scrapeTimeout: 10s
  path: /metrics
  labels: {}

# Sidecar containers
sidecars: []

# Init containers
initContainers: []

# Lifecycle hooks
lifecycle: {}

# Network Policy
networkPolicy:
  enabled: false
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 5432  # PostgreSQL
        - protocol: TCP
          port: 6379  # Redis

# RBAC configuration
rbac:
  create: false
  rules: []

# Gateway API HTTPRoute
httpRoute:
  enabled: false
"@
    
    # Write values.yaml file
    $valuesContent | Out-File $valuesFile -Encoding utf8
    
    Write-Host "[+] values.yaml generated successfully" -ForegroundColor Green
    Write-Verbose "File: $valuesFile"
    Write-Verbose "Size: $((Get-Item $valuesFile).Length) bytes"
        exit 0}
catch {
    Write-Error "Failed to generate values.yaml: $($_.Exception.Message)"
    exit 1
}