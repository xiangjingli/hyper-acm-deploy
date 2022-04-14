# hyper-acm-deploy
Deploy ACM components on a Hypershift hosted cluster based on the given configuration file.

## Prereqs
At least three running k8s clusters are required:

- A k8s cluster runs as the management cluster.

- A hosted cluster provisioned by Hypershift should be running on the management cluster. To verify this:
1. Check the hostedCluster CR status
```
% oc get hostedclusters -n <Hosted cluster Namespace> <Hosted cluster Name>
```
2. Check if the hosted cluster can be accessed.
```
% CLUSTER_NAMESPACE=<Hosted cluster Namespace>
% CLUSTER_NAME=<Hosted cluster Name>
% HOSTED_CLUSTER_KUBECONFIG=`oc get hostedcluster -n ${CLUSTER_NAMESPACE} ${CLUSTER_NAME} -o jsonpath={.status.kubeconfig.name}`
% oc get secret -n ${CLUSTER_NAMESPACE} ${HOSTED_CLUSTER_KUBECONFIG} -o jsonpath={.data.kubeconfig} | base64 -d > ${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig
% export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig
% oc cluster-info
```

- The rest of the k8s clusters run as the managed clusters. Those clusters will be imported to the ACM hub via `import-cluster.sh`.

## Create Configuration file acm.conf

Please check the configuration file sample [acm.conf] (acm.conf), where

- You can choose which ACM components (App, Policy, Observability) to be installed. The ACM foundation component is always installed by default.
- You can specify images for each component


## Install ACM Hub on a Hypershift hosted cluster
```
% export KUBECONFIG=<management cluster kubeconfig>
% ./hyper-acm-install.sh -f <configuration file name> -n <Hosted cluster Namespace> -c <Hosted cluster Name>
```

## Uninstall ACM Hub from a Hypershift hosted cluster
```
% export KUBECONFIG=<management cluster kubeconfig>
% ./hyper-acm-uninstall.sh -n <Hosted cluster Namespace> -c <Hosted cluster Name>
```

## Import a managed cluster to the ACM hub
```
% export KUBECONFIG=<management cluster kubeconfig>
% ./import-cluster.sh -n <Hosted cluster Namespace> -c <Hosted cluster Name> -m <the managed cluster name> -k <the managed cluster kubeconfig>
```
## Detach a managed cluster from the ACM hub
```
% export KUBECONFIG=<management cluster kubeconfig>
% ./detach-cluster.sh -f <configuration file name> -n <Hosted cluster Namespace> -c <Hosted cluster Name> -m <the managed cluster name> -k <the managed cluster kubeconfig>
```