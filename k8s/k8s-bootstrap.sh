#!/usr/bin/env bash

# This script is run outside of CI with elevated priviledges mainly to
# configure CI prequisities such as ci service account and secrets

set -eu
set -o pipefail

PIPELINE=awsbroker-k8s

# We use two namespaces - one for CI testing, and the other for the actual deployment
# The ci-user will be created in the CI namespace, but will also have access
# to the deployment namespace
NAMESPACE=aws-sb
NAMESPACE_CI="${NAMESPACE}-ci"

ci_user="ci-user"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

set_credhub_value() {
  KEY="$1"
  VALUE="$2"
  https_proxy=socks5://localhost:8112 \
  credhub set -n "/concourse/apps/$PIPELINE/$KEY" -t value -v "${VALUE}"
}

echo "Ensuring you are logged in to credhub"
if ! https_proxy=socks5://localhost:8112 credhub find > /dev/null; then
  https_proxy=socks5://localhost:8112 credhub login --sso
fi

if kubectl --namespace ${NAMESPACE_CI} get serviceaccount ${ci_user} > /dev/null 2>&1 ; then
  echo "Rotating service account creds"
  kubectl --namespace ${NAMESPACE_CI} delete serviceaccount ${ci_user}
fi

kubectl apply -f <(cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: "${NAMESPACE_CI}"
---
apiVersion: v1
kind: Namespace
metadata:
  name: "${NAMESPACE}"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: "${ci_user}"
  namespace: "${NAMESPACE_CI}"
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: "tiller-manager"
  namespace: "${NAMESPACE_CI}"
rules:
- apiGroups: ["", "batch", "extensions", "apps"]
  resources: ["*"]
  verbs: ["*"]
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: "tiller-manager"
  namespace: "${NAMESPACE}"
rules:
- apiGroups: ["", "batch", "extensions", "apps"]
  resources: ["*"]
  verbs: ["*"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: tiller-binding
  namespace: "${NAMESPACE_CI}"
subjects:
- kind: ServiceAccount
  name: "${ci_user}"
  namespace: "${NAMESPACE_CI}"
roleRef:
  kind: Role
  name: "tiller-manager"
  apiGroup: rbac.authorization.k8s.io
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: tiller-binding
  namespace: "${NAMESPACE}"
subjects:
- kind: ServiceAccount
  name: "${ci_user}"
  namespace: "${NAMESPACE_CI}"
roleRef:
  kind: Role
  name: "tiller-manager"
  apiGroup: rbac.authorization.k8s.io
EOF
)

# Add the rbac permissions required by etcd-operator to the service account
kubectl apply -f <(cat <<EOF
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: etcd-operator-ci
  namespace: "${NAMESPACE_CI}"
rules:
- apiGroups:
  - etcd.database.coreos.com
  resources:
  - etcdclusters
  - etcdbackups
  - etcdrestores
  verbs:
  - "*"
- apiGroups:
  - apiextensions.k8s.io
  resources:
  - customresourcedefinitions
  verbs:
  - "*"
- apiGroups:
  - ""
  resources:
  - pods
  - services
  - endpoints
  - persistentvolumeclaims
  - events
  verbs:
  - "*"
- apiGroups:
  - apps
  resources:
  - deployments
  verbs:
  - "*"
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: etcd-operator
  namespace: "${NAMESPACE}"
rules:
- apiGroups:
  - etcd.database.coreos.com
  resources:
  - etcdclusters
  - etcdbackups
  - etcdrestores
  verbs:
  - "*"
- apiGroups:
  - apiextensions.k8s.io
  resources:
  - customresourcedefinitions
  verbs:
  - "*"
- apiGroups:
  - ""
  resources:
  - pods
  - services
  - endpoints
  - persistentvolumeclaims
  - events
  verbs:
  - "*"
- apiGroups:
  - apps
  resources:
  - deployments
  verbs:
  - "*"
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: etcd-operator-ci-binding
  namespace: "${NAMESPACE_CI}"
subjects:
- kind: ServiceAccount
  name: "${ci_user}"
  namespace: "${NAMESPACE_CI}"
roleRef:
  kind: Role
  name: "etcd-operator-ci"
  apiGroup: rbac.authorization.k8s.io
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: etcd-operator-binding
  namespace: "${NAMESPACE}"
subjects:
- kind: ServiceAccount
  name: "${ci_user}"
  namespace: "${NAMESPACE_CI}"
roleRef:
  kind: Role
  name: "etcd-operator"
  apiGroup: rbac.authorization.k8s.io
---
EOF
)


secret="$(kubectl get "serviceaccount/${ci_user}" --namespace "${NAMESPACE_CI}" -o=jsonpath='{.secrets[0].name}')"
token="$(kubectl get secret "${secret}" --namespace "${NAMESPACE_CI}" -o=jsonpath='{.data.token}' | base64 --decode)"

cur_context="$(kubectl config view -o=jsonpath='{.current-context}' --flatten=true)"
cur_cluster="$(kubectl config view -o=jsonpath="{.contexts[?(@.name==\"${cur_context}\")].context.cluster}" --flatten=true)"
cur_api_server="$(kubectl config view -o=jsonpath="{.clusters[?(@.name==\"${cur_cluster}\")].cluster.server}" --flatten=true)"
cur_crt="$(kubectl config view -o=jsonpath="{.clusters[?(@.name==\"${cur_cluster}\")].cluster.certificate-authority-data}" --flatten=true)"

kubeconfig="$(cat <<EOF
{
  "apiVersion": "v1",
  "clusters": [
    {
      "cluster": {
        "certificate-authority-data": "${cur_crt}",
        "server": "${cur_api_server}"
      },
      "name": "kubernetes"
    }
  ],
  "contexts": [
    {
      "context": {
        "cluster": "kubernetes",
        "user": "${ci_user}",
        "namespace": "${NAMESPACE_CI}"
      },
      "name": "${NAMESPACE_CI}"
    },
    {
      "context": {
        "cluster": "kubernetes",
        "user": "${ci_user}",
        "namespace": "${NAMESPACE}"
      },
      "name": "${NAMESPACE}"
    }
  ],
  "current-context": "${NAMESPACE}-ci",
  "kind": "Config",
  "users": [
    {
      "name": "${ci_user}",
      "user": {
        "token": "${token}"
      }
    }
  ]
}
EOF
)"

set_credhub_value kubeconfig "${kubeconfig}"

echo "Use in concourse:"
echo "echo \$KUBECONFIG > k"
echo "export KUBECONFIG=k"
echo "kubectl get all"
