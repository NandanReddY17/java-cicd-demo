# AWS (not used)

The pipeline was first built for AWS. The AWS **Free plan** account blocked it with an
explicit-deny service control policy:

- `eks-cluster.yaml`, `setup-aws.sh`, `ci-iam-policy.json`: Amazon EKS + ECR. EKS, EC2, ECR and
  load balancers were all denied.
- `setup-lightsail.sh`: second attempt, k3s on an Amazon Lightsail server. Lightsail could be
  read, but `CreateInstances` and `CreateKeyPair` were denied.

The project therefore runs on **Azure AKS** (Azure free trial, spending limit on); see `../azure`.
These files are kept as a record of the attempts.
