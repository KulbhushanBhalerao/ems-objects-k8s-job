# Helm Chart for EMS Objects Creation

This is a complete Helm chart for deploying the EMS objects creation job with intelligent hash-based execution.

## Chart Structure

```
helm-chart/
├── Chart.yaml                      # Chart metadata
├── values.yaml                     # Default configuration values
├── .helmignore                     # Files to ignore when packaging
├── ems-scripts/                    # EMS definition files
│   ├── common/                     # Common EMS objects
│   └── application/                # Application-specific objects
└── templates/                      # Kubernetes manifest templates
    ├── _helpers.tpl                # Template helpers
    ├── configmap-ems-objects.yaml  # ConfigMap with EMS scripts
    └── job-ems-objects.yaml        # Job with smart hash checking
```

## Features

### Smart Hash-Based Execution

The Helm version of the job includes intelligent change detection:

- **SHA256 Hash Calculation**: Automatically calculates hash of ConfigMap content
- **Conditional Execution**: Job only runs when EMS scripts (.ems/.bridge files) change
- **Prevents Unnecessary Runs**: Skips job execution during upgrades if files unchanged
- **Always Runs on Install**: Ensures initial setup always executes

### How It Works

1. On `helm install`: Job always runs to create initial EMS objects
2. On `helm upgrade`:
   - Calculates new hash from ConfigMap
   - Compares with hash from existing job annotation
   - If hashes differ (files changed) → Job recreates and runs
   - If hashes match (no changes) → Job skipped

## Configuration

Edit `values.yaml` to configure:

```yaml
emsAdmin:
  image: "your-registry/ems-admin:1.0.0"
  serverName: "your-ems-server"
  port: "7222"
  user: "admin"
  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"
```

## Usage

### Prerequisites

```bash
# Create the EMS admin password secret
kubectl create secret generic ems-admin-secret --from-literal=password=emspassword
```

### Initial Installation

```bash
# Install with default values
helm install ems-objects ./helm-chart

# Or with custom configuration
helm install ems-objects ./helm-chart \
  --set emsAdmin.serverName=your-ems-server \
  --set emsAdmin.image=your-registry/ems-admin:1.0.0

# Verify installation
kubectl get jobs
kubectl logs job/job-ems-objects-creation
```

### Upgrade After Changing EMS Scripts

```bash
# 1. Edit your .ems or .bridge files
vim ems-scripts/common/destinations.ems

# 2. Upgrade - job will run because hash changed
helm upgrade ems-objects ./helm-chart
```

### Upgrade Without Script Changes

```bash
# Job will NOT rerun (hash unchanged)
helm upgrade ems-objects ./helm-chart --set emsAdmin.resources.requests.memory=512Mi
```

## Package and Distribution

```bash
# Package the chart
helm package ./helm-chart

# This creates: ems-objects-creation-1.0.0.tgz

# Install from package
helm install ems-objects ems-objects-creation-1.0.0.tgz
```

## Integration into Your Helm Chart

To integrate this into an existing Helm chart:

1. Copy the chart as a subchart:
   ```bash
   mkdir -p your-chart/charts
   cp -r helm-chart your-chart/charts/ems-objects-creation
   ```

2. Or merge templates directly:
   ```bash
   cp helm-chart/templates/* your-chart/templates/
   cp -r helm-chart/ems-scripts your-chart/
   # Merge values.yaml manually
   ```

## Troubleshooting

### Job Not Running on Upgrade

If job doesn't run when you expect it to:

```bash
# Check current hash
kubectl get job job-ems-objects-creation -o jsonpath='{.metadata.annotations.configmaphash}'

# Force job to run by deleting it first
kubectl delete job job-ems-objects-creation
helm upgrade ems-objects ./helm-chart
```

### View Job Execution Logic

The job template uses Helm's `lookup` function to check existing job:

```yaml
# Calculate new hash
{{ $newhash := include (print $.Template.BasePath "/configmap-ems-objects.yaml") . | sha256sum }}

# Compare with existing hash
{{ $currenthash := (lookup "batch/v1" "Job" .Release.Namespace "job-ems-objects-creation").metadata.annotations.configmaphash }}

# Only run if different
{{ if ne $currenthash $newhash }}
  # Create job
{{ end }}
```

## Benefits

✅ **Efficiency**: Prevents unnecessary EMS operations when scripts unchanged  
✅ **Safety**: Always runs on initial install  
✅ **Transparency**: Hash visible in job annotations  
✅ **Automation**: No manual intervention needed  
✅ **Idempotent**: Safe to run `helm upgrade` multiple times

## See Also

- [Main README](../README.md) - Project overview
- [Deployment Guide](../kubernetes/DEPLOYMENT_GUIDE.md) - Detailed deployment instructions
- [EMS Scripts](../ems-scripts/) - Sample EMS object definitions
