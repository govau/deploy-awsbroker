#!/bin/bash

set -eu
set -o pipefail

: "${HELM_PREFIX:?Need to set HELM_PREFIX}"
: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${NAMESPACE:?Need to set NAMESPACE}"
: "${TILLER_NAMESPACE:?Need to set TILLER_NAMESPACE}"

echo $KUBECONFIG > k
export KUBECONFIG=k

ci_user=ci-user

set -x

echo "Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

helm init --client-only --service-account "${ci_user}" --wait

helm delete "${HELM_PREFIX}catalog" --purge
helm delete "${HELM_PREFIX}etcd-operator" --purge
