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

function installTb() {

    loadDemo=$1

    kubectl apply -f tb-node-db-configmap.yml

    kubectl apply -f tb-cache-configmap.yml
    kubectl apply -f tb-node-configmap.yml
    kubectl apply -f tb-kafka-configmap.yml

    kubectl rollout status statefulset/zookeeper
    kubectl rollout status statefulset/tb-valkey
    kubectl wait kafka/tb --for=condition=Ready --timeout=600s

    # OCI Database with PostgreSQL creates only the `postgres` database
    kubectl delete job tb-create-db --ignore-not-found
    kubectl apply -f postgres-create-db.yml
    if ! kubectl wait --for=condition=complete job/tb-create-db --timeout=300s; then
        kubectl logs job/tb-create-db || true
        exit 1
    fi

    kubectl delete pod tb-db-setup --ignore-not-found
    kubectl apply -f database-setup.yml
    kubectl wait --for=condition=Ready pod/tb-db-setup --timeout=300s
    kubectl exec tb-db-setup -- sh -c 'export INSTALL_TB=true; export LOAD_DEMO='"$loadDemo"'; start-tb-node.sh; rc=$?; touch /tmp/install-finished; exit $rc'

    kubectl delete pod tb-db-setup

}

LOAD_DEMO=false
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --loadDemo)
    LOAD_DEMO=true
    ;;
    *)
            # unknown option
    ;;
esac
shift # past argument or value
done

kubectl apply -f tb-namespace.yml
kubectl config set-context --current --namespace=thingsboard

if ! kubectl get secret postgres > /dev/null 2>&1; then
    echo "Secret 'postgres' not found. Apply external-secrets/postgres.yml and wait until it is synced." >&2
    exit 1
fi

kubectl apply -f zookeeper.yml
kubectl apply -f tb-valkey.yml
kubectl apply -f kafka.yml

installTb ${LOAD_DEMO}
