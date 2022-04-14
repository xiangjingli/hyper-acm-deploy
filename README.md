# hyper-acm-deploy
Deploy ACM components on a Hypershift hosted cluster based on the given configuration file.

## Create Configuration file

Please check the configuration file sample [acm.conf] (acm.conf), where

- You can choose which ACM components (App, Policy, Observability) to be installed. The ACM foundation component is always installed by default.
- You can specify images for each component


## Install ACM Hub on a Hypershift hosted cluster
```
export KUBECONFIG=<management cluster kubeconfig>
./hyper-acm-install.sh -f <configuration file name> -n <Hosted cluster Namespace> -c <Hosted cluster Name>
```

## Uninstall ACM Hub from a Hypershift hosted cluster
```
export KUBECONFIG=<management cluster kubeconfig>
./hyper-acm-uninstall.sh -n <Hosted cluster Namespace> -c <Hosted cluster Name>
```

## Import a managed cluster to the ACM hub

### Prereqs
An existing k8s cluster is required. For example, you can create a new `kind` cluster and import it to the ACM hub

```
export KUBECONFIG=<management cluster kubeconfig>
./import-cluster.sh -n <Hosted cluster Namespace> -c <Hosted cluster Name> -m <the managed cluster name> -k <the managed cluster kubeconfig>
```
## Detach a managed cluster from the ACM hub
```
./detach-cluster.sh -n <Hosted cluster Namespace> -c <Hosted cluster Name> -m <the managed cluster name> -k <the managed cluster kubeconfig>
```