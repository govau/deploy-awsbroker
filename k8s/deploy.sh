#!/bin/bash

set -eu
set -o pipefail

: "${HELM_PREFIX:?Need to set HELM_PREFIX (can be an empty string)}"
: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${NAMESPACE:?Need to set NAMESPACE}"
: "${TILLER_NAMESPACE:?Need to set TILLER_NAMESPACE}"

echo $KUBECONFIG > k
export KUBECONFIG=k

ci_user=ci-user

set -x

kubectl get pods -n ${NAMESPACE} # just a test

echo "Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

helm init --client-only --service-account "${ci_user}" --wait --local-repo-url none

helm dependency update charts/stable/etcd-operator/

echo "Deploying etcd-operator (needed by Service Catalog)"
helm upgrade --install --wait \
  --namespace ${NAMESPACE} \
  -f ci/k8s/etcd-operator-values.yml \
  ${HELM_PREFIX}etcd-operator charts/stable/etcd-operator

echo "Waiting for etcd-operator to start"
kubectl rollout status --namespace=${NAMESPACE} --timeout=1m \
  --watch deployment/${HELM_PREFIX}etcd-operator-etcd-operator-etcd-operator

echo "Deploying Service Catalog (needed by AWS servicebroker)"
helm repo add svc-cat https://svc-catalog-charts.storage.googleapis.com
SC_VERSION="$(cat service-catalog.release/tag)"
helm upgrade --install --wait \
    --namespace ${NAMESPACE} \
    -f ci/k8s/catalog-values.yml \
    --version "${SC_VERSION}" \
    ${HELM_PREFIX}catalog svc-cat/catalog