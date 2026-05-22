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
