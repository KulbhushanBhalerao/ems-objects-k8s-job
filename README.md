# TIBCO EMS Objects Creation Kubernetes Job

This project provides a Kubernetes-based solution for creating TIBCO EMS objects (queues, topics, bridges) defined in `.ems` or `.bridge` files via ConfigMaps.

## Project Structure

```
.
├── README.md                           # This file
├── docker/
│   ├── Dockerfile                      # Container image for EMS admin operations
│   └── scripts/
│       └── ems-admin.sh               # Script to process and execute EMS scripts
├── ems-scripts/
│   ├── common/
│   │   ├── destinations.ems           # Common queues/topics for all environments
│   │   └── bridges.bridge             # Common bridges for all environments
│   └── application/
│       ├── destinations.ems           # Application-specific destinations
│       └── bridges.bridge             # Application-specific bridges
├── kubernetes/
│   ├── configmap-ems-objects-standalone.yaml # ConfigMap for standalone kubectl deployment
│   ├── job-ems-objects.yaml               # Kubernetes Job (standalone version)
│   └── DEPLOYMENT_GUIDE.md                 # Deployment instructions
├── helm-chart/                             # Complete Helm chart (RECOMMENDED)
│   ├── Chart.yaml                          # Helm chart metadata
│   ├── values.yaml                         # Configuration values
│   ├── .helmignore                         # Files to ignore when packaging
│   ├── README.md                           # Helm chart documentation
│   ├── ems-scripts/                        # EMS script files (copied from root)
│   │   ├── common/
│   │   └── application/
│   └── templates/                          # Helm templates
│       ├── _helpers.tpl                    # Helper templates
│       ├── configmap-ems-objects.yaml      # ConfigMap template
│       └── job-ems-objects.yaml            # Job template with smart hash checking
```

## Prerequisites

- TIBCO EMS 10.4 server running and accessible
- Kubernetes cluster access
- Docker (for building the container image)
- TIBCO EMS client binaries (`tibemsadmin`)

## EMS Script Files

### File Types

1. **`.ems` files**: Define queues, topics, and their properties
2. **`.bridge` files**: Define bridges between destinations

### Naming Convention

Files are processed in alphabetical order. Use numeric prefixes to control execution order:

- `1.*.ems` - Destinations (queues and topics)
- `2.*.ems` - Common bridges
- `3.*.bridge` - Environment-specific bridges

## Quick Start

### 1. Build the Docker Image

```bash
cd docker
docker build -t ems-admin:1.0.0 .
# Tag and push to your registry
docker tag ems-admin:1.0.0 your-registry/ems-admin:1.0.0
docker push your-registry/ems-admin:1.0.0
```

### 2. Customize EMS Scripts

Edit the files in `ems-scripts/` directory to define your EMS objects:

- Add queues/topics in `*.ems` files
- Add bridges in `.bridge` files

### 3. Update Kubernetes Manifests

**Option A: Using Helm (Recommended)**

The Helm chart includes smart hash-based execution that prevents unnecessary job reruns:
- Job automatically runs on first install
- On upgrade, calculates SHA256 hash of ConfigMap content
- Only reruns job if ConfigMap has actually changed
- Prevents duplicate EMS object creation attempts

```bash
# Create the EMS admin secret first
kubectl create secret generic ems-admin-secret --from-literal=password=emspassword

# Deploy with Helm
helm install ems-objects ./helm-chart

# Or with custom values
helm install ems-objects ./helm-chart \
  --set emsAdmin.serverName=your-ems-server \
  --set emsAdmin.image=your-registry/ems-admin:1.0.0

# Upgrade - job only runs if .ems or .bridge files changed
helm upgrade ems-objects ./helm-chart
```

**How the hash checking works:**
1. ConfigMap hash is calculated and stored in job annotation: `configmaphash`
2. On helm upgrade, new hash is compared with existing job's hash
3. If hashes differ (files changed), job is recreated and runs
4. If hashes match (no changes), job is skipped entirely

**Option B: Using kubectl (Standalone)**

For standalone deployment without Helm:
```bash
# Create the ConfigMap from files
kubectl create configmap ems-objects-scripts \
  --from-file=1.common.destinations.ems=ems-scripts/common/destinations.ems \
  --from-file=2.application.destinations.ems=ems-scripts/application/destinations.ems \
  --from-file=3.common.bridges.bridge=ems-scripts/common/bridges.bridge \
  --from-file=4.application.bridges.bridge=ems-scripts/application/bridges.bridge

# Create the secret
kubectl create secret generic ems-admin-secret --from-literal=password=emspassword

# Deploy the job
kubectl apply -f kubernetes/job-ems-objects.yaml
```

Note: Edit `kubernetes/job-ems-objects.yaml` to update:
- Docker image reference
- EMS server name (EMSSERVERNAME environment variable)
- Resource limits if needed

### 4. Deploy to Kubernetes

```bash
# Create the ConfigMap
kubectl apply -f kubernetes/configmap-ems-objects.yaml

# Run the Job
kubectl apply -f kubernetes/job-ems-objects.yaml

# Check job status
kubectl get jobs
kubectl logs job/job-ems-objects
```

## Configuration

### Environment Variables

- `EMSSERVERNAME`: EMS server hostname/service name (default: `emsserver-svc`)
- `EMS_PORT`: EMS server port (default: `7222`)
- `EMS_USER`: EMS admin username (default: `admin`)

### EMS Connection

The job connects to EMS using:
```
${EMSSERVERNAME}:7222 (user: admin)
```

Update the environment variables in the Job manifest to match your setup.

## EMS Script Examples

### Creating Queues

```
echo on

create queue APP.INBOUND.Q.01
setprop queue APP.INBOUND.Q.01 prefetch=1,failsafe
create jndiname APP.INBOUND.Q.01 queue APP.INBOUND.Q.01

commit
```

### Creating Topics

```
create topic APP.EVENTS.T.01
setprop topic APP.EVENTS.T.01 secure
create jndiname APP.EVENTS.T.01 topic APP.EVENTS.T.01

commit
```

### Creating Bridges

```
create bridge source=topic:APP.EVENTS.T.01 target=queue:APP.INBOUND.Q.01 selector="EventType='CRITICAL'"

commit
```

## Helm Integration

This solution can be integrated into Helm charts using hooks:

```yaml
annotations:
  "helm.sh/hook": pre-install,pre-upgrade
  "helm.sh/hook-weight": "-5"
  "helm.sh/hook-delete-policy": before-hook-creation
```

## Troubleshooting

### Check Job Logs

```bash
kubectl logs job/job-ems-objects
```

### Check EMS Server Connectivity

```bash
kubectl exec -it <ems-pod> -- /opt/tibco/ems/10.4/bin/tibemsadmin -server localhost:7222
```

### Common Issues

1. **Connection refused**: Check EMS server is running and accessible
2. **Authentication failed**: Verify EMS credentials
3. **Objects already exist**: Use `-ignore` flag in tibemsadmin (already included)

## Maintenance

### Updating EMS Objects

1. Modify the EMS scripts in `ems-scripts/`
2. Update the ConfigMap: `kubectl apply -f kubernetes/configmap-ems-objects.yaml`
3. Delete and recreate the job: 
   ```bash
   kubectl delete job job-ems-objects
   kubectl apply -f kubernetes/job-ems-objects.yaml
   ```

### Adding New Scripts

1. Create new `.ems` or `.bridge` files in `ems-scripts/`
2. Add them to the ConfigMap in `kubernetes/configmap-ems-objects.yaml`
3. Redeploy the ConfigMap and Job

## Notes

- The job uses the `-ignore` flag to prevent failures on existing objects
- Scripts are executed in alphabetical order
- Use numeric prefixes to control execution order
- All scripts should end with `commit` to ensure changes are applied

## License

**TIBCO EMS Enterprise License Required**

This project is a sample implementation demonstrating how to create and manage TIBCO EMS objects using DevOps and Platform Engineering practices. 

**Important Notes:**

- TIBCO Enterprise Messaging Service (EMS) requires a valid enterprise license from TIBCO Software Inc.
- This repository provides sample code and configurations for educational and demonstration purposes
- The approaches shown here are intended to help platform engineering teams implement infrastructure-as-code patterns for EMS object management

**Docker Image Distribution:**

⚠️ **DO NOT upload the Docker image created from this project to any public container registry.** The image contains TIBCO EMS client binaries which are proprietary software and subject to TIBCO's licensing terms. Only distribute images through private, internal registries within your organization.

