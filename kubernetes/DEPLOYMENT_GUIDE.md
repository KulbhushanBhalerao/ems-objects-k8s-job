# Kubernetes Deployment Guide

## Quick Start

### 1. Prerequisites Check

Before deploying, ensure you have:

- [x] Kubernetes cluster access (`kubectl` configured)
- [x] TIBCO EMS server running in the cluster or accessible from it
- [x] Docker image built and pushed to your registry
- [x] EMS server hostname/service name
- [x] Network connectivity from Kubernetes pods to EMS server (port 7222)

### 2. Verify EMS Connectivity

Test connection to EMS server from within the cluster:

```bash
# Create a test pod
kubectl run -it --rm debug --image=busybox --restart=Never -- sh

# Inside the pod, test connectivity
nc -zv emsserver-svc 7222
# or
telnet emsserver-svc 7222
```

### 3. Update Configuration

#### Update ConfigMap

Edit [configmap-ems-objects.yaml](configmap-ems-objects.yaml):

1. Modify the EMS scripts to match your requirements
2. Add/remove script sections as needed
3. Ensure script names maintain proper ordering (1., 2., 3., etc.)

#### Update Job Manifest

Edit [job-ems-objects.yaml](job-ems-objects.yaml):

1. Update the Docker image reference:
   ```yaml
   image: "your-registry.example.com/ems-admin:1.0.0"
   ```

2. Update EMS server configuration:
   ```yaml
   - name: EMSSERVERNAME
     value: "your-ems-server-svc"  # Update this
   ```

3. If using a private registry, uncomment and configure imagePullSecrets:
   ```yaml
   imagePullSecrets:
     - name: registry-secret
   ```

### 4. Deploy to Kubernetes

#### Option A: Using kubectl (Standalone)

**Important:** The main ConfigMap file uses Helm syntax. For standalone kubectl usage, create the ConfigMap from files directly:

```bash
# Navigate to project root
cd /Users/kul/data/ems-objects-creation-k8s-sample

# Create the ConfigMap from .ems and .bridge files
kubectl create configmap ems-objects-scripts \
  --from-file=1.common.destinations.ems=ems-scripts/common/destinations.ems \
  --from-file=2.application.destinations.ems=ems-scripts/application/destinations.ems \
  --from-file=3.common.bridges.ems=ems-scripts/common/bridges.ems \
  --from-file=4.application.bridges.ems=ems-scripts/application/bridges.ems \
  --from-file=5.dev.destinations.bridge=ems-scripts/application/dev_destinations.bridge \
  --dry-run=client -o yaml | kubectl apply -f -

# Verify ConfigMap was created
kubectl get configmap ems-objects-scripts
kubectl describe configmap ems-objects-scripts

# Create the Job
kubectl apply -f kubernetes/job-ems-objects.yaml

# Check job status
kubectl get jobs
kubectl describe job job-ems-objects-creation

# View logs
kubectl logs job/job-ems-objects-creation
```

#### Option B: Using Helm Chart (Recommended - with Smart Hash Checking)

The Helm version includes intelligent hash-based execution that prevents unnecessary job reruns:

**Features:**
- ✅ **Automatic Change Detection**: Calculates SHA256 hash of ConfigMap content
- ✅ **Smart Execution**: Job only runs when ConfigMap actually changes
- ✅ **Prevents Duplicate Work**: Skips job execution if .ems/.bridge files unchanged
- ✅ **Safe Upgrades**: Always runs on initial install, smart on upgrades

**Setup:**

```bash
# 1. Create the EMS admin password secret
kubectl create secret generic ems-admin-secret --from-literal=password=emspassword

# 2. Install the Helm chart
cd /Users/kul/data/ems-objects-creation-k8s-sample
helm install ems-objects ./helm-chart \
  --set emsAdmin.serverName=your-ems-server \
  --set emsAdmin.image=your-registry/ems-admin:1.0.0

# 3. Verify installation
kubectl get jobs
kubectl logs job/job-ems-objects-creation

# 4. Update .ems or .bridge files and upgrade
# Job will automatically rerun because hash changed
vim helm-chart/ems-scripts/common/destinations.ems
helm upgrade ems-objects ./helm-chart

# 5. Upgrade without changes
# Job will NOT rerun (hash unchanged)
helm upgrade ems-objects ./helm-chart --set emsAdmin.resources.requests.memory=512Mi
```

**How Hash Checking Works:**

1. **Initial Install** (`helm install`)
   - Job always runs to create EMS objects
   - ConfigMap hash stored in job annotation

2. **Upgrade with Changes** (`helm upgrade` after modifying .ems files)
   - New hash calculated from updated ConfigMap
   - Compared with existing job's hash annotation
   - Hashes differ → Job recreated and runs

3. **Upgrade without Changes** (`helm upgrade` with no .ems file changes)
   - New hash matches existing hash
   - Job skipped entirely (no recreation)

**View Hash Values:**

```bash
# Check current job's hash
kubectl get job job-ems-objects-creation -o jsonpath='{.metadata.annotations.configmaphash}'

# Check ConfigMap content
kubectl get configmap ems-objects-scripts -o yaml
```

### 5. Verify Deployment

```bash
# Check job status
kubectl get job job-ems-objects-creation

# Expected output:
# NAME                        COMPLETIONS   DURATION   AGE
# job-ems-objects-creation   1/1           45s        2m

# View detailed job information
kubectl describe job job-ems-objects-creation

# View pod logs
kubectl logs -l app=ems-admin

# If job completed, you might need to use:
kubectl logs -l app=ems-admin --previous
```

### 6. Verify EMS Objects Created

Connect to your EMS server and verify objects were created:

```bash
# Option 1: Use tibemsadmin from EMS server pod
kubectl exec -it <ems-server-pod> -- /opt/tibco/ems/10.4/bin/tibemsadmin -server localhost:7222

# Inside tibemsadmin:
> connect
> show queues
> show topics
> show bridges
> quit

# Option 2: From your local machine (if EMS is accessible)
/opt/tibco/ems/10.4/bin/tibemsadmin -server emsserver-svc:7222 -user admin
```

Expected output should show your created objects like:
```
APP.INBOUND.Q.01
APP.ORDER.PROCESSING.Q.01
APP.EVENTS.T.01
APP.ORDER.STATUS.T.01
...
```

## Namespace Deployment

### Deploy to Specific Namespace

```bash
# Create namespace
kubectl create namespace ems-admin

# Deploy to namespace
kubectl apply -f configmap-ems-objects.yaml -n ems-admin
kubectl apply -f job-ems-objects.yaml -n ems-admin

# View in namespace
kubectl get all -n ems-admin
```

### Environment-Specific Deployments

For multiple environments (dev, test, prod), you can use different ConfigMaps:

```bash
# Development
kubectl apply -f configmap-ems-objects.yaml -n dev
kubectl apply -f job-ems-objects.yaml -n dev

# Test
kubectl apply -f configmap-ems-objects-test.yaml -n test
kubectl apply -f job-ems-objects.yaml -n test

# Production
kubectl apply -f configmap-ems-objects-prod.yaml -n production
kubectl apply -f job-ems-objects.yaml -n production
```

## Updating EMS Objects

### Method 1: Update and Rerun Job (kubectl)

```bash
# 1. Update your .ems and .bridge files in ems-scripts/ directory

# 2. Recreate ConfigMap from updated files
kubectl create configmap ems-objects-scripts \
  --from-file=1.common.destinations.ems=ems-scripts/common/destinations.ems \
  --from-file=2.application.destinations.ems=ems-scripts/application/destinations.ems \
  --from-file=3.common.bridges.ems=ems-scripts/common/bridges.ems \
  --from-file=4.application.bridges.ems=ems-scripts/application/bridges.ems \
  --from-file=5.dev.destinations.bridge=ems-scripts/application/dev_destinations.bridge \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Delete existing job
kubectl delete job job-ems-objects-creation

# 4. Recreate job
kubectl apply -f kubernetes/job-ems-objects.yaml

# 5. Monitor
kubectl logs -f job/job-ems-objects-creation
```

### Method 2: Using ConfigMap Hash (Automatic Detection)

If using with Helm and hash annotations, the job automatically reruns when ConfigMap changes.

## Troubleshooting

### Job Failed to Complete

```bash
# Check job status
kubectl get job job-ems-objects-creation

# Describe for events
kubectl describe job job-ems-objects-creation

# Check pod logs
kubectl logs -l app=ems-admin

# Check pod status
kubectl get pods -l app=ems-admin
```

### Common Issues

#### 1. Image Pull Error

**Symptom:** Pod status shows `ImagePullBackOff` or `ErrImagePull`

**Solution:**
```bash
# Check if image exists in registry
docker pull your-registry.example.com/ems-admin:1.0.0

# Create image pull secret if using private registry
kubectl create secret docker-registry registry-secret \
  --docker-server=your-registry.example.com \
  --docker-username=your-username \
  --docker-password=your-password \
  --docker-email=your-email@example.com

# Update job to use the secret (already in template, just uncomment)
```

#### 2. EMS Connection Failed

**Symptom:** Logs show "Connection refused" or "tibemsadmin: can't connect to server"

**Solution:**
```bash
# Verify EMS server is running
kubectl get pods -l app=ems-server

# Test network connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- nc -zv emsserver-svc 7222

# Check EMS server service
kubectl get svc emsserver-svc
kubectl describe svc emsserver-svc

# Verify DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup emsserver-svc
```

#### 3. Permission Errors

**Symptom:** Logs show "Error: not authorized" or "security violation"

**Solution:**
- Verify EMS admin credentials
- Check EMS ACL configuration
- Ensure admin user has permission to create objects

#### 4. ConfigMap Not Mounted

**Symptom:** Logs show "No EMS script files found"

**Solution:**
```bash
# Verify ConfigMap exists
kubectl get configmap ems-objects-scripts

# Check ConfigMap content
kubectl describe configmap ems-objects-scripts

# Verify volume mount in pod
kubectl describe pod -l app=ems-admin
```

### Debug Mode

To run the job with debug output:

```bash
# Edit the job to run with a debug shell
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: job-ems-debug
spec:
  template:
    spec:
      containers:
      - name: ems-admin
        image: ems-admin:1.0.0
        command: ["sh"]
        args: ["-c", "ls -la /scripts/destination/ && cat /scripts/destination/* && sh /scripts/ems-admin.sh"]
        env:
        - name: EMSSERVERNAME
          value: "emsserver-svc"
        volumeMounts:
        - name: ems-scripts
          mountPath: "/scripts/destination"
      volumes:
      - name: ems-scripts
        configMap:
          name: ems-objects-scripts
      restartPolicy: Never
EOF

# View logs
kubectl logs job/job-ems-debug
```

## Cleanup

### Remove Job and ConfigMap

```bash
# Delete job
kubectl delete job job-ems-objects-creation

# Delete ConfigMap
kubectl delete configmap ems-objects-scripts

# Or delete both at once
kubectl delete -f kubernetes/
```

### Remove Created EMS Objects

To remove objects from EMS, create a cleanup script:

```bash
# Create cleanup ConfigMap
kubectl create configmap ems-cleanup-scripts --from-literal=cleanup.ems="
echo on
delete queue APP.INBOUND.Q.01
delete queue APP.ORDER.PROCESSING.Q.01
delete topic APP.EVENTS.T.01
delete topic APP.ORDER.STATUS.T.01
commit
"

# Run cleanup job
kubectl apply -f job-ems-objects.yaml
# (After updating configmap reference)
```

## Best Practices

1. **Version Control**: Keep ConfigMaps and Job manifests in Git
2. **Environment Separation**: Use separate namespaces for dev/test/prod
3. **Secrets Management**: Never hardcode passwords; use Kubernetes Secrets
4. **Resource Limits**: Always set resource requests and limits
5. **Monitoring**: Set up alerts for job failures
6. **Idempotency**: Always use `-ignore` flag to handle existing objects
7. **Logging**: Preserve job logs for auditing (set `ttlSecondsAfterFinished`)

## Advanced Configuration

### Using Secrets for EMS Credentials

```bash
# Create secret
kubectl create secret generic ems-credentials \
  --from-literal=username=admin \
  --from-literal=password=your-password

# Reference in job (already in template, uncomment):
# - name: EMS_PASSWORD
#   valueFrom:
#     secretKeyRef:
#       name: ems-credentials
#       key: password
```

### Scheduled Execution

To run the job periodically, use a CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ems-objects-sync
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        # ... same as job-ems-objects.yaml
```

## Support

For issues or questions:
- Check EMS server logs
- Review Kubernetes events: `kubectl get events --sort-by='.lastTimestamp'`
- Verify TIBCO EMS documentation for object creation syntax
