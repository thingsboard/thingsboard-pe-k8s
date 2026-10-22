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


kubectl config set-context --current --namespace=thingsboard

# The gateway first: deleting its Service removes the network load balancer and releases the reserved address.
kubectl delete httproute,tcproute,udproute --all --ignore-not-found
kubectl delete gateway tb-gateway --ignore-not-found --wait
kubectl wait --for=delete service/tb-gateway-nginx --timeout=300s 2> /dev/null || true

kubectl delete -f tb-services.yml --ignore-not-found
kubectl delete -f transports/ --ignore-not-found
kubectl delete statefulset trendz-app trendz-python-executor --ignore-not-found

if kubectl get crd k8ssandraclusters.k8ssandra.io > /dev/null 2>&1; then
    kubectl delete k8ssandracluster --all --wait
fi
if kubectl get crd kafkas.kafka.strimzi.io > /dev/null 2>&1; then
    kubectl delete kafka,kafkanodepool --all --wait
fi
kubectl delete -f zookeeper.yml -f tb-valkey.yml --ignore-not-found
kubectl delete cm --selector='name' --ignore-not-found

# Deletes the block volumes behind the claims
kubectl delete pvc --all --wait
