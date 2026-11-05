# Live Demo Checklist

Before the viva: open these tabs — GitHub repo, GitHub Actions, ECR repo, EKS cluster, app URL — and a Git Bash terminal.

- [ ] GitHub repo: walk through `ci-cd.yml`, `Dockerfile`, `k8s/`, `ansible/deploy.yml`.
- [ ] Actions: show the last green run with its 3 jobs.
- [ ] ECR: show image tags (Git SHAs + `latest`) and the scan result.
- [ ] EKS console: cluster Active, node group with 2 nodes.
- [ ] Terminal: `kubectl get nodes`, `kubectl get deploy,pods,svc -l app=java-cicd-demo`.
- [ ] Browser: open the load balancer URL, do a calculation (e.g. 12 × 4, then ÷ 0 to show the error), point out `build` and `servedBy` in the footer.
- [ ] Change the `message` (page title) in `HomeController.java` and the test, then `git commit -am "..." && git push`.
- [ ] Show the pipeline starting by itself.
- [ ] While it runs: `kubectl get pods -w` to show the rolling update (new pods start, old ones terminate).
- [ ] Show the new SHA tag in ECR and `kubectl rollout history deployment/java-cicd-demo`.
- [ ] Refresh the browser: new title, footer `build` = new SHA.
- [ ] Explain where credentials are stored (GitHub secrets) and why nothing secret is in Git.
