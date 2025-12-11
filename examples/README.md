# Shopping Cart Infrastructure Examples

This directory contains example files and templates for building, testing, and deploying the Shopping Cart microservices.

## Directory Structure

```
examples/
├── dockerfiles/          # Sample Dockerfiles for each service
├── github-actions/       # GitHub Actions workflow templates
└── README.md            # This file
```

## Dockerfiles

Sample multi-stage Dockerfiles optimized for each technology stack:

- **Dockerfile.product-catalog** (Node.js/Express)
  - Alpine-based, multi-stage build
  - Production-only dependencies
  - Non-root user for security
  - Health checks included

- **Dockerfile.shopping-cart** (Python/Flask)
  - Slim Python image
  - Gunicorn production server
  - Optimized layer caching
  - Non-root user for security

- **Dockerfile.order-service** (Java/Spring Boot)
  - Maven multi-stage build
  - JRE-only runtime (no JDK)
  - Container-optimized JVM settings
  - Spring Actuator health checks

- **Dockerfile.payment-service** (Go)
  - Scratch-based for minimal size
  - Static binary compilation
  - No shell (maximum security)
  - Minimal attack surface

### Using the Dockerfiles

Copy the appropriate Dockerfile to your service repository:

```bash
# Example: Copy product-catalog Dockerfile
cp examples/dockerfiles/Dockerfile.product-catalog ../shopping-cart-product-catalog/Dockerfile
```

## GitHub Actions Workflows

Production-ready GitHub Actions workflows for CI/CD:

### build-push.yml

Complete workflow with:
- **PR validation**: Dockerfile linting (Hadolint), security scanning (Trivy)
- **Multi-tag strategy**: Git SHA, branch name, semantic versioning, latest
- **Container registry**: Push to GitHub Container Registry (GHCR)
- **Security**: Build attestation and provenance
- **Integration**: Jenkins webhook trigger for deployment
- **Testing**: Container health check validation

### Setting Up GitHub Actions

1. **Copy workflow to service repository:**
   ```bash
   mkdir -p .github/workflows
   cp examples/github-actions/build-push.yml .github/workflows/
   ```

2. **Configure repository secrets** (Settings → Secrets and variables → Actions):
   - `JENKINS_WEBHOOK_URL` - Jenkins webhook endpoint
   - `JENKINS_WEBHOOK_TOKEN` - Authentication token for Jenkins

3. **Adjust workflow for your service:**
   - Modify port numbers in health check (line 148)
   - Adjust health endpoint path if different from `/health`
   - Update build context if using subdirectories

4. **Test the workflow:**
   - Create a PR to trigger lint/scan jobs
   - Merge to main to trigger build/push jobs
   - Create a release to trigger version tagging

## Quick Start Guide

### 1. Local Testing with build-and-push.sh

Test building images locally before setting up CI/CD:

```bash
# Build product-catalog image (no push)
./scripts/build-and-push.sh product-catalog

# Build and push to GHCR
./scripts/build-and-push.sh product-catalog latest --push

# Build with version tag
./scripts/build-and-push.sh shopping-cart v1.0.0 --push
```

The script will:
- Create a temporary build context with sample application
- Build the Docker image
- Tag with git SHA (if in git repository)
- Test the container locally
- Optionally push to GHCR

### 2. Setting Up GHCR Authentication

#### Using GitHub CLI (Recommended)

```bash
# Login to GitHub CLI
gh auth login

# Authenticate Docker with GHCR
export GITHUB_TOKEN=$(gh auth token)
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

#### Using Personal Access Token

1. Create PAT at: https://github.com/settings/tokens/new
   - Scopes: `write:packages`, `read:packages`, `delete:packages`
   - Note: "GHCR Access for Shopping Cart"

2. Login to GHCR:
   ```bash
   export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
   echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin
   ```

### 3. Creating a Test Repository

Create a test repository to verify the workflow:

```bash
# Create new repository
mkdir shopping-cart-product-catalog
cd shopping-cart-product-catalog

# Initialize git
git init

# Copy Dockerfile
cp ../shopping-cart-infra/examples/dockerfiles/Dockerfile.product-catalog ./Dockerfile

# Copy workflow
mkdir -p .github/workflows
cp ../shopping-cart-infra/examples/github-actions/build-push.yml .github/workflows/

# Create sample application (Node.js example)
cat > package.json << 'EOF'
{
  "name": "product-catalog",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

cat > server.js << 'EOF'
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  res.json({ service: 'product-catalog', status: 'healthy' });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.listen(port, () => {
  console.log(`Product Catalog listening on port ${port}`);
});
EOF

# Create .dockerignore
cat > .dockerignore << 'EOF'
.git
.github
*.md
.env
node_modules
EOF

# Create remote repository and push
gh repo create shopping-cart-product-catalog --public --source=. --remote=origin
git add .
git commit -m "Initial commit with GitHub Actions workflow"
git push -u origin main

# Monitor workflow execution
gh run watch
```

### 4. Verifying the Image in GHCR

After successful push:

```bash
# List image versions
gh api /user/packages/container/product-catalog/versions | jq -r '.[].metadata.container.tags[]'

# Pull and test locally
docker pull ghcr.io/YOUR_USERNAME/product-catalog:latest
docker run -d -p 3000:3000 ghcr.io/YOUR_USERNAME/product-catalog:latest
curl http://localhost:3000/health
```

## Integration with Jenkins

The GitHub Actions workflow triggers Jenkins after successful image push to main branch.

### Jenkins Webhook Configuration

Jenkins should expose a webhook endpoint that accepts:

```json
{
  "service": "product-catalog",
  "image_tag": "main-a1b2c3d",
  "git_sha": "a1b2c3d4e5f6g7h8i9j0",
  "git_ref": "refs/heads/main",
  "git_author": "username",
  "commit_message": "feat: add new feature"
}
```

Jenkins pipeline will:
1. Receive webhook notification
2. Pull infrastructure repository
3. Update Helm values with new image tag
4. Commit and push changes
5. Argo CD automatically syncs and deploys

## Security Best Practices

### Dockerfile Security

- Use specific image versions (not `latest`)
- Run as non-root user
- Use multi-stage builds to minimize image size
- Scan for vulnerabilities with Trivy
- Use `.dockerignore` to exclude sensitive files

### GitHub Actions Security

- Use `secrets.GITHUB_TOKEN` (auto-provided, scoped)
- Never hardcode credentials in workflows
- Enable branch protection rules
- Require PR reviews before merge
- Use build attestation for supply chain security

### GHCR Security

- Set package visibility (public vs private)
- Enable vulnerability scanning
- Use signed commits
- Rotate PATs regularly
- Use least-privilege scopes

## Troubleshooting

### Docker Build Fails

```bash
# Check Dockerfile syntax
docker build --no-cache -t test .

# Validate with Hadolint
docker run --rm -i hadolint/hadolint < Dockerfile
```

### Authentication Issues

```bash
# Verify GitHub authentication
gh auth status

# Re-login to GHCR
gh auth logout
gh auth login
export GITHUB_TOKEN=$(gh auth token)
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

### Workflow Not Triggering

- Check branch name matches workflow triggers
- Verify paths-ignore doesn't exclude your changes
- Check repository settings → Actions → General → Workflow permissions
- Review workflow run logs in Actions tab

## Additional Resources

- [Container Image Workflow Guide](../docs/container-image-workflow.md) - Comprehensive guide
- [CI/CD Architecture](../docs/cicd-architecture.md) - Complete pipeline documentation
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GHCR Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
