#  k8s-data-platform 

A fully local, zero-cost, end-to-end data platform running on **Kubernetes**, **Terraform**, and **LocalStack**.

This project demonstrates how to reproduce a production-oriented AWS data platform locally using **Kubernetes (kind)**, **Terraform**, **IAM least-privilege policies**, and **IRSA-style authentication**, without requiring an AWS account or incurring cloud infrastructure costs.

The platform runs entirely on your local machine and provides an S3-compatible data lake through LocalStack.

---

##  Overview

The goal of this project is to demonstrate how cloud-native data infrastructure can be designed, provisioned, and tested locally while following production-oriented practices.

The platform includes:

* A **FastAPI** application running inside Kubernetes.
* A local **S3-compatible data lake** provided by LocalStack.
* Infrastructure managed declaratively with **Terraform**.
* Kubernetes resources managed through Terraform.
* IAM policies following the **least-privilege principle**.
* Kubernetes **RBAC** with dedicated service accounts and roles.
* Health checks and resource constraints.
* Automated Terraform validation through **GitHub Actions**.
* A clear migration path from local Kubernetes to **AWS EKS**.

---

##  Architecture

```text
                              ┌──────────────────────────────────────────────┐
                              │              Kubernetes Cluster              │
                              │                    kind                      │
                              │                                              │
                              │   ┌──────────────────────────────────────┐   │
                              │   │              data namespace           │   │
                              │   │                                      │   │
┌──────────────┐              │   │   ┌──────────────────────────────┐   │   │
│              │              │   │   │        Python API            │   │   │
│ User / Client├──────────────┼───┼──►│          FastAPI             │   │   │
│              │              │   │   │        2 replicas            │   │   │
└──────────────┘              │   │   └──────────────┬───────────────┘   │   │
                              │   │                  │                   │   │
                              │   │                  ▼                   │   │
                              │   │   ┌──────────────────────────────┐   │   │
                              │   │   │       IAM / IRSA Role       │   │   │
                              │   │   │      Least Privilege        │   │   │
                              │   │   └──────────────────────────────┘   │   │
                              │   │                  │                   │   │
                              │   └──────────────────┼───────────────────┘   │
                              │                      │                       │
                              │                      ▼                       │
                              │          ┌──────────────────────┐           │
                              │          │     LocalStack        │           │
                              │          │                      │           │
                              │          │   S3 / IAM / STS     │           │
                              │          │                      │           │
                              │          │   data-lake-dev      │           │
                              │          └──────────────────────┘           │
                              │                                              │
                              └──────────────────────────────────────────────┘
                                           ▲
                                           │
                              ┌────────────┴────────────┐
                              │        Terraform         │
                              │           IaC            │
                              │                          │
                              │  infra/cluster           │
                              │  infra/aws               │
                              └─────────────────────────┘
```

---

##  Components

### Kubernetes

The application runs on a local **kind** Kubernetes cluster inside the `data` namespace.

The deployment follows several security and reliability best practices:

* Runs as a **non-root user** (`UID 10001`).
* Defines CPU and memory requests.
* Defines CPU and memory limits.
* Uses an HTTP readiness probe through `/health`.
* Runs multiple API replicas.
* Uses a dedicated Kubernetes `ServiceAccount`.
* Uses Kubernetes `Role` and `RoleBinding` resources.
* Keeps application resources isolated inside a dedicated namespace.

### FastAPI

The application provides the API layer of the platform.

Its responsibility is to receive data and interact with the S3-compatible data lake through the configured endpoint.

The application is designed to be cloud-agnostic and uses environment-based configuration, including:

```text
S3_ENDPOINT
```

This allows the same application to communicate with LocalStack locally and AWS S3 in a real environment.

### LocalStack

[LocalStack](https://www.localstack.cloud/) provides a local AWS-compatible environment.

The project uses it to emulate:

* **S3**
* **IAM**
* **STS**

The S3 bucket used by the platform is:

```text
data-lake-dev
```

This makes it possible to develop and test the platform without creating real AWS resources.

### Terraform

Terraform manages both the Kubernetes and AWS-compatible infrastructure.

The configuration is intentionally separated into two independent roots:

```text
infra/
├── cluster/
└── aws/
```

#### `infra/cluster`

Responsible for Kubernetes infrastructure, including:

* Namespace
* Secrets
* Deployments
* Service accounts
* RBAC resources
* Application configuration

#### `infra/aws`

Responsible for AWS-compatible infrastructure, including:

* S3 bucket
* Bucket versioning
* IAM policies
* IAM roles
* LocalStack AWS resources

This separation keeps infrastructure concerns isolated and makes the project easier to migrate to real AWS infrastructure.

---

## Security Model

Security is one of the main goals of this project.

### Container security

The API container does not run as root.

```text
UID: 10001
```

This reduces the impact of a potential container compromise.

### Kubernetes RBAC

The application uses a dedicated `ServiceAccount` instead of relying on the default account.

Access is controlled through:

```text
ServiceAccount
      │
      ▼
    Role
      │
      ▼
 RoleBinding
```

This follows the principle of granting workloads only the Kubernetes permissions they actually need.

### IAM Least Privilege

The AWS-compatible permissions are intentionally scoped rather than granting broad administrative access.

The objective is to demonstrate the same security principles expected in a production AWS environment:

> Grant the minimum permissions required for the workload to perform its job.

---

##  Project Structure

A simplified project structure looks like this:

```text
k8s-data-platform/
│
├── app/
│   └── ...
│
├── infra/
│   ├── aws/
│   │   └── ...
│   │
│   └── cluster/
│       └── ...
│
├── .github/
│   └── workflows/
│       └── ...
│
├── Dockerfile
├── Makefile
├── LICENSE
└── README.md
```

> The exact application files may vary depending on the repository version.

---

##  Prerequisites

Before starting, make sure the following tools are installed:

| Tool                                                   | Purpose                  |
| ------------------------------------------------------ | ------------------------ |
| [Docker](https://www.docker.com/)                      | Container runtime        |
| [kind](https://kind.sigs.k8s.io/)                      | Local Kubernetes cluster |
| [kubectl](https://kubernetes.io/docs/tasks/tools/)     | Kubernetes CLI           |
| [Terraform](https://developer.hashicorp.com/terraform) | Infrastructure as Code   |
| [LocalStack](https://www.localstack.cloud/)            | Local AWS emulation      |
| `make`                                                 | Project automation       |

Terraform **1.5+** is recommended.

You will also need a **LocalStack authentication token** for the configured LocalStack setup.

---

##  Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/tu-usuario/k8s-data-platform.git
cd k8s-data-platform
```

Replace the repository URL with the actual GitHub repository URL.

---

### 2. Configure the LocalStack token

Export your LocalStack authentication token:

```bash
export TF_VAR_localstack_auth_token="your_localstack_auth_token"
```

Make sure the variable is available in the same shell session where you execute the project commands.

---

### 3. Start the platform

Run:

```bash
make up
```

The `make up` workflow is responsible for preparing the local environment, including:

1. Checking required dependencies.
2. Building the application Docker image.
3. Creating the local `kind` Kubernetes cluster.
4. Applying the Terraform infrastructure.
5. Deploying the application.
6. Rolling out the Kubernetes workloads.

After the command completes, the local platform should be running inside the Kubernetes cluster.

---

### 4. Run the integration tests

Execute:

```bash
make test
```

The integration test sends a sample payload to the API and verifies that the application can write and retrieve an object from the local S3-compatible data lake.

This provides an end-to-end validation of:

```text
Client
  │
  ▼
FastAPI
  │
  ▼
IAM / Permissions
  │
  ▼
LocalStack S3
  │
  ▼
Object verification
```

---

### 5. Tear down the environment

When finished, remove the local infrastructure with:

```bash
make down
```

This removes the resources created for the local environment.

---

##  Useful Kubernetes Commands

Once the cluster is running, you can inspect the workloads with:

### List namespaces

```bash
kubectl get namespaces
```

### Inspect the `data` namespace

```bash
kubectl get all -n data
```

### Check pods

```bash
kubectl get pods -n data
```

### Check deployment

```bash
kubectl get deployments -n data
```

### Inspect the service account

```bash
kubectl get serviceaccount -n data
```

### Inspect RBAC

```bash
kubectl get role,rolebinding -n data
```

### View application logs

```bash
kubectl logs -n data deployment/<deployment-name>
```

Replace `<deployment-name>` with the actual deployment name in the repository.

---

##  CI/CD

The repository includes a GitHub Actions workflow that validates the Terraform configuration.

The CI pipeline performs checks such as:

```bash
terraform fmt
terraform validate
```

This helps catch infrastructure configuration problems before changes are merged.

The workflow is intentionally lightweight because the platform is designed to run locally and does not require a cloud account for the validation stage.

---

##  Migration to AWS EKS

One of the main design goals is keeping the application independent from the underlying infrastructure.

The local environment uses:

```text
kind + LocalStack
```

while the production architecture can use:

```text
EKS + AWS S3 + AWS IAM + AWS STS
```

### Migration steps

A production migration would involve:

1. Replace the local `kind` cluster with an **AWS EKS** cluster managed by Terraform.
2. Configure the EKS **OIDC provider**.
3. Create the appropriate AWS IAM role.
4. Configure the IAM trust policy using the real EKS OIDC provider.
5. Annotate the Kubernetes `ServiceAccount` with:

```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
```

6. Point the application directly to AWS S3.
7. Remove LocalStack-specific configuration.
8. Remove the AWS provider `skip_*` configuration used for local emulation.

The target architecture becomes:

```text
                    AWS
┌─────────────────────────────────────────────┐
│                                             │
│                  EKS                        │
│                                             │
│   ┌─────────────────────────────────────┐   │
│   │             FastAPI                 │   │
│   │                                     │   │
│   │        Kubernetes ServiceAccount    │   │
│   └──────────────────┬──────────────────┘   │
│                      │                      │
│                      ▼                      │
│               IAM Role / IRSA              │
│                      │                      │
│                      ▼                      │
│                 AWS S3                     │
│                                             │
└─────────────────────────────────────────────┘
```

The important part is that **the application itself does not need to be rewritten** for this migration. Infrastructure-specific behavior is isolated through configuration and Terraform.

---

##  Why "$0 Edition"?

This project intentionally avoids real cloud infrastructure during development.

Instead of:

```text
AWS EKS
AWS S3
AWS IAM
AWS STS
```

the local environment uses:

```text
kind
LocalStack
Terraform
Docker
```

This provides a realistic development and learning environment without AWS infrastructure charges.

> **Note:** `$0 Edition` refers to the infrastructure cost of the local environment. Docker, LocalStack, and other third-party tools may have their own licensing or usage considerations.

---

##  What This Project Demonstrates

This project is designed as a practical demonstration of several cloud-native and DevOps concepts:

* Kubernetes application deployment
* Infrastructure as Code with Terraform
* Local AWS emulation
* S3-compatible data lakes
* IAM least-privilege design
* Kubernetes RBAC
* Service accounts
* IRSA-oriented authentication
* Container security
* Kubernetes health probes
* Resource requests and limits
* Multi-replica deployments
* Infrastructure separation
* CI/CD validation
* Local integration testing
* Migration from local infrastructure to AWS EKS

---

##  Development Flow

The intended development workflow is:

```text
        Developer
            │
            ▼
       Source Code
            │
            ▼
       Docker Image
            │
            ▼
       kind Cluster
            │
            ▼
        Terraform
       ┌────┴────┐
       │         │
       ▼         ▼
 Kubernetes   LocalStack
       │         │
       └────┬────┘
            │
            ▼
     Integration Tests
```

This allows infrastructure and application changes to be tested locally before being considered for a real cloud deployment.

---

##  Cleanup

To remove the local platform:

```bash
make down
```

If you want to verify that the kind cluster has been removed:

```bash
kind get clusters
```

---

##  Contributing

Contributions are welcome.

A typical contribution workflow is:

```bash
git checkout -b feature/my-change
```

Make your changes, validate the project locally, and then create a pull request.

Before opening a PR, make sure the Terraform configuration passes formatting and validation checks:

```bash
terraform fmt
terraform validate
```

---

##  License

This project is distributed under the **MIT License**.

See [`LICENSE`](LICENSE) for the complete license text.

---

##  Project Goal

The goal of **k8s-data-platform — $0 Edition** is not simply to run an API locally.

It is to demonstrate how a production-oriented cloud architecture can be designed, automated, secured, tested, and eventually migrated to AWS — **starting entirely from a local development environment**.

```text
Local Development
       │
       ▼
kind + LocalStack
       │
       ▼
Terraform + Kubernetes
       │
       ▼
Security + Testing
       │
       ▼
AWS EKS + S3
```

**Build locally. Test locally. Deploy to the cloud when you're ready.** 
