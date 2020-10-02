# Kubernetes resources configuration for ThingsBoard Microservices

This folder containing scripts and Kubernetes resources configurations to run ThingsBoard in Microservices mode.

## Prerequisites

ThingsBoard Microservices run on the Kubernetes cluster.
You need to have a Kubernetes cluster, and the kubectl command-line tool must be configured to communicate with your cluster.
If you do not have a cluster already, you can create one by using [Minikube](https://kubernetes.io/docs/setup/minikube),
AWS, GCP or you can choose any other available [Kubernetes cluster deployment solutions](https://unofficial-kubernetes.readthedocs.io/en/latest/setup/pick-right-solution/).

### Minikube Configuration

#### Enable ingress addon 
By default ingress addon is disabled in the Minikube, and available only in cluster providers.
To enable ingress, please execute the following command:

`
minikube addons enable ingress
` 

### AWS Configuration

To configure AWS setup, please choose one of the directory and use README.md there.  After configuring AWS, you can continue the installation from this step.

- ./aws/kubeone - KubeOne automates cluster operations on all your aws instances. KubeOne can install high-available (HA) master clusters as well single master clusters.

- ./aws/eks - Amazon EKS is a completely AWS-managed Kubernetes service.

## GCP Configuration

To configure GCP setup, plesae go to the ./gcp directory and use README.md there.  After configuring GCP, you can continue the installation from this step.

## Upload Docker credentials

Make sure your have logged in to docker hub using command line. To upload Docker credentials, please execute next command:

`
./k8s-upload-docker-credentials.sh
`

Or you can use the following command:

`
kubectl create secret docker-registry regcred --docker-server=https://index.docker.io/v1/ --docker-username=[YOUR_USERNAME] --docker-password=[YOUR_PASSWORD] --docker-email=[YOUR_EMAIL]
`

## Installation

Before performing initial installation you have to select correct `PLATFORM` in `.env` file depending on the real cluster platform you are using (`minikube`, `gcp`, `aws` or `aws-eks`).

Also, you can configure the type of database to be used with ThingsBoard and the type of deployment.
In order to set database type change the value of `DATABASE` variable in `.env` file to one of the following:

- `postgres` - use PostgreSQL database;
- `hybrid` - use PostgreSQL for entities database and Cassandra for timeseries database;

**NOTE**: According to the database type corresponding kubernetes resources will be deployed (see `postgres.yml`, `cassandra.yml` for details).

In order to set deployment type change the value of `DEPLOYMENT_TYPE` variable in `.env` file to one of the following:

- `basic` - start up with single instance of Zookeeper, Kafka and Redis;
- `high-availability` - start up with Zookeeper, Kafka and Redis in cluster modes;

**NOTE**: According to the deployment type corresponding kubernetes resources will be deployed (see the content of the directories `./basic` and `./high-availability` for details).

Execute the following command to run the installation:

`
./k8s-install-tb.sh --loadDemo
`

Where:

- `--loadDemo` - optional argument. Whether to load additional demo data.

## Configure your license key

`
nano common/tb-node.yml
`

and put the license secret parameter 

```
tb-node StatefulSet configuration

- name: TB_LICENSE_SECRET
  value: "PUT_YOUR_LICENSE_SECRET_HERE"
```

## Running

Execute the following command to deploy third-party resources:

`
./k8s-deploy-thirdparty.sh
`

Type **'yes'** when prompted, if you are running ThingsBoard in `high-availability` `DEPLOYMENT_TYPE` for the first time and don't have configured Redis cluster.

Before deploying ThingsBoard resources you should configure number of pods for each service. 
You can do it in `thingsboard.yml` by changing `spec.replicas` fields for different services. 
It is recommended to have at least 2 `tb-node` and 10 `tb-js-executor`.
Execute the following command to deploy resources:

`
./k8s-deploy-resources.sh
`

If you have used minikube after a while when all resources will be successfully started you can open `http://{your-cluster-ip}` in your browser (for ex. `http://192.168.99.101`).
You should see the ThingsBoard login page.

If you have used aws or gcp installations you can open ThingsBoard web interface in your browser using dns name or ip of the load balancer.

You can see DNS name or ip of the loadbalancer using command:

`
kubectl get ingress -oyaml
`

Or you can see this name on the ELB page.

You should see the ThingsBoard login page.

Use the following default credentials:

- **System Administrator**: sysadmin@thingsboard.org / sysadmin

If you installed DataBase with demo data (using `--loadDemo` flag) you can also use the following credentials:

- **Tenant Administrator**: tenant@thingsboard.org / tenant
- **Customer User**: customer@thingsboard.org / customer

In case of any issues, you can examine service logs for errors.
For example to see ThingsBoard node logs execute the following commands:

1) Get the list of the running tb-node pods:

`
kubectl get pods -l app=tb-node
`

2) Fetch logs of the tb-node pod:

`
kubectl logs -f [tb-node-pod-name]
`

Where:

- `tb-node-pod-name` - tb-node pod name obtained from the list of the running tb-node pods.

Or use `kubectl get pods` to see the state of all the pods.
Or use `kubectl get services` to see the state of all the services.
Or use `kubectl get deployments` to see the state of all the deployments.
See [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/) command reference for details.

Execute the following command to delete all ThingsBoard microservices:

`
./k8s-delete-resources.sh
`

Execute the following command to delete all third-party microservices:

`
./k8s-delete-thirdparty.sh
`

Execute the following command to delete all resources (including database):

`
./k8s-delete-all.sh
`

## Upgrading

In case when database upgrade is needed, execute the following commands:

```
./k8s-delete-resources.sh
./k8s-upgrade-tb.sh --fromVersion=[FROM_VERSION]
./k8s-deploy-resources.sh
```

Where:

- `FROM_VERSION` - from which version upgrade should be started. See [Upgrade Instructions](https://thingsboard.io/docs/user-guide/install/upgrade-instructions) for valid `fromVersion` values.
