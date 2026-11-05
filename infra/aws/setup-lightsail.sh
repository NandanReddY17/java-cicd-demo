#!/usr/bin/env bash
# One-time AWS setup: a Kubernetes (k3s) cluster on an Amazon Lightsail server.
# Run from the repo root in Git Bash after `aws configure`.
#
# Why Lightsail + k3s: this AWS Free-plan account blocks EKS and EC2, but allows Lightsail
# in us-east-1. k3s is a lightweight, CNCF-certified Kubernetes distribution.
#
# Creates: SSH key pair, Lightsail instance, static IP, firewall rule for the Kubernetes API,
# k3s, a least-privilege service account for the pipelines, and two kubeconfigs OUTSIDE the repo:
#   ~/.kube/lightsail-k3s.yaml      admin access for this PC
#   ~/java-cicd-ci.kubeconfig       CI access (paste into GitHub secret / Jenkins credential)
set -euo pipefail

REGION="${REGION:-us-east-1}"
ZONE="${ZONE:-us-east-1a}"
NAME="${NAME:-java-cicd-k3s}"
BUNDLE="${BUNDLE:-small_3_0}"            # 2 GB RAM, 2 vCPU, 60 GB SSD
BLUEPRINT="${BLUEPRINT:-ubuntu_24_04}"
KEY_NAME="${KEY_NAME:-java-cicd-key}"
KEY_FILE="$HOME/.ssh/lightsail-java-cicd.pem"
ADMIN_KUBECONFIG="$HOME/.kube/lightsail-k3s.yaml"
CI_KUBECONFIG="$HOME/java-cicd-ci.kubeconfig"
LS="aws lightsail --region $REGION"

winpath() { command -v cygpath >/dev/null && cygpath -w "$1" || echo "$1"; }

echo "== 1. SSH key pair"
mkdir -p "$HOME/.ssh" "$HOME/.kube"
if [ ! -f "$KEY_FILE" ]; then
  $LS delete-key-pair --key-pair-name "$KEY_NAME" >/dev/null 2>&1 || true
  umask 077
  $LS create-key-pair --key-pair-name "$KEY_NAME" --query privateKeyBase64 --output text > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
fi

echo "== 2. Lightsail instance ($BUNDLE, $BLUEPRINT)"
if ! $LS get-instance --instance-name "$NAME" >/dev/null 2>&1; then
  $LS create-instances --instance-names "$NAME" --availability-zone "$ZONE" \
    --blueprint-id "$BLUEPRINT" --bundle-id "$BUNDLE" --key-pair-name "$KEY_NAME" \
    --tags key=project,value=cia2-cicd >/dev/null
fi
for i in $(seq 1 60); do
  STATE=$($LS get-instance --instance-name "$NAME" --query instance.state.name --output text)
  [ "$STATE" = "running" ] && break
  sleep 5
done
echo "Instance state: $STATE"

echo "== 3. Static IP (stays the same across reboots)"
$LS get-static-ip --static-ip-name "$NAME-ip" >/dev/null 2>&1 || $LS allocate-static-ip --static-ip-name "$NAME-ip" >/dev/null
$LS attach-static-ip --static-ip-name "$NAME-ip" --instance-name "$NAME" >/dev/null 2>&1 || true
IP=$($LS get-static-ip --static-ip-name "$NAME-ip" --query staticIp.ipAddress --output text)
echo "Public IP: $IP"

echo "== 4. Firewall: SSH 22, HTTP 80 (app), 6443 (Kubernetes API for the pipelines)"
$LS put-instance-public-ports --instance-name "$NAME" --port-infos \
  fromPort=22,toPort=22,protocol=TCP fromPort=80,toPort=80,protocol=TCP \
  fromPort=6443,toPort=6443,protocol=TCP >/dev/null

SSH="ssh -i $KEY_FILE -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ubuntu@$IP"
echo "== 5. Wait for SSH"
for i in $(seq 1 40); do $SSH true 2>/dev/null && break; sleep 5; done

echo "== 6. Install k3s (Traefik disabled; public IP added to the API certificate)"
$SSH "command -v k3s >/dev/null || curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC='server --disable traefik --tls-san $IP --node-external-ip $IP --write-kubeconfig-mode 600' sh -"
$SSH "for i in \$(seq 1 30); do sudo k3s kubectl get nodes 2>/dev/null | grep -q ' Ready' && break; sleep 5; done; sudo k3s kubectl get nodes -o wide"

echo "== 7. Admin kubeconfig for this PC"
umask 077
$SSH "sudo cat /etc/rancher/k3s/k3s.yaml" | sed "s#https://127.0.0.1:6443#https://$IP:6443#" > "$ADMIN_KUBECONFIG"
K="kubectl --kubeconfig $(winpath "$ADMIN_KUBECONFIG")"
$K get nodes -o wide

echo "== 8. Least-privilege service account for the pipelines"
$K apply -f infra/ci-rbac.yaml
for i in $(seq 1 30); do
  TOKEN=$($K get secret ci-deployer-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
  [ -n "$TOKEN" ] && break
  sleep 2
done
[ -n "$TOKEN" ] || { echo "Service account token was not created"; exit 1; }
CA=$($K config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

cat > "$CI_KUBECONFIG" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: $NAME
  cluster:
    server: https://$IP:6443
    certificate-authority-data: $CA
users:
- name: ci-deployer
  user:
    token: $TOKEN
contexts:
- name: ci-deployer@$NAME
  context:
    cluster: $NAME
    user: ci-deployer
    namespace: default
current-context: ci-deployer@$NAME
EOF

echo "== 9. Check the CI identity: can manage deployments, cannot read secrets"
KCI="kubectl --kubeconfig $(winpath "$CI_KUBECONFIG")"
echo "create deployments: $($KCI auth can-i create deployments)"
echo "get secrets:        $($KCI auth can-i get secrets || true)"

echo
echo "Done. App will be served at http://$IP/ after the first deployment."
echo "CI kubeconfig: $CI_KUBECONFIG  (GitHub secret KUBECONFIG / Jenkins secret file 'kubeconfig'; never commit it)"
