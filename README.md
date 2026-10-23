# Devops With Kubernetes 2026

## Exercises
- [Exercise 1.1](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.1)
- [Exercise 1.2](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.2)
- [Exercise 1.3](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.3)
- [Exercise 1.4](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.4)
- [Exercise 1.5](https://github.com/samuel-jinadu/devops-with-kubernetes-2026/tree/1.5)

## Notes
- Command to deploy: `kubectl apply -f manifests/deployment.yaml`
- Command to extract config for lens: `kubectl config view --minify --raw`
- Command to port-forward: `kubectl port-forward pod/my-pod TO_PORT:FROM_PORT` # Note: This command is blocking

## Sources
- .devcontainer code sourced from [lbrenman/k3d-codespace](https://github.com/lbrenman/k3d-codespace). Used to make a k3d codespace.