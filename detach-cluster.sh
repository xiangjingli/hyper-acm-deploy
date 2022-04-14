#!/bin/bash

source ./helpers.sh

check_dependency

if [ "$#" -lt 1 ]; then
  detach_cluster_usage
  exit 0
fi

while getopts "c:n:m:k:" arg; do
  case $arg in
    c)
      CLUSTER_NAME="${OPTARG}"
      ;;
    n)
      CLUSTER_NAMESPACE="${OPTARG}"
      ;;
    m)
      MANAGED_CLUSTER_NAME="${OPTARG}"
      ;;
    k)
      MANAGED_KUBECONFIG="${OPTARG}"
      ;;
    :)
      detach_cluster_usage
      exit 0
      ;;
    *)
      detach_cluster_usage
      exit 0
      ;;
  esac
done

comment "info" "1. Validating management cluster status"

oc config view --minify=true --raw=true > hub.kubeconfig
export KUBECONFIG=./hub.kubeconfig
oc cluster-info
if [ $? -ne 0 ]; then
    comment "error" "Failed to access the management cluster."
    exit 1
fi

HOSTED_CLUSTER="${CLUSTER_NAMESPACE}-${CLUSTER_NAME}"
comment "info" "2. Validating hosted cluster status in the hosted cluster namespace: ${HOSTED_CLUSTER}"

HOSTED_CLUSTER_KUBECONFIG=`oc get hostedcluster -n ${CLUSTER_NAMESPACE} ${CLUSTER_NAME} -o jsonpath={.status.kubeconfig.name}`
oc get secret -n ${CLUSTER_NAMESPACE} ${HOSTED_CLUSTER_KUBECONFIG} -o jsonpath={.data.kubeconfig} | base64 -d > ${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig

export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig
oc cluster-info
if [ $? -ne 0 ]; then
    comment "error" "Failed to access the hosted cluster."
    exit 1
fi

comment "info" "3. Validating managed cluster status"

export KUBECONFIG=${MANAGED_KUBECONFIG}
oc cluster-info
if [ $? -ne 0 ]; then
    comment "error" "Failed to access the hosted cluster."
    exit 1
fi

comment "info" "4. Delete app addon from the hosted cluster"

export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig

oc delete managedclusteraddons -n ${MANAGED_CLUSTER_NAME} application-manager

comment "info" "4.1 wait for app addon to be removed from the managed cluster"

export KUBECONFIG=${MANAGED_KUBECONFIG}

waitForNoAppAddon

comment "info" "5. Delete klusterlet component from the managed cluster"

export KUBECONFIG=${MANAGED_KUBECONFIG}

oc delete deployments -n open-cluster-management-agent klusterlet

oc delete klusterlet klusterlet --wait=false --ignore-not-found
oc patch klusterlet klusterlet -p '{"metadata":{"finalizers":null}}' --type=merge


oc delete namespace open-cluster-management-agent --wait=false --ignore-not-found
oc delete namespace open-cluster-management-agent-addon --wait=false --ignore-not-found

comment "info" "6. Delete the managed cluster from the hosted cluster"

export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig

oc delete managedclusters ${MANAGED_CLUSTER_NAME} --wait=false --ignore-not-found

oc patch managedclusters ${MANAGED_CLUSTER_NAME} -p '{"metadata":{"finalizers":null}}' --type=merge

oc delete secret -n ${MANAGED_CLUSTER_NAME} ${MANAGED_CLUSTER_NAME}-import

