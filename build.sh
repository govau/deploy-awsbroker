#!/bin/bash

set -eu
set -x
set -o pipefail

ORIG_PWD="${PWD}"

# Create our own GOPATH
export GOPATH="${ORIG_PWD}/go"

# Symlink our source dir from inside of our own GOPATH
mkdir -p "${GOPATH}/src/github.com/awslabs"
ln -s "${ORIG_PWD}/src" "${GOPATH}/src/github.com/awslabs/aws-servicebroker"

# Build it
go install github.com/awslabs/aws-servicebroker/cmd/servicebroker

# Copy artefacts to output directory
cp  "${ORIG_PWD}/ci/manifest.yml" \
    "${ORIG_PWD}/ci/Procfile" \
    "${ORIG_PWD}/ci/run_app.sh" \
    "${ORIG_PWD}/ci/ups_as_envs.py" \
    "${ORIG_PWD}/build"

printf "\ndomain: $DOMAIN\n" >> ${ORIG_PWD}/build/manifest.yml

cp "${GOPATH}/bin/servicebroker" \
   "${ORIG_PWD}/build/servicebroker"

echo "Files in build:"
ls -l "${ORIG_PWD}/build"
