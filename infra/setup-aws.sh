#!/usr/bin/env bash
# One-time AWS setup for the CI/CD pipeline. Run from the repo root in Git Bash
# after `aws configure` (with your own admin IAM user).
#
# Creates: ECR repository, EKS cluster, a least-privilege IAM user for GitHub Actions,
# and an EKS access entry so that user can deploy to the default namespace only.
set -euo pipefail

REGION=ap-south-1
CLUSTER=java-cicd-cluster
REPO=java-cicd-demo
CI_USER=github-actions-cicd

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS account: $ACCOUNT_ID  region: $REGION"

echo "== 1. ECR repository (scan on push, immutable tags off so 'latest' can move)"
aws ecr describe-repositories --repository-names "$REPO" --region "$REGION" >/dev/null 2>&1 ||
  aws ecr create-repository --repository-name "$REPO" --region "$REGION" \
    --image-scanning-configuration scanOnPush=true >/dev/null
echo "ECR: $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO"

echo "== 2. EKS cluster (takes ~15-20 minutes)"
if ! aws eks describe-cluster --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
  eksctl create cluster -f infra/eks-cluster.yaml
fi
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl get nodes

echo "== 3. IAM user for GitHub Actions (least privilege)"
aws iam get-user --user-name "$CI_USER" >/dev/null 2>&1 || aws iam create-user --user-name "$CI_USER" >/dev/null
sed -e "s/ACCOUNT_ID/$ACCOUNT_ID/g" -e "s/REGION/$REGION/g" infra/ci-iam-policy.json > /tmp/ci-policy.json
aws iam put-user-policy --user-name "$CI_USER" --policy-name cicd-ecr-eks \
  --policy-document file:///tmp/ci-policy.json

echo "== 4. Allow the CI user to deploy into the 'default' namespace of the cluster"
CI_ARN="arn:aws:iam::$ACCOUNT_ID:user/$CI_USER"
aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION" \
  --principal-arn "$CI_ARN" >/dev/null 2>&1 || true
aws eks associate-access-policy --cluster-name "$CLUSTER" --region "$REGION" \
  --principal-arn "$CI_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
  --access-scope type=namespace,namespaces=default >/dev/null

echo
echo "Done. Now create an access key for '$CI_USER' in the AWS console"
echo "(IAM > Users > $CI_USER > Security credentials > Create access key)"
echo "and save it as GitHub secrets AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."
