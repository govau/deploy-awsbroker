#!/bin/bash

eval $(./ups_as_envs.py)

./servicebroker \
    -logtostderr \
    -brokerId="${BROKER_ID:=awsservicebroker}" \
    -enableBasicAuth=true \
    -basicAuthUser="${BROKER_USERNAME}" \
    -basicAuthPass="${BROKER_PASSWORD}" \
    -insecure=true \
    -port="${PORT}" \
    -region=ap-southeast-2 \
    -s3Bucket="${S3_BUCKET:=awsservicebroker}" \
    -s3Key="${S3_KEY:=templates/latest/}" \
    -s3Region="${S3_REGION:=us-east-1}" \
    -tableName="${TABLE_NAME}" \
    -templateFilter="${TEMPLATE_FILTER:=-main.yaml}" \
    -prescribeOverrides="${PRESCRIBE:=true}" \
    -v="${VERBOSITY:=5}"
