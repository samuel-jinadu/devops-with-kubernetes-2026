# Devops With Kubernetes 2026

## Exercises
- [Exercise 1.1](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.1)
- [Exercise 1.2](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.2)
- [Exercise 1.3](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.3)
- [Exercise 1.4](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.4)
- [Exercise 1.5](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.5)
- [Exercise 1.6](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.6)
- [Exercise 1.7](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.7)
- [Exercise 1.8](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.8)
- [Exercise 1.9](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.9)
- [Exercise 1.10](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.10)
- [Exercise 1.11](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.11)
- [Exercise 1.12](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.12)
- [Exercise 1.13](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.13)
- [Exercise 2.1](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/2.1)
- [Exercise 2.2](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/2.2)
- [Exercise 2.3](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/2.3)
- [Exercise 2.4](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/2.4)
- [Exercise 2.5](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/2.5)
- [Exercise 2.6](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/2.6)
- [Exercise 2.7](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/2.7)
- [Exercise 2.8](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/2.8)
- [Exercise 2.9](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/2.9)
- [Exercise 2.10](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/2.10)
- [Exercise 3.1](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.1)
- [Exercise 3.2](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.2)
- [Exercise 3.3](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.3)
- [Exercise 3.4](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.4)
- [Exercise 3.5](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.5)
- [Exercise 3.6](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.6)
- [Exercise 3.7](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.7)
- [Exercise 3.8](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.8)
- [Exercise 3.9](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.9)
- [Exercise 3.10](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.10)
- [Exercise 3.11](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.11)
- [Exercise 3.12](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/3.12)
- [Exercise 4.1](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/4.1)
- [Exercise 4.2](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/4.2)
- [Exercise 4.3](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/4.3)
- [Exercise 4.4](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/4.4)
- [Exercise 4.5](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/4.5)
- [Exercise 4.6](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/4.6)
- [Exercise 4.7](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/4.7)
- [Exercise 4.8](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/4.8)
- [Exercise 4.9](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/4.9)
- [Exercise 4.10](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/4.10)
- [Exercise 5.1](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/5.1)
- [Exercise 5.2](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/5.2)
- [Exercise 5.3](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/5.3)
- [Exercise 5.4](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/5.4)
- [Exercise 5.6](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/5.6)
- [Exercise 5.7](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/5.7)

## Notes

### Deployments
- `./deploy-gke.sh` — defaults to **staging** deploy (matches main-branch CI behaviour)
- `TARGET_NS=production TARGET_TAG=v1.0.0 ./deploy-gke.sh` — deploy **production** at a specific tag
- `TARGET_NS=my-branch TARGET_TAG=my-branch ./deploy-gke.sh` — ephemeral feature-branch deploy

### How environments are wired
- **staging** namespace (tracked by Argo CD from `main`): 
  - No backup CronJob
  - Broadcaster logs todos, does NOT forward to webhook
  - No public HTTPRoutes; use `kubectl -n staging port-forward svc/todo-app-service-cluster-ip 8080:2345`
- **production** namespace (tracked by Argo CD from the latest tag): 
  - Backup CronJob active (needs `storage-sa-key` secret + `backup-config` ConfigMap)
  - Broadcaster forwards to webhook (`broadcaster-webhook` secret)
  - Public routes on `exercises-gateway` → `/`, `/submit`, `/backend`

### Push → environment mapping
| Push | Namespace | Argo App | Deployed via |
|---|---|---|---|
| commit to `main` | `staging` | `project-staging` (targetRevision: main) | Argo CD |
| `git tag v1.2.3 && git push origin v1.2.3` | `production` | `project-production` (targetRevision: v1.2.3) | Argo CD |
| feature branch push | `<branch>` | — | direct kubectl (ephemeral) |

### Secrets (applied by deploy-gke.sh, not Argo CD)
- staging: `postgres-credentials`
- production: `postgres-credentials`, `broadcaster-webhook`, `storage-sa-key` + `backup-config` ConfigMap

# Logs Screenshot
![Logs Screenshot](logs-screenshot.png)

*Couldnt get access to the true GCP, so had to improvise: Log Screenshot*

## Pros and Cons of DBaaS vs DIY

### DIY Postgres (self-hosted on GKE with PVCs)

**Pros**
- **Costs to initialize**: No additional service fees beyond the GKE cluster you already pay for; you only pay for the PersistentVolume storage (and compute you already provision). 

**Cons**
- **Work to initialize**: You must write and maintain the Deployment/StatefulSet, PVC, Service, Secret for credentials, and a backup CronJob.
- **Maintenance burden**: You are responsible for version upgrades, security patching, minor/major Postgres upgrades (which are nontrivial with PVCs), and monitoring disk usage. 

### DBaaS (Google Cloud SQL for Postgres)

**Pros**
- **Work to initialize**: Very little: No YAML for storage, no StatefulSet.
- **Maintenance**: Google handles patching, minor version upgrades, disk growth, and instance health. 

**Cons**
- **Costs** — You pay for the instance (vCPU/RAM), storage, and backups on top of the GKE cluster. 

## Sources
- .devcontainer code originally based on [lbrenman/k3d-codespace](https://github.com/lbrenman/k3d-codespace), adapted for the floci-gcp GKE emulator.