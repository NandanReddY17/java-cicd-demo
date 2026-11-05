# End-to-End Cloud CI/CD Pipeline (CIA 2)

A **Simple Calculator** web app (Java 21 / Spring Boot) that is automatically built, tested,
containerised and deployed to **Azure Kubernetes Service (AKS)** on every `git push`. The browser
page collects input; the Java REST API does the calculation (add, subtract, multiply, divide,
modulo, power).

```
git push ──► GitHub Actions / Jenkins ──► Maven (compile, test, package) ──► Docker build
                                                                               │
   Browser ◄── Azure Load Balancer ◄── AKS pods ◄── Ansible deploy ◄── GitHub Container Registry
```

| Concern | Tool |
|---|---|
| Source control | Git + GitHub |
| CI/CD orchestration | GitHub Actions (`.github/workflows/ci-cd.yml`) and Jenkins (`Jenkinsfile`, `jenkins/`) |
| Build & unit tests | Maven + JUnit 5 / MockMvc |
| Containerisation | Docker (`Dockerfile`, `.dockerignore`) |
| Registry | GitHub Container Registry, `ghcr.io/nandanreddy17/java-cicd-demo` |
| Orchestration | Azure Kubernetes Service (free control-plane tier), created with the Azure CLI |
| Deployment automation | Ansible (`ansible/deploy.yml`) |
| Cloud | Microsoft Azure (free trial, spending limit on), region Central India |

## Repository layout

```
.github/workflows/ci-cd.yml   GitHub Actions pipeline: build-test -> docker -> deploy
Jenkinsfile                   Jenkins pipeline (same stages + container smoke test)
jenkins/                      Jenkins in Docker: Dockerfile, plugins.txt, casc.yaml, docker-compose.yml
src/main/java/.../            CalculatorService (maths), CalculatorController (REST API), HomeController (info)
src/main/resources/static/    index.html calculator page
src/test/java/.../            19 unit tests (JUnit 5 + MockMvc)
pom.xml                       Maven build
Dockerfile, .dockerignore     container image
k8s/deployment.yaml.j2        Deployment (image tag filled in by Ansible)
k8s/service.yaml              LoadBalancer Service (public endpoint)
ansible/deploy.yml            apply manifests, wait for rollout, verify endpoint
ansible/inventory.ini         localhost (runs on the CI runner)
infra/azure/setup-aks.sh      one-time Azure setup: resource group, AKS, CI service account + kubeconfig
infra/ci-rbac.yaml            least-privilege Kubernetes identity for the pipelines
infra/aws/                    attempts on AWS EKS and Lightsail (blocked by the AWS Free plan; kept for the record)
```

## Endpoints

| Path | Returns |
|---|---|
| `/` | calculator web page (`src/main/resources/static/index.html`) |
| `/api/calculate?a=8&b=2&op=divide` | `{"a":8.0,"b":2.0,"op":"divide","result":4.0}`; ops: add, subtract, multiply, divide, modulo, power; bad input → 400 `{"error": ...}` |
| `/api/info` | page title message, version, `build` (Git SHA of running image), `servedBy` (pod name) |
| `/actuator/health/readiness`, `/liveness` | Kubernetes probes |

## GitHub Actions pipeline

| Job | Steps | Purpose |
|---|---|---|
| **Build & Test** | Checkout → Compile → Run unit tests → Package JAR | fail fast; nothing broken gets an image |
| **Docker Build & Push** | Login to ghcr.io with the built-in `GITHUB_TOKEN` → tag with Git SHA + `latest` → push | immutable, traceable artifact |
| **Deploy to AKS & Verify** | kubeconfig from the `KUBECONFIG` secret → Ansible: render manifest, `kubectl apply`, `rollout status`, wait for the LB IP, HTTP check that `build` == new SHA | proves the new version is live |

Pull requests run only the first job. The deploy job runs when the repository variable
`CLOUD_DEPLOY` is `true`.

## Jenkins pipeline (`Jenkinsfile`)

The same pipeline is also implemented in Jenkins, running in Docker on the developer PC.

| Stage | What it does |
|---|---|
| Checkout | clone the commit, read the short Git SHA |
| Compile / Unit Tests / Package | `mvn compile`, `mvn test` (JUnit report published), `mvn package` (JAR archived) |
| Docker Build | `java-cicd-demo:<sha>` and `:latest` |
| Container Smoke Test | start the new image, call `/api/calculate` (6×7 = 42) and `/api/info` (build = SHA) |
| Push to GHCR | only when `CLOUD_DEPLOY=true` |
| Deploy to AKS (Ansible) | same `ansible/deploy.yml` as GitHub Actions |
| Verify Deployment | `kubectl get deployment/pods/service`, rollout history |

Jenkins itself is configured as code: `jenkins/Dockerfile` (Jenkins + Maven, Docker CLI, kubectl,
Ansible), `jenkins/plugins.txt`, and `jenkins/casc.yaml` (admin user, `CLOUD_DEPLOY` env var,
and the `java-cicd-demo` pipeline job created with Job DSL). GitHub cannot reach a Jenkins running on a
laptop, so the job **polls GitHub every minute** (`pollSCM`) instead of using a webhook.

```bash
cd jenkins
cp .env.example .env          # set JENKINS_ADMIN_PASSWORD
docker compose up -d --build  # http://localhost:8081  (user: admin)
```

To enable the cloud stages in Jenkins, add two credentials (Manage Jenkins → Credentials → global):
`ghcr-creds` (*Username with password*: GitHub username + a personal access token with `write:packages`)
and `kubeconfig` (*Secret file*: the CI kubeconfig). Then set `CLOUD_DEPLOY=true` in `jenkins/.env` and
run `docker compose up -d`. Enable cloud deploys in **either** Jenkins **or** GitHub Actions, not both,
so the two pipelines don't deploy the same commit twice.

## Run locally

```bash
mvn clean verify                 # build + tests
mvn spring-boot:run              # http://localhost:8080/
docker build -t java-cicd-demo . && docker run --rm -p 8080:8080 java-cicd-demo
```

## One-time cloud setup

Prerequisites: an Azure subscription (free trial works: 4 vCPU quota, spending limit on), and on your
PC: Azure CLI, `kubectl`, Git Bash.

1. `az login` (opens the browser).
2. From the repo root in Git Bash: `bash infra/azure/setup-aks.sh`. It creates the resource group and AKS
   cluster (1 × Standard_B2s_v2 node, free control-plane tier, ~5–10 min), a least-privilege service
   account `ci-deployer`, and writes its kubeconfig to `~/java-cicd-ci.kubeconfig` (outside the repo).
3. GitHub repo → Settings → Secrets and variables → Actions:
   secret `KUBECONFIG` = contents of that file; variable `CLOUD_DEPLOY` = `true`.
4. The GHCR image inherits the public repo's visibility, so AKS pulls it without a password. (If your
   package is private, make it public under Packages → `java-cicd-demo` → Package settings.)
5. Re-run the pipeline. Get the URL with `kubectl get svc java-cicd-demo` (EXTERNAL-IP), or from the
   last Ansible step in the log.

## Demonstrating a change

1. Edit the `message` (page title) in `src/main/java/com/example/cicddemo/HomeController.java` **and** the expected text in `HomeControllerTest.java`.
2. `git commit -am "Change title" && git push`
3. Watch the pipeline run automatically. A new image tag (the new short SHA) appears in GHCR.
4. `kubectl rollout history deployment/java-cicd-demo` shows a new revision.
5. Refresh the URL: the new title appears, and the footer's `build` equals the new commit SHA.

## Clean up (avoid using credit)

```bash
az group delete --name java-cicd-rg --yes --no-wait   # deletes AKS, its VM, disk and load balancer
```

## Security notes

- No secrets in Git: the CI kubeconfig lives in GitHub encrypted secrets / Jenkins credentials;
  `.gitignore` excludes kubeconfig files and `.env`.
- The pipelines use a Kubernetes service account that can only manage Deployments and Services in the
  `default` namespace (it cannot read Secrets or touch other namespaces). No Azure admin credentials
  are given to CI.
- GitHub Actions pushes images with the short-lived built-in `GITHUB_TOKEN`; no registry password is stored.
- Images are tagged with the Git commit SHA (immutable, traceable, easy rollback).
- Containers run as non-root (uid 10001), read-only root filesystem, all Linux capabilities dropped,
  CPU/memory limits set.
