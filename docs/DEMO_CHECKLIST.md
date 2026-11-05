# Live Demo Checklist

Before the viva: open these tabs — GitHub repo, GitHub Actions, GitHub Packages, Azure portal (AKS), Jenkins (http://localhost:8081), app URL (http://4.224.118.106/) — and a terminal with `KUBECONFIG` set to `~/.kube/aks-java-cicd.yaml`.

- [ ] GitHub repo: walk through `ci-cd.yml`, `Dockerfile`, `k8s/`, `ansible/deploy.yml`.
- [ ] Actions: show the last green run (#7) with its 3 jobs.
- [ ] GitHub Packages: show the java-cicd-demo image tags (Git SHAs + `latest`).
- [ ] Azure portal: AKS cluster java-cicd-aks running, node pool with 1 node.
- [ ] Terminal: `kubectl get nodes`, `kubectl get deploy,pods,svc -l app=java-cicd-demo`.
- [ ] Browser: open the load balancer URL, do a calculation (e.g. 12 × 4, then ÷ 0 to show the error), point out `build` and `servedBy` in the footer.
- [ ] Change the `message` (page title) in `HomeController.java` and the test, then `git commit -am "..." && git push`.
- [ ] Show the pipeline starting by itself.
- [ ] While it runs: `kubectl get pods -w` to show the rolling update (new pods start, old ones terminate).
- [ ] Show the new SHA tag in GitHub Packages and `kubectl rollout history deployment/java-cicd-demo`.
- [ ] Refresh the browser: new title, footer `build` = new SHA.
- [ ] Explain where credentials are stored (GitHub secrets) and why nothing secret is in Git.
