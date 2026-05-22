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
| Single container                   | no           | yes               |
| Multi container                    | no           | yes              |
| Reproducible setup                 | no           | yes               |
| One command for everything         | no           | yes               |
| Easy to read and share             | no           | yes              |
| Used in CI/CD pipelines            | no           | yes               |
| Auto networking between containers | no Manual    | yes Automatic     |


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

| Trigger | When it fires | What it does |
|---|---|---|
| `push to main` | Every time I push code to main | Build, test, push `latest` image |
| `tag v*` | Every time I create a version tag like `v1.0.0` | Build, test, push versioned image |
| `pull_request` | Every time I open a PR to main | Build and test only — no push |

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

