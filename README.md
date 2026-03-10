# Pipekit Infra Take-home

This repository contains my solution for the Pipekit infrastructure take-home exercise.

## Prerequisites

The following tools must be installed:

- Docker
- k3d
- kubectl
- Terraform or OpenTofu
- git

## Clone the repository and run the infrastructure

```bash
git clone <your-repo-url>
cd <repo>/tofu
terraform init
terraform apply
```

If the API does not immediately show the data, restart the PostgREST deployment:

```bash
kubectl rollout restart deployment/postgrest -n postgrest
```

Open the API endpoint in your browser:

```
http://localhost:8080/todos
```

You should see the injected data.

## Expected result

![Expected result](./docs/postgrest-result.png)