# End-to-End Cloud CI/CD Pipeline on AWS (CIA 2)

A **Simple Calculator** web app (Java 21 / Spring Boot) that is automatically built, tested,
containerised and deployed to Amazon EKS on every `git push`. The browser page collects input;
the Java REST API does the calculation (add, subtract, multiply, divide, modulo, power).

```
git push ──► GitHub Actions ──► Maven (compile, test, package) ──► Docker build
                                                                     │
   Browser ◄── AWS Load Balancer ◄── EKS pods ◄── Ansible deploy ◄── Amazon ECR
```

| Concern | Tool |
|---|---|
| Source control | Git + GitHub |
| CI/CD orchestration | GitHub Actions (`.github/workflows/ci-cd.yml`) |
| Build & unit tests | Maven + JUnit 5 / MockMvc |
| Containerisation | Docker (`Dockerfile`, `.dockerignore`) |
| Registry | Amazon ECR (scan on push) |
| Orchestration | Amazon EKS (Kubernetes), created with `eksctl` |
| Deployment automation | Ansible (`ansible/deploy.yml`) |
| Cloud | AWS, region `ap-south-1` (Mumbai) |

## Repository layout

```
.github/workflows/ci-cd.yml   pipeline: build-test -> docker -> deploy
src/main/java/.../            CalculatorService (maths), CalculatorController (REST API), HomeController (info)
src/main/resources/static/    index.html calculator page
src/test/java/.../            19 unit tests (JUnit 5 + MockMvc)
pom.xml                       Maven build
Dockerfile, .dockerignore     container image
k8s/deployment.yaml.j2        Deployment (image tag filled in by Ansible)
k8s/service.yaml              LoadBalancer Service (public endpoint)
ansible/deploy.yml            apply manifests, wait for rollout, verify endpoint
ansible/inventory.ini         localhost (runs on the CI runner)
infra/eks-cluster.yaml        eksctl cluster definition
infra/setup-aws.sh            one-time AWS setup (ECR, EKS, CI IAM user)
infra/ci-iam-policy.json      least-privilege policy for the CI user
```

## Endpoints

| Path | Returns |
|---|---|
| `/` | calculator web page (`src/main/resources/static/index.html`) |
| `/api/calculate?a=8&b=2&op=divide` | `{"a":8.0,"b":2.0,"op":"divide","result":4.0}`; ops: add, subtract, multiply, divide, modulo, power; bad input → 400 `{"error": ...}` |
| `/api/info` | page title message, version, `build` (Git SHA of running image), `servedBy` (pod name) |
| `/actuator/health/readiness`, `/liveness` | Kubernetes probes |

## Pipeline stages

| Job | Steps | Purpose |
|---|---|---|
| **Build & Test** | Checkout → Compile → Run unit tests → Package JAR | fail fast; nothing broken gets an image |
| **Docker Build & Push** | Login to ECR → tag with Git SHA + `latest` → push | immutable, traceable artifact |
| **Deploy to EKS & Verify** | `update-kubeconfig` → Ansible: render manifest, `kubectl apply`, `rollout status`, wait for LB, HTTP check that `build` == new SHA | proves the new version is live |

Pull requests run only the first job.

## Run locally

```bash
mvn clean verify                 # build + tests
mvn spring-boot:run              # http://localhost:8080/
docker build -t java-cicd-demo . && docker run --rm -p 8080:8080 java-cicd-demo
```

## One-time setup

Prerequisites: AWS account, GitHub account, and on your PC: AWS CLI v2, `eksctl`, `kubectl`, Git Bash.

1. `aws configure` with your own admin IAM user's access key, region `ap-south-1`.
2. From the repo root in Git Bash: `bash infra/setup-aws.sh` (creates ECR repo, EKS cluster ~15–20 min,
   a least-privilege IAM user `github-actions-cicd`, and grants it deploy rights in the `default` namespace).
3. AWS console → IAM → Users → `github-actions-cicd` → Security credentials → Create access key.
4. GitHub repo → Settings → Secrets and variables → Actions → add `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
5. Push to `main`. The pipeline creates the Deployment and Service on the first run.
6. Get the URL: `kubectl get svc java-cicd-demo` (EXTERNAL-IP column), or read it from the last Ansible step in the Actions log.

## Demonstrating a change

1. Edit the `message` (page title) in `src/main/java/com/example/cicddemo/HomeController.java` **and** the expected text in `HomeControllerTest.java`.
2. `git commit -am "Change greeting" && git push`
3. Watch Actions run automatically. A new image tag (the new short SHA) appears in ECR.
4. `kubectl rollout history deployment/java-cicd-demo` shows a new revision.
5. Refresh the URL: the new title appears, and the footer's `build` equals the new commit SHA.

## Clean up (avoid charges)

```bash
kubectl delete -f k8s/service.yaml        # removes the load balancer first
eksctl delete cluster -f infra/eks-cluster.yaml
aws ecr delete-repository --repository-name java-cicd-demo --force --region ap-south-1
```

## Security notes

- No secrets in Git: AWS keys live in GitHub encrypted secrets; `.gitignore` excludes kubeconfig and `.env`.
- The CI IAM user can only push to one ECR repo and describe one cluster; inside Kubernetes it has
  `AmazonEKSEditPolicy` scoped to the `default` namespace only.
- Images are tagged with the Git commit SHA (immutable, traceable, easy rollback); ECR scans each push.
- Containers run as non-root (uid 10001), read-only root filesystem, all Linux capabilities dropped,
  CPU/memory limits set.
