# Docker Image Build Instructions

## Prerequisites

You need to copy the TIBCO EMS 10.4 client binaries to this directory before building the Docker image.

## Best Practice: Use CI/CD Pipeline (Recommended)

**For production environments, build this image using Azure DevOps Pipeline or GitHub Actions workflow:**

### Why Use CI/CD Pipelines?

- ✅ **Reproducible builds** - Consistent image builds across environments
- ✅ **Secure storage** - TIBCO binaries stored in artifact repository, not in source control
- ✅ **Automated testing** - Validate image before deployment
- ✅ **Audit trail** - Track who built what and when
- ✅ **Secret management** - Secure handling of registry credentials

### Recommended Workflow

1. **Store EMS binaries in artifact repository:**
   - Azure Artifacts (Azure DevOps)
   - GitHub Packages
   - JFrog Artifactory
   - Nexus Repository

2. **Pipeline downloads binaries during build:**
   ```yaml
   # Azure DevOps Pipeline example
   - task: DownloadPackage@1
     inputs:
       packageType: 'generic'
       feed: 'tibco-binaries'
       definition: 'ems-10.4-client'
       version: '10.4.0'
       downloadPath: '$(Build.SourcesDirectory)/docker/scripts'

   # GitHub Actions example
   - name: Download EMS binaries
     run: |
       curl -H "Authorization: token ${{ secrets.GITHUB_TOKEN }}" \
         -L https://maven.pkg.github.com/.../ems-client-10.4.tar.gz \
         -o ems-binaries.tar.gz
       tar -xzf ems-binaries.tar.gz -C docker/scripts/
   ```

3. **Build and push image:**
   - Build Docker image in pipeline
   - Run security scans (Trivy, Aqua, etc.)
   - Push to container registry
   - Tag with version/commit SHA

4. **Clean up:**
   - Binaries are never committed to source control
   - Downloaded dynamically during each build

### Example Pipeline Structure

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
    - main
  paths:
    include:
    - docker/**

variables:
  imageRepository: 'ems-admin'
  containerRegistry: 'yourregistry.azurecr.io'
  tag: '$(Build.BuildId)'

stages:
- stage: Build
  jobs:
  - job: BuildImage
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - task: DownloadPackage@1
      displayName: 'Download TIBCO EMS binaries'
      inputs:
        packageType: 'universal'
        feed: 'tibco-artifacts'
        definition: 'ems-client-binaries'
        version: '10.4.0'
        downloadPath: '$(Build.SourcesDirectory)/docker/scripts'
    
    - task: Docker@2
      displayName: 'Build Docker image'
      inputs:
        command: 'build'
        repository: $(imageRepository)
        dockerfile: '$(Build.SourcesDirectory)/docker/Dockerfile'
        tags: |
          $(tag)
          latest
    
    - task: Docker@2
      displayName: 'Push to container registry'
      inputs:
        command: 'push'
        repository: $(imageRepository)
        containerRegistry: $(containerRegistry)
        tags: |
          $(tag)
          latest
```

---

## Manual Build Instructions (Development Only)

**Note:** The following manual steps are for local development/testing only. For production, use the CI/CD pipeline approach above.

## Step 1: Copy EMS Client Binaries

From your local TIBCO EMS installation (`/opt/tibco/ems/10.4`), copy the following directories:

```bash
# Navigate to the docker directory
cd /Users/kul/data/ems-objects-creation-k8s-sample/docker

# Create the target directories
mkdir -p scripts/bin
mkdir -p scripts/lib

# Copy binaries from local EMS installation
cp -r /opt/tibco/ems/10.4/bin/* scripts/bin/
cp -r /opt/tibco/ems/10.4/lib/* scripts/lib/

# Verify the files are copied
ls -l scripts/bin/tibemsadmin
ls -l scripts/lib/*.jar
```

### Required Files

**bin directory should contain:**
- `tibemsadmin` (EMS admin tool)
- Other supporting binaries

**lib directory should contain:**
- `tibjms.jar` (TIBCO EMS client library)
- `tibcrypt.jar`
- Other supporting JAR files

## Step 2: Verify Directory Structure

After copying, your directory structure should look like:

```
docker/
├── Dockerfile
├── BUILD_INSTRUCTIONS.md
└── scripts/
    ├── ems-admin.sh
    ├── bin/
    │   ├── tibemsadmin
    │   └── ... (other binaries)
    └── lib/
        ├── tibjms.jar
        ├── tibcrypt.jar
        └── ... (other JARs)
```

## Step 3: Build the Docker Image

```bash
# From the docker directory
docker build -t ems-admin:1.0.0 .

# Or specify a custom tag
docker build -t your-registry/ems-admin:1.0.0 .
```

## Step 4: Test the Image Locally

```bash
# Create a test directory with a simple EMS script
mkdir -p /tmp/ems-test
cat > /tmp/ems-test/test.ems << 'EOF'
echo on
create queue TEST.Q.01
commit
EOF

# Run the container (replace EMSSERVERNAME with your EMS server)
docker run --rm \
  -v /tmp/ems-test:/scripts/destination:ro \
  -e EMSSERVERNAME=your-ems-server \
  ems-admin:1.0.0
```

## Step 5: Push to Container Registry

```bash
# Login to your container registry
docker login your-registry.example.com

# Tag the image
docker tag ems-admin:1.0.0 your-registry.example.com/ems-admin:1.0.0

# Push the image
docker push your-registry.example.com/ems-admin:1.0.0
```

## Troubleshooting

### Issue: "tibemsadmin not found"

**Solution:** Ensure you copied the binaries correctly and they have execute permissions:

```bash
chmod +x scripts/bin/tibemsadmin
ls -l scripts/bin/tibemsadmin
```

### Issue: "ClassNotFoundException" or Java errors

**Solution:** Verify all required JAR files are in the lib directory:

```bash
ls -l scripts/lib/*.jar
# Should see tibjms.jar, tibcrypt.jar, etc.
```

### Issue: "Permission denied" errors

**Solution:** Ensure files are readable:

```bash
chmod -R 644 scripts/lib/*
chmod -R 755 scripts/bin/*
```

## Alternative: Using a Base Image with EMS

If you have an existing base image with TIBCO EMS installed, you can modify the Dockerfile:

```dockerfile
FROM your-registry/tibco-ems-base:10.4

# No need to copy bin and lib directories
# Just copy the admin script
COPY scripts/ems-admin.sh /scripts/ems-admin.sh
RUN chmod +x /scripts/ems-admin.sh

CMD ["sh", "/scripts/ems-admin.sh"]
```

## Notes

- The image uses Red Hat UBI 8 minimal as the base image
- TIBCO user (UID 2001, GID 2001) is created for running the container
- The container runs as a non-root user for security
- EMS binaries are installed at `/opt/tibco/ems/10.4`
- Scripts are mounted at `/scripts/destination` via ConfigMap

## Security Best Practices

### Artifact Repository Setup

1. **Never commit TIBCO binaries to Git:**
   ```bash
   # Add to .gitignore
   docker/scripts/bin/
   docker/scripts/lib/
   *.jar
   ```

2. **Store binaries in secure artifact repository:**
   - Use versioned packages
   - Implement access controls
   - Enable audit logging
   - Scan for vulnerabilities

3. **Use service principals/tokens in CI/CD:**
   - Azure DevOps: Use service connections
   - GitHub: Use secrets for artifact access
   - Never hardcode credentials

### Image Security Scanning

Include security scanning in your pipeline:

```yaml
# Trivy security scan example
- task: trivy@1
  inputs:
    image: '$(containerRegistry)/$(imageRepository):$(tag)'
    severityThreshold: 'HIGH'
    exitCode: '1'  # Fail build on HIGH/CRITICAL vulnerabilities
```

## License Considerations

⚠️ **Important**: TIBCO EMS is commercial software. Ensure you have proper licensing before distributing this image.

- Do not push to public registries
- Use private container registries
- Store binaries in private artifact repositories only
- Ensure compliance with TIBCO license agreements
- Implement proper access controls on artifact repository
