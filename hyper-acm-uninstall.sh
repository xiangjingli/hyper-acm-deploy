#!/bin/bash

source ./helpers.sh

check_dependency

if [ "$#" -lt 1 ]; then
  uninstall_usage
  exit 0
fi

while getopts "c:n:" arg; do
  case $arg in
    c)
      CLUSTER_NAME="${OPTARG}"
      ;;
    n)
      CLUSTER_NAMESPACE="${OPTARG}"
      ;;
    :)
      usage
      exit 0
      ;;
    *)
      uninstall_usage
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

comment "info" "3. Uninstalling ACM App component"

export KUBECONFIG=./hub.kubeconfig
oc delete deployments -n ${HOSTED_CLUSTER} multicluster-operators-channel multicluster-operators-hub-subscription multicluster-operators-application multicluster-operators-subscription-report konnectivity-agent-webhook

oc delete services -n ${HOSTED_CLUSTER} channels-apps-open-cluster-management-webhook-svc

export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig

oc delete endpoints -n ${HOSTED_CLUSTER} channels-apps-open-cluster-management-webhook-svc

oc delete services -n ${HOSTED_CLUSTER} channels-apps-open-cluster-management-webhook-svc


comment "info" "4. Uninstalling ACM Policy component"




comment "info" "5. Uninstalling ACM Observability component"




comment "info" "6. Uninstalling ACM foundation component"


comment "info" "6.1 Delete the hosted cluster namespace from the hosted cluster"

export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig

oc delete namespace ${HOSTED_CLUSTER}


comment "info" "6.2 Delete foundation components from the management cluster"

export KUBECONFIG=./hub.kubeconfig
oc delete deployments -n ${HOSTED_CLUSTER} managedcluster-import-controller hub-registration-controller clustermanager-placement-controller




