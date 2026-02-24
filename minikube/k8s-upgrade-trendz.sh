#!/bin/bash
#
# Copyright © 2016-2020 The Thingsboard Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -euo pipefail

NAMESPACE="thingsboard"
STATEFULSET="trendz-app"
JOB_NAME="trendz-upgrade"
JOB_FILE="./trendz/trendz-upgrade.yml"
STS_FILE="./trendz/trendz-app.yml"

kubectl scale statefulset "${STATEFULSET}" -n "${NAMESPACE}" --replicas=0
kubectl apply -f "${JOB_FILE}" -n "${NAMESPACE}"

if ! kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=900s; then
  echo "ERROR: Job ${JOB_NAME} did not complete successfully"
  kubectl get job "${JOB_NAME}" -n "${NAMESPACE}" -o wide || true
  kubectl describe job "${JOB_NAME}" -n "${NAMESPACE}" || true
  kubectl logs "job/${JOB_NAME}" -n "${NAMESPACE}" || true
  if kubectl wait --for=condition=failed "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=1s >/dev/null 2>&1; then
    echo "ERROR: Job ${JOB_NAME} is in FAILED state"
  else
    echo "ERROR: Job ${JOB_NAME} timed out (not complete within 900s)"
  fi
  exit 1
fi

kubectl logs "job/${JOB_NAME}" -n "${NAMESPACE}" || true
kubectl delete job "${JOB_NAME}" -n "${NAMESPACE}" --ignore-not-found

kubectl apply -f "${STS_FILE}" -n "${NAMESPACE}"
