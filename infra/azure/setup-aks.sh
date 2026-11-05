#!/usr/bin/env bash
# One-time Azure setup for the CI/CD pipeline. Run from the repo root in Git Bash after `az login`.
#
# Creates: resource group, AKS cluster (free control-plane tier, 1 small node),
# a least-privilege Kubernetes service account for the pipelines, and a kubeconfig
# for it OUTSIDE the repo (~/java-cicd-ci.kubeconfig) to paste into GitHub/Jenkins.
#
# Override defaults like:  LOCATION=southindia NODE_SIZE=Standard_B2as_v2 bash infra/azure/setup-aks.sh
set -euo pipefail

RG="${RG:-java-cicd-rg}"
CLUSTER="${CLUSTER:-java-cicd-aks}"
LOCATION="${LOCATION:-centralindia}"
NODE_SIZE="${NODE_SIZE:-Standard_B2s_v2}"   # 2 vCPU, 8 GB; fits the 4-vCPU free-trial quota
NODE_COUNT="${NODE_COUNT:-1}"
CI_KUBECONFIG="${CI_KUBECONFIG:-$HOME/java-cicd-ci.kubeconfig}"
ADMIN_KUBECONFIG="${ADMIN_KUBECONFIG:-$HOME/.kube/aks-java-cicd.yaml}"

# Retry a command a few times: the network this was built on resets connections intermittently.
retry() {
  local n=0
  until "$@"; do
    n=$((n + 1)); [ "$n" -ge 6 ] && return 1
    echo "  (attempt $n failed, retrying in 10s)"; sleep 10
  done
}

echo "Subscription: $(retry az account show --query name -o tsv)"
echo "Location: $LOCATION   Node size: $NODE_SIZE x $NODE_COUNT"

echo "== 1. Register the Kubernetes resource provider (first time only)"
if [ "$(retry az provider show -n Microsoft.ContainerService --query registrationState -o tsv)" != "Registered" ]; then
  retry az provider register --namespace Microsoft.ContainerService --wait
fi

echo "== 2. Resource group"
retry az group create --name "$RG" --location "$LOCATION" --tags project=cia2-cicd -o none

echo "== 3. AKS cluster (about 5-10 minutes)"
state() { az aks show -g "$RG" -n "$CLUSTER" --query provisioningState -o tsv 2>/dev/null || true; }
if [ -z "$(state)" ]; then
  retry az aks create -g "$RG" -n "$CLUSTER" \
    --location "$LOCATION" \
    --tier free \
    --node-count "$NODE_COUNT" \
    --node-vm-size "$NODE_SIZE" \
    --node-osdisk-size 30 \
    --generate-ssh-keys \
    --tags project=cia2-cicd \
    --no-wait -o none || true
fi
for i in $(seq 1 90); do
  S=$(state)
  echo "  cluster state: ${S:-starting}"
  [ "$S" = "Succeeded" ] && break
  [ "$S" = "Failed" ] && { echo "Cluster creation failed"; exit 1; }
  sleep 20
done

echo "== 4. Admin access for this PC (kubectl), in its own file: $ADMIN_KUBECONFIG"
mkdir -p "$(dirname "$ADMIN_KUBECONFIG")"
ADMIN_WIN="$ADMIN_KUBECONFIG"
command -v cygpath >/dev/null && ADMIN_WIN=$(cygpath -w "$ADMIN_KUBECONFIG")
retry az aks get-credentials -g "$RG" -n "$CLUSTER" --file "$ADMIN_WIN" --overwrite-existing
export KUBECONFIG="$ADMIN_WIN"
retry kubectl get nodes -o wide

echo "== 5. Least-privilege service account for the pipelines"
retry kubectl apply -f infra/ci-rbac.yaml
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
