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

CERT_MANAGER_VERSION="v1.21.2"
EXTERNAL_SECRETS_VERSION="2.11.0"
STRIMZI_VERSION="1.2.0"
NGF_VERSION="2.7.2"
K8SSANDRA_OPERATOR_VERSION="1.33.0"

WITH_CASSANDRA=false
for arg in "$@"; do
    case $arg in
        --with-cassandra)
        WITH_CASSANDRA=true
        ;;
        *)
        echo "Usage: $0 [--with-cassandra]" >&2
        exit 2
        ;;
    esac
done

kubectl apply -f tb-namespace.yml

helm repo add jetstack https://charts.jetstack.io --force-update
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm repo add strimzi https://strimzi.io/charts/ --force-update

# Gateway API CRDs from the NGINX Gateway Fabric release, including the experimental TCPRoute and UDPRoute
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/experimental?ref=v${NGF_VERSION}" \
    | kubectl apply --server-side -f -

helm upgrade --install cert-manager jetstack/cert-manager --version "${CERT_MANAGER_VERSION}" \
    --namespace cert-manager --create-namespace \
    --set crds.enabled=true \
    --set "extraArgs={--enable-gateway-api}" \
    --wait

helm upgrade --install external-secrets external-secrets/external-secrets --version "${EXTERNAL_SECRETS_VERSION}" \
    --namespace external-secrets --create-namespace \
    --wait

kubectl apply --server-side \
    -f "https://github.com/strimzi/strimzi-kafka-operator/releases/download/${STRIMZI_VERSION}/strimzi-crds-${STRIMZI_VERSION}.yaml"
helm upgrade --install strimzi-kafka-operator strimzi/strimzi-kafka-operator --version "${STRIMZI_VERSION}" \
    --namespace thingsboard \
    --skip-crds \
    --set watchNamespaces="{thingsboard}" \
    --wait

helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric --version "${NGF_VERSION}" \
    --namespace nginx-gateway --create-namespace \
    --set nginxGateway.gwAPIExperimentalFeatures.enable=true \
    --wait

if [ "$WITH_CASSANDRA" == "true" ]; then
    helm repo add k8ssandra https://helm.k8ssandra.io/stable --force-update
    helm upgrade --install k8ssandra-operator k8ssandra/k8ssandra-operator --version "${K8SSANDRA_OPERATOR_VERSION}" \
        --namespace thingsboard \
        --wait
fi

echo "Operators installed successfully!"
