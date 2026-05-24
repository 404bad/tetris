# Tetris DevSecOps Project

A full end-to-end DevSecOps implementation using a classic Tetris game as the application. This project demonstrates real-world DevOps and security practices from local development to production deployment.

## Tech Stack

- App: React + Redux + Webpack
- Containerization: Docker + Docker Compose
- CI/CD: GitHub Actions
- Security: Trivy, SonarQube, npm audit, GitLeaks
- Orchestration: Kubernetes (Helm)
- Monitoring: Prometheus + Grafana + Loki

## Pipeline Overview

Code Push → Build → Test → Security Scan → Docker Image → Push to Registry → Deploy to K8s → Monitor

# DevOpsifying the tetric application

## Step 1: Containerization with Docker

This step packages the Tetris app into a lightweight, production-ready Docker image using a multi-stage build strategy.

files addes:

- Dockerfile — instructions to build the Docker image
- .dockerignore — files to exclude from the build context

### Dockerfile Breakdown

Uses Node.js 18 on Alpine Linux (lightweight ~50MB base image) as the build environment. Named builder so Stage 2 can reference it.

Sets the working directory inside the container. All subsequent commands run from /app.

Copies package.json and package-lock.json first — before the rest of the code. This is a Docker layer caching trick: if dependencies haven't changed, Docker skips the npm ci step on the next build, saving time.

Installs dependencies using npm ci (clean install) instead of npm install.

Copies the rest of the source code into the container.

Builds the React app for production. Outputs optimized static files into the /app/build folder (minified JS, CSS, HTML).

Starts a fresh, clean image using nginx on Alpine. The Node.js environment from Stage 1 is completely discarded — the final image contains only nginx and the static build files. This keeps the image small and secure.

Copies only the production build output from Stage 1 into nginx's default serving directory.

Documents that the container listens on port 80 (HTTP). This is informational — actual port mapping happens at docker run time.

Starts nginx in the foreground.
By default, nginx runs as a background daemon (detached process). Docker requires the main process to stay in the foreground — if the process exits, the container stops. daemon off; overrides this behavior and keeps nginx running in the foreground, keeping the container alive.

### .dockerignore

Tells Docker to exclude these from the build context.

### Multi-Stage Build — Why it matters

|                      | Single Stage                        | Multi-Stage               |
| -------------------- | ----------------------------------- | ------------------------- |
| Final image contains | Node.js + npm + source code + build | Only nginx + static files |
| Image size           | ~400MB+                             | ~25MB                     |
| Attack surface       | Large                               | Minimal                   |
| Source code exposed  | Yes                                 | No                        |

### Build and run locally

```bash
docker build -t tetris-app .

docker run -p 3000:80 tetris-app

docker ps

docker stop <container_id>

# Check image size
docker images tetris-app


```

### What We Achieved

- App runs in an isolated, reproducible container
- Production-optimized build served via nginx
- Image is minimal (~25MB) and secure
- No Node.js or source code in the final image
- Ready to push to any container registry (DockerHub, ECR, GCR)
  Share

### Docker compose

Docker Compose is a tool for defining and running multi-container Docker applications. Instead of running long docker run commands manually every time, you define everything in a single docker-compose.yml file and bring your entire stack up with one command.

Think of it this way:

Dockerfile → defines how to build one container

docker-compose.yml → defines how to run one or more containers together

### Docker Compose vs docker run

|                                    | `docker run` | `docker compose` |
| ---------------------------------- | ------------ | ---------------- |
| Single container                   | no           | yes              |
| Multi container                    | no           | yes              |
| Reproducible setup                 | no           | yes              |
| One command for everything         | no           | yes              |
| Easy to read and share             | no           | yes              |
| Used in CI/CD pipelines            | no           | yes              |
| Auto networking between containers | no Manual    | yes Automatic    |

### How its fits in DevSecOps pipeline

```bash
Developer pushes code
        ↓
CI/CD pipeline runs:
  docker compose build   ← builds the image
  docker compose up -d   ← starts the stack
        ↓
Monitoring stack (Prometheus + Grafana) comes up alongside the app
        ↓
Everything runs together, networked automatically
```

As we add more services (Prometheus, Grafana, Loki) in the monitoring step, we simply add them to the same docker-compose.yml — no extra configuration needed.

## Step 3: CI/CD Pipeline with GitHub Actions

CI (Continuous Integration) means every time I push code, it automatically builds and tests it — catching issues early before they reach production.

CD (Continuous Delivery) means once the build passes, it automatically packages and delivers the artifact (in our case, a Docker image) to a registry — ready to deploy at any time.

Together, CI/CD removes manual steps from my workflow. I push code, the pipeline does the rest.

### Why GitHub Actions?

I chose GitHub Actions because:

- It lives directly in my repository — no separate CI server to manage
- Free for public repositories
- Huge library of ready-made actions (checkout, docker login, metadata, build-push)
- Native integration with GitHub events (push, pull request, tags)

### Pipeline Structure

My pipeline has two jobs that run in sequence:

```
Push to GitHub
      ↓
 ┌─────────────┐
 │  Job 1      │
 │  Build &    │
 │  Test       │
 └──────┬──────┘
        │ only if Job 1 passes
        ↓
 ┌─────────────┐
 │  Job 2      │
 │  Build &    │
 │  Push to    │
 │  Docker Hub │
 └─────────────┘
```

Job 2 only runs if Job 1 passes. This means I never push a broken image to Docker Hub.

---

### Pipeline Triggers

I configured three triggers:

| Trigger        | When it fires                                   | What it does                      |
| -------------- | ----------------------------------------------- | --------------------------------- |
| `push to main` | Every time I push code to main                  | Build, test, push `latest` image  |
| `tag v*`       | Every time I create a version tag like `v1.0.0` | Build, test, push versioned image |
| `pull_request` | Every time I open a PR to main                  | Build and test only — no push     |

The pull request trigger is important — it validates my code before it even merges, acting as a gate.

---

### Why Three Tags: latest, 1.0, 1.0.0

When I push the tag v1.0.0 to GitHub, the metadata action automatically creates three Docker Hub tags for the same image:

#### latest

```
myusername/tetris-app:latest


```

This always points to the most recent image built from the main branch. When someone runs docker pull myusername/tetris-app without specifying a version, they get latest. It is the default, and it always reflects the current stable state of the app.

#### 1.0

```
myusername/tetris-app:1.0
```

This is the minor version tag — it covers the entire 1.0.x release line. Every time I release v1.0.0, v1.0.1, v1.0.2, this tag gets updated to point to the latest patch. Someone who pins to 1.0 always gets my latest bug fixes within the 1.0 line without jumping to a breaking change in 2.0.

#### 1.0.0

```
myusername/tetris-app:1.0.0

```

This is the exact version tag — it is immutable. Once pushed, it never changes. Someone who pins to 1.0.0 always gets exactly that build, forever. This is critical for reproducibility — if something breaks in 1.0.1, I can always roll back to 1.0.0 with confidence.

This is the standard Docker tagging strategy used in production. It gives consumers of my image the flexibility to choose how much they want to follow updates.

I use a Docker Hub Access Token instead of my actual password. Go to hub.docker.com → Account Settings → Security → New Access Token. This way even if the token is compromised, I can revoke it without changing my password.

#### How to Trigger a Release

```bash
# Tag the commit
git tag v1.0.0

# Push the tag to GitHub
git push origin v1.0.0


```

### What I Achieved

- Every push to main automatically builds and tests the app
- Every version tag automatically publishes a Docker image to Docker Hub
- Pull requests are validated before merging — nothing broken gets into main
- Credentials are stored securely as GitHub Secrets — never in code
- Docker images are properly versioned with three tags for flexibility and reproducibility

## Step 4: Security Scanning

Security scanning is the "Sec" in DevSecOps. Instead of treating security as a final checkpoint before release, I shift it left — meaning I run security checks automatically on every push, as part of the pipeline, before the image ever reaches Docker Hub.

My pipeline runs three scanners, each catching a different category of vulnerability:

```
Code pushed to GitHub
        ↓
┌───────────────────┐
│  npm audit        │  ← dependency vulnerabilities
│  Gitleaks         │  ← hardcoded secrets in code
│  Trivy            │  ← Docker image CVEs
└───────────────────┘
        ↓
Only if scanning passes → push to Docker Hub
```

---

### Scanner 1: npm audit

**What it does:**
`npm audit` checks every package in `node_modules` against the **npm advisory database** — a registry of known vulnerabilities (CVEs) in open source packages. It reports which packages have known security issues and how severe they are.

**Why I use it:**
This project uses older dependencies like `postcss@7` and older versions of `babel`. These packages likely have known CVEs — `npm audit` surfaces them with severity ratings (Low, Moderate, High, Critical) so I know exactly what needs to be updated.

**The `--audit-level=high` flag:**
Only fails the pipeline if a **High or Critical** vulnerability is found. Low and Moderate issues are reported but don't block the build — a practical balance between security and not breaking the pipeline on every minor issue.

**The `continue-on-error: true` flag:**
Since this is an older project with known dependency issues, I set this to `true` so the pipeline continues even if audit finds issues. In a production project I would remove this once vulnerabilities are remediated.

**Sample output:**

```
found 12 vulnerabilities (3 moderate, 7 high, 2 critical)
```

> This is actually useful for the project — it gives me real vulnerabilities to document, prioritize, and fix.

---

### Scanner 2: Gitleaks

```yaml
- name: Run Gitleaks (secrets scan)
  uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  continue-on-error: true
```

**What it does:**
Gitleaks scans the entire Git history and source code for accidentally committed secrets — API keys, passwords, tokens, private keys, connection strings, and other sensitive data.

**Why this matters:**
One of the most common and damaging security mistakes is accidentally committing a secret to a public repository. Even if I delete the file in the next commit, the secret is still in Git history and can be extracted. Gitleaks catches this before it becomes a problem.

**What it detects:**

- AWS access keys
- GitHub tokens
- Docker Hub credentials
- Private keys (RSA, PEM)
- Database connection strings
- Generic high-entropy strings that look like secrets

**The `GITHUB_TOKEN`:**
This is an automatically generated token provided by GitHub Actions for every pipeline run. Gitleaks uses it to authenticate with the GitHub API. I don't need to create this secret manually — GitHub provides it automatically.

**Why `continue-on-error: true`:**
Same reason as npm audit — to keep the pipeline running while I'm building the project. In production this would be `false` — any detected secret immediately fails the build.

---

### Scanner 3: Trivy

```yaml
- name: Build Docker image for scanning
  run: docker build -t tetris-app:scan .

- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: tetris-app:scan
    format: table
    exit-code: "0"
    severity: CRITICAL,HIGH
```

**What it does:**
Trivy is an open source vulnerability scanner by Aqua Security. It scans the final Docker image for known CVEs in:

- OS packages (Alpine Linux packages inside the image)
- Application dependencies (Node.js packages)
- Base image vulnerabilities (nginx:alpine, node:16-alpine)

**Why I build the image first:**
Trivy needs a built Docker image to scan. I build it with the tag `tetris-app:scan` specifically for scanning — separate from the image that gets pushed to Docker Hub.

**The `format: table` flag:**
Outputs results as a human-readable table in the pipeline logs. Other options are `json` and `sarif` (for GitHub Security tab integration).

**The `severity: CRITICAL,HIGH` flag:**
Only reports Critical and High vulnerabilities — filters out noise from Low and Medium issues so I can focus on what matters most.

**The `exit-code: '0'` flag:**
Does not fail the pipeline even if vulnerabilities are found — it reports them and continues. Setting this to `'1'` would fail the build on any Critical/High finding, which is the production standard.

**Sample output:**

```
┌─────────────────┬────────────────┬──────────┬───────────────────┐
│    Library      │ Vulnerability  │ Severity │     Title         │
├─────────────────┼────────────────┼──────────┼───────────────────┤
│ node:16-alpine  │ CVE-2023-xxxx  │ HIGH     │ OpenSSL issue     │
│ nth-check       │ CVE-2021-3803  │ HIGH     │ ReDoS in nth-check│
└─────────────────┴────────────────┴──────────┴───────────────────┘
```

### Pipeline Order — Why Security Runs Before Docker Push

```yaml
security:
  needs: build   ← waits for build to pass

docker:
  needs: security  ← waits for security to pass
```

I deliberately placed security scanning between the build job and the Docker Hub push job. This means:

1. App must build successfully first
2. Security scans run on the built app and image
3. Only after scanning completes does the image get pushed to Docker Hub

This ensures I never publish an unscanned image. Even with `continue-on-error: true` during development, the scans always run and their results are always visible in the pipeline logs.

---

### Security Job in the Full Pipeline

```
Push to GitHub
      ↓
Build & Test          (Job 1)
      ↓
Security Scanning     (Job 2)
  ├── npm audit       → dependency CVEs
  ├── Gitleaks        → secrets in code
  └── Trivy           → Docker image CVEs
      ↓
Build & Push          (Job 3)
  └── Docker Hub      → versioned image
```

---

### What I Achieved

- Every push automatically scans dependencies, secrets, and the Docker image
- Security is enforced in the pipeline — not an afterthought
- Real vulnerabilities are surfaced, documented, and tracked as actionable TODOs
- No unscanned image ever reaches Docker Hub
- Secrets are never committed to the repository

## Step 5: Infrastructure as Code with Terraform — EKS on AWS

At this point I had a working Docker image, a CI/CD pipeline, and security scanning in place. The next challenge was deploying the app to a real Kubernetes cluster on AWS. I could have clicked through the AWS console to create everything manually — but that approach doesn't scale, isn't reproducible, and is impossible to version control or destroy cleanly. That's why I chose Terraform.

Terraform lets me define my entire AWS infrastructure as code. Every VPC, subnet, IAM role, and EKS cluster is declared in `.tf` files and tracked in a state file. When I'm done, `terraform destroy` removes every single resource — no dangling charges, no leftover orphaned resources in my AWS account.

### Why Terraform over the AWS Console?

If I created the EKS cluster manually through the console, I would have no record of exactly what I built. The next time I needed to recreate it — for a different environment, after an accidental deletion, or for a teammate, I'd be clicking through screens trying to remember what I did. With Terraform, my infrastructure is documented in code, reproducible in minutes, and destroyable in one command.

### Files Created

```
terraform/
├── versions.tf           # provider version pins
├── variables.tf          # all input variables with defaults
├── provider.tf           # AWS provider configuration
├── vpc.tf                # all networking resources
├── eks.tf                # EKS cluster, node group, IAM roles
├── outputs.tf            # useful values printed after apply
└── aws-lbc-policy.json   # IAM policy for AWS Load Balancer Controller
```

---

### versions.tf — Pinning Provider Versions

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
```

I pin provider versions deliberately. Without pins, `terraform init` would always pull the latest provider — and a breaking change in a new provider version could silently break my configuration on the next run. `~> 5.0` means "any 5.x version" — I get bug fixes and minor updates but never a breaking major version upgrade without my explicit change.

I need two providers:

- **aws** — the main provider that creates all AWS resources
- **tls** — used to read the OIDC certificate thumbprint from the EKS cluster, which is required to set up IAM Roles for Service Accounts (IRSA) for the AWS Load Balancer Controller

I also included an S3 backend configuration (commented out for now). In production I would enable this — it stores the Terraform state file in S3 instead of locally, which means the state is safe if my laptop dies, and a DynamoDB table provides state locking so two people can't run `terraform apply` at the same time.

---

### variables.tf — Single Source of Truth for Configuration

Instead of hardcoding values like `"us-east-1"` or `"t3.medium"` directly in my resource files, I put every configurable value in `variables.tf`. This means I can change the region, instance type, or cluster name in one place and it propagates everywhere.

Key variables I defined:

| Variable             | Default                         | Purpose                                |
| -------------------- | ------------------------------- | -------------------------------------- |
| `aws_region`         | `us-east-1`                     | Where all resources are created        |
| `cluster_name`       | `tetris-eks`                    | Name used across all related resources |
| `cluster_version`    | `1.29`                          | Kubernetes version                     |
| `node_instance_type` | `t3.medium`                     | EC2 type for worker nodes              |
| `node_desired_size`  | `2`                             | Normal number of worker nodes          |
| `node_min_size`      | `1`                             | Minimum during scale-down              |
| `node_max_size`      | `4`                             | Maximum during scale-up                |
| `docker_image`       | `kailashbadu/tetris-app:latest` | Image deployed to the cluster          |

I chose `t3.medium` for worker nodes because it gives 2 vCPUs and 4GB RAM — enough to run 2 Tetris pods comfortably with headroom for system pods like CoreDNS and the VPC CNI.

---

### provider.tf — Configuring the AWS Provider

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "tetris-devsecops"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
```

The `default_tags` block is one of my favourite Terraform features. Every single AWS resource I create automatically gets these three tags without me having to add them individually. This means in the AWS console I can filter by `ManagedBy = terraform` to instantly see everything Terraform owns, and I can filter by `Project = tetris-devsecops` to see everything belonging to this project. It also makes cost allocation easy — I can see exactly what this project is costing me in the AWS billing dashboard.

---

### vpc.tf — Building the Network from Scratch

This is the most important file for the destroy guarantee. I deliberately did not use the default VPC that AWS creates automatically in every account. Instead I built a complete network from scratch — which means Terraform owns it entirely and can destroy it entirely.

#### Architecture

```
VPC  10.0.0.0/16
│
├── Public Subnet AZ-a   10.0.101.0/24  ← ALB, NAT Gateway
├── Public Subnet AZ-b   10.0.102.0/24  ← ALB, NAT Gateway
│         │
│    Internet Gateway (outbound to internet)
│
├── Private Subnet AZ-a  10.0.1.0/24   ← Worker Nodes
└── Private Subnet AZ-b  10.0.2.0/24   ← Worker Nodes
          │
     NAT Gateway (nodes can reach internet, internet can't reach nodes)
```

#### Why Two Availability Zones?

I spread the infrastructure across two AZs (`us-east-1a` and `us-east-1b`). If one AZ has an outage — which does happen — my worker nodes in the other AZ keep the app running. This is standard production practice.

#### Why Private Subnets for Worker Nodes?

My worker nodes sit in private subnets. They have no public IP addresses and no direct route from the internet to them. All inbound traffic comes through the ALB in the public subnet, which forwards to pods via the Kubernetes Service. This dramatically reduces the attack surface — an attacker on the internet cannot directly reach my EC2 instances.

#### NAT Gateway — Outbound Without Exposure

Worker nodes in private subnets still need outbound internet access — to pull Docker images from Docker Hub, to call AWS APIs, to download updates. The NAT Gateway sits in the public subnet and acts as an outbound proxy: nodes can reach the internet, but the internet cannot initiate connections to the nodes. I created one NAT Gateway per AZ so that if one AZ's NAT Gateway goes down, nodes in the other AZ still have outbound connectivity.

#### Subnet Tags for EKS

I tagged my subnets with specific Kubernetes tags:

```
"kubernetes.io/cluster/tetris-eks" = "shared"
"kubernetes.io/role/elb"           = "1"   # public subnets
"kubernetes.io/role/internal-elb"  = "1"   # private subnets
```

These tags are not optional — they are how the AWS Load Balancer Controller discovers which subnets to place load balancers in. Without them, the controller cannot create ALBs for my Ingress resources.

#### Resources Created in vpc.tf

| Resource                 | Count | Purpose                               |
| ------------------------ | ----- | ------------------------------------- |
| VPC                      | 1     | The network boundary                  |
| Internet Gateway         | 1     | Public internet access                |
| Public Subnets           | 2     | One per AZ — ALBs and NAT GWs         |
| Private Subnets          | 2     | One per AZ — worker nodes             |
| Elastic IPs              | 2     | Static IPs for NAT Gateways           |
| NAT Gateways             | 2     | Outbound internet for private subnets |
| Public Route Table       | 1     | Routes 0.0.0.0/0 → IGW                |
| Private Route Tables     | 2     | One per AZ, routes 0.0.0.0/0 → NAT GW |
| Route Table Associations | 4     | Links subnets to their route tables   |

---

### eks.tf — The Cluster, Node Group, and IAM

#### IAM Role: EKS Cluster Control Plane

EKS needs an IAM role to manage AWS resources on my behalf — creating load balancers, managing ENIs, describing EC2 instances. I created a dedicated role and attached only `AmazonEKSClusterPolicy` — the principle of least privilege. The role trusts only the `eks.amazonaws.com` service, meaning only EKS can assume it.

#### IAM Role: Worker Nodes

Worker nodes (EC2 instances) also need an IAM role. They need three policies:

- `AmazonEKSWorkerNodePolicy` — allows nodes to join the cluster
- `AmazonEKS_CNI_Policy` — allows the VPC CNI plugin to configure pod networking
- `AmazonEC2ContainerRegistryReadOnly` — allows nodes to pull images from ECR

I give read-only ECR access, not write — nodes should never be pushing images.

#### EKS Cluster

```hcl
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]
}
```

I enabled both private and public endpoint access. Private access means worker nodes communicate with the control plane over the VPC network (faster, no internet hop). Public access means I can run `kubectl` from my laptop without needing a VPN. In a strict production setup I would disable public access and use a bastion host or VPN.

I also enabled cluster logging for `api`, `audit`, and `authenticator`. These logs go to CloudWatch and are invaluable for debugging — if a pod can't pull an image, if a user gets denied, if something is misconfigured, the answer is usually in these logs.

#### EKS Managed Node Group

I used a managed node group rather than self-managed EC2 instances. AWS handles the AMI selection, security patches, and node draining during updates. I just declare the instance type and scaling config and AWS does the rest.

```hcl
lifecycle {
  ignore_changes = [scaling_config[0].desired_size]
}
```

This `lifecycle` block is important — it tells Terraform to ignore changes to `desired_size`. Without it, if the cluster autoscaler scales my nodes from 2 to 3, the next `terraform apply` would immediately scale back to 2, fighting the autoscaler. This block lets the autoscaler manage actual node count while Terraform manages everything else.

#### OIDC Provider — IAM Roles for Service Accounts

This is the piece that enables fine-grained IAM permissions for Kubernetes workloads. Instead of giving every pod on a node full access to whatever the node role allows, IRSA lets me assign a specific IAM role to a specific Kubernetes service account. The AWS Load Balancer Controller uses this — it gets only the permissions it needs to manage load balancers, nothing more.

The OIDC provider is created by reading the TLS certificate from the EKS cluster's OIDC issuer URL — that's why I need the `tls` provider.

#### IAM Role: AWS Load Balancer Controller

The AWS Load Balancer Controller is a Kubernetes controller that watches for Ingress resources and creates AWS Application Load Balancers automatically. It needs IAM permissions to create and manage ALBs, target groups, security groups, and listeners.

I download the official IAM policy from AWS (`aws-lbc-policy.json`) rather than writing it myself — it's maintained by the AWS team and updated as the controller's requirements change. The role uses IRSA so only the LBC service account in the `kube-system` namespace can assume it.

---

### outputs.tf — What to Use After Apply

```hcl
output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}
```

After `terraform apply` completes, Terraform prints these values. `configure_kubectl` is the exact command I run to point my local `kubectl` at the new cluster — no need to look anything up.

---

### Deploying

```bash
#  downloads providers, sets up backend
terraform init

#  see exactly what will be created before touching anything
terraform plan

#  create all 30 resources (takes ~15 minutes)
terraform apply

# Connect kubectl to the new cluster
aws eks update-kubeconfig --region us-east-1 --name tetris-eks

# Verify nodes are ready
kubectl get nodes
```

### Destroying — Complete Teardown

```bash
terraform destroy
```

Terraform destroys resources in the correct dependency order:

1. EKS Node Group → EC2 instances terminated
2. EKS Cluster → control plane deleted
3. IAM Roles and Policies → deleted
4. OIDC Provider → deleted
5. NAT Gateways → deleted
6. Elastic IPs → released
7. Subnets, Route Tables, IGW → deleted
8. VPC → deleted

Every AWS resource created by Terraform is destroyed. Zero charges after destroy.

---

### What I Achieved

- A production-grade EKS cluster running across two Availability Zones, fully provisioned from code
- Complete network isolation — worker nodes in private subnets, only reachable through the load balancer
- All IAM roles follow the principle of least privilege — each component gets only the permissions it needs
- The entire infrastructure is version controlled alongside the application code
- `terraform destroy` leaves the AWS account completely clean — no orphaned resources, no surprise charges
- The cluster is ready to receive Kubernetes manifests in the next step
