# Log Output

A simple Go app to log uuid to console with timestamps.

## Prerequisites
- Go `1.27.2`

## Running Locally
```go
git clone https://github.com/samuel-jinadu/devops-with-kubernetes-2026.git
cd devops-with-kubernetes-2026/log-output
go run . 

// Sample output
// 2026-10-22 20:10:01.85680331 +0000 UTC: 9e66cea2-1296-41b2-8e9c-b6faa825f11a
// 2026-10-22 20:10:06.861170927 +0000 UTC: 9e66cea2-1296-41b2-8e9c-b6faa825f11a
// Ctl-C to stop

```

## Running in a Kubernetes Environment
```bash
kubectl create deployment log-output-app --image=ghcr.io/samuel-jinadu/log-output:main
```