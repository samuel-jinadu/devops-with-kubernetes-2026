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

## Notes
- Deploy: `kubectl apply -f manifests/deployment.yaml`
- Extract config for lens: `kubectl config view --minify --raw`
- Port-forward: `kubectl port-forward pod/my-pod TO_PORT:FROM_PORT` # Note: This command is blocking
- Create default cluster with published ports: `k3d cluster create --port 8082:30080@agent:0 -p 8081:80@loadbalancer --agents 2`
- Create default cluster without ports when not using nodeports: `k3d cluster create -p 8081:80@loadbalancer --agents 2`
- Sabotaging pods: `kubectl delete pod -l app=todo-app`

## Sources
- .devcontainer code sourced from [lbrenman/k3d-codespace](https://github.com/lbrenman/k3d-codespace). Used to make a k3d codespace.