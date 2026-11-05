#!/usr/bin/env bash
# One-time Azure setup for the CI/CD pipeline. Run from the repo root in Git Bash after `az login`.
#
# Creates: resource group, AKS cluster (free control-plane tier, 1 small node),
# a least-privilege Kubernetes service account for the pipelines, and a kubeconfig
# for it OUTSIDE the repo (~/java-cicd-ci.kubeconfig) to paste into GitHub/Jenkins.
#
# Override defaults like:  LOCATION=southeastasia NODE_SIZE=Standard_B2s_v2 bash infra/azure/setup-aks.sh
set -euo pipefail

RG="${RG:-java-cicd-rg}"
CLUSTER="${CLUSTER:-java-cicd-aks}"
LOCATION="${LOCATION:-centralindia}"
NODE_SIZE="${NODE_SIZE:-Standard_B2s}"
NODE_COUNT="${NODE_COUNT:-1}"
CI_KUBECONFIG="${CI_KUBECONFIG:-$HOME/java-cicd-ci.kubeconfig}"

echo "Subscription: $(az account show --query name -o tsv)"
echo "Location: $LOCATION   Node size: $NODE_SIZE x $NODE_COUNT"

echo "== 1. Register the Kubernetes resource provider (first time only)"
az provider register --namespace Microsoft.ContainerService --wait

echo "== 2. Resource group"
az group create --name "$RG" --location "$LOCATION" --tags project=cia2-cicd -o none

echo "== 3. AKS cluster (about 5-10 minutes)"
if ! az aks show -g "$RG" -n "$CLUSTER" -o none 2>/dev/null; then
  az aks create -g "$RG" -n "$CLUSTER" \
    --location "$LOCATION" \
    --tier free \
    --node-count "$NODE_COUNT" \
    --node-vm-size "$NODE_SIZE" \
    --node-osdisk-size 30 \
    --generate-ssh-keys \
    --tags project=cia2-cicd \
    -o none
fi

echo "== 4. Admin access for this PC (kubectl)"
az aks get-credentials -g "$RG" -n "$CLUSTER" --overwrite-existing
kubectl get nodes -o wide

echo "== 5. Least-privilege service account for the pipelines"
kubectl apply -f infra/azure/ci-rbac.yaml
for i in $(seq 1 30); do
  TOKEN=$(kubectl get secret ci-deployer-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
  [ -n "$TOKEN" ] && break
  sleep 2
done
[ -n "$TOKEN" ] || { echo "Service account token was not created"; exit 1; }

SERVER=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

umask 077
cat > "$CI_KUBECONFIG" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: $CLUSTER
  cluster:
    server: $SERVER
    certificate-authority-data: $CA
users:
- name: ci-deployer
  user:
    token: $TOKEN
contexts:
- name: ci-deployer@$CLUSTER
  context:
    cluster: $CLUSTER
    user: ci-deployer
    namespace: default
current-context: ci-deployer@$CLUSTER
EOF

echo "== 6. Check the CI identity: allowed to manage deployments, NOT allowed to read secrets"
KCI="$CI_KUBECONFIG"
command -v cygpath >/dev/null && KCI=$(cygpath -w "$CI_KUBECONFIG")
kubectl --kubeconfig "$KCI" auth can-i create deployments
kubectl --kubeconfig "$KCI" auth can-i get secrets || true

echo
echo "Done. CI kubeconfig written to: $CI_KUBECONFIG"
echo "Add its contents as the GitHub secret KUBECONFIG and as the Jenkins Secret file 'kubeconfig'."
echo "Never commit this file."
