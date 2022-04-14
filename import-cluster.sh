#!/bin/bash

source ./helpers.sh

check_dependency

if [ "$#" -lt 1 ]; then
  import_cluster_usage
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
      import_cluster_usage
      exit 0
      ;;
    *)
      import_cluster_usage
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

comment "info" "4. Create the managed cluster on the hosted cluster"

export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig

sed -e "s,\<MANAGED_CLUSTER_NAME\>,${MANAGED_CLUSTER_NAME}," foundation/hosted/01-managedcluster.yaml | oc apply -f -

RUN_CMD="oc get secrets -n ${MANAGED_CLUSTER_NAME} ${MANAGED_CLUSTER_NAME}-import"
WAIT_MSG="The managed cluster import secret is not ready"
waitForCMD "\${RUN_CMD}" "\${WAIT_MSG}"

oc get secret -n ${MANAGED_CLUSTER_NAME} ${MANAGED_CLUSTER_NAME}-import -o jsonpath={.data.crds\\\.yaml} | base64 -d  > import-crds.yaml
oc get secret -n ${MANAGED_CLUSTER_NAME} ${MANAGED_CLUSTER_NAME}-import -o jsonpath={.data.import\\\.yaml} | base64 -d > import.yaml

comment "info" "5. apply klusterlet manifest to the managed cluster"

export KUBECONFIG=${MANAGED_KUBECONFIG}
oc apply -f import-crds.yaml
oc apply -f import.yaml

comment "info" "6. Wait for open-cluster-management-agent pods to be Ready"
waitForRes "pods" "klusterlet" "open-cluster-management-agent" ""

comment "info" "7. Check the managed cluster status"

export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig

sleep 5
oc get managedclusters ${MANAGED_CLUSTER_NAME}

comment "info" "8. Enable the app addon on the managed cluster"

sed -e "s,\<MANAGED_CLUSTER_NAME\>,${MANAGED_CLUSTER_NAME}," app/hosted/2-app-addon.yaml | oc apply -f -
