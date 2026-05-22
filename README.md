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

# Devosifying the tetric application

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


## How its fits in DevSecOps pipeline

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


