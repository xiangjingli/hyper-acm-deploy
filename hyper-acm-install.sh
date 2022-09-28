#!/bin/bash

source ./helpers.sh
source ./bash-ini-parser

check_dependency

if [ "$#" -lt 1 ]; then
  usage
  exit 0
fi

while getopts "c:f:n:" arg; do
  case $arg in
    c)
      CLUSTER_NAME="${OPTARG}"
      ;;
    n)
      CLUSTER_NAMESPACE="${OPTARG}"
      ;;
    f)
      CONFIG="${OPTARG}"
      ;;
    :)
      usage
      exit 0
      ;;
    *)
      usage
      exit 0
      ;;
  esac
done

cfg_parser ${CONFIG}
cfg_writer

cfg.section.ACM_COMPONENTS
cfg.section.FOUNDATION_IMAGES
cfg.section.APP_IMAGES
cfg.section.POLICY_IMAGES


if [ "${APP}" = "true" ]; then
  install_list="APP"
fi

if [ "${POLICY}" = "true" ]; then
  install_list="${install_list} POLICY"
fi

if [ "${OBSERVABILITY}" = "true" ]; then
  install_list="${install_list} OBSERVABILITY"
fi

if [ "${HIVE}" = "true" ]; then
  install_list="${install_list} HIVE"
fi

comment "info" "The following ACM components will be installed: ${install_list}"

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

comment "info" "3. Installing ACM foundation component"

comment "info" "3.1 Applying foundation component CRDs on the hosted cluster"

export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig
oc apply -f foundation/hosted/crds

comment "info" "3.2 Create the same hosted cluster namespace on the hosted cluster to support leader election of registration controllers"
oc create namespace ${HOSTED_CLUSTER}

comment "info" "3.3 Create ocp global pull secret to host cluster namespace on the hosted cluster"
pull_secret=$(mktemp /tmp/pull-secret.XXXXXX)
oc get secret -n openshift-config pull-secret -o jsonpath={.data.\\\.dockerconfigjson} | base64 -d > $pull_secret
oc create secret docker-registry -n ${HOSTED_CLUSTER} pull-secret --from-file=.dockerconfigjson=$pull_secret
rm -rf $pull_secret

comment "info" "3.4 Applying foundation components on the management cluster"

export KUBECONFIG=./hub.kubeconfig

sed -e "s,\<HUB_REGISTRATION\>,${HUB_REGISTRATION}," -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," foundation/management/01-hub-registration-deployment.yaml | oc apply -f -

sed -e "s,\<MANAGED_CLUSTER_IMPORT\>,${MANAGED_CLUSTER_IMPORT},"  -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," -e "s,\<HUB_REGISTRATION\>,${HUB_REGISTRATION}," -e "s,\<REGISTRATION_OPERATOR\>,${REGISTRATION_OPERATOR}," -e "s,\<MANIFEST_WORK\>,${MANIFEST_WORK}," foundation/management/02-managed-cluster-import-deployment.yaml | oc apply -f -

sed -e "s,\<PLACEMENT\>,${PLACEMENT}," -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," foundation/management/03-placement-deployment.yaml | oc apply -f -

if [ "${APP}" = "true" ]; then
  comment "info" "4. Installing ACM App component"

  comment "info" "4.1 Applying App component CRDs on the hosted cluster"

  export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig
  oc apply -f app/hosted/crds

  comment "info" "4.2 Applying App components on the management cluster"

  export KUBECONFIG=./hub.kubeconfig

  sed -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/management/1-service_account.yaml | oc apply -f -
  oc apply -f app/management/2-clusterrole.yaml
  sed -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/management/3-clusterrole_binding.yaml | oc apply -f -

  sed -e "s,\<CHANNEL\>,${CHANNEL}," -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/management/4-channel-deployment.yaml | oc apply -f -

  comment "info" "4.3 waiting for app channel pod to be Ready"
  waitForRes "pods" "multicluster-operators-channel" "${HOSTED_CLUSTER}" ""

  sed -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/management/5-channel-service.yaml | oc apply -f -

  CHANNEL_CLUSTER_IP=`oc get service -n ${HOSTED_CLUSTER} channels-apps-open-cluster-management-webhook-svc -o jsonpath='{.spec.clusterIP}'`
  comment "info" "CHANNEL_CLUSTER_IP=${CHANNEL_CLUSTER_IP}"

  if [ -z "${CHANNEL_CLUSTER_IP}" ]; then
    comment "error" "Failed to get the cluster ip of the app channel pod."
    exit 1
  fi

  sed -e "s,\<SUBSCRIPTION\>,${SUBSCRIPTION}," -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/management/6-hub-subscription-deployment.yaml | oc apply -f -
  sed -e "s,\<SUBSCRIPTION\>,${SUBSCRIPTION}," -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/management/7-application-deployment.yaml | oc apply -f -
  sed -e "s,\<SUBSCRIPTION\>,${SUBSCRIPTION}," -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/management/8-subscription-report-deployment.yaml | oc apply -f -
  sed -e "s,\<CHANNEL_CLUSTER_IP\>,${CHANNEL_CLUSTER_IP}," -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/management/9-konnectivity-agent-webhook-deployment.yaml | oc apply -f -

  comment "info" "4.3 Applying channel webhook service and endpoint on the hosted cluster"

  export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig

  sed -e "s,\<CHANNEL_CLUSTER_IP\>,${CHANNEL_CLUSTER_IP}," -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/hosted/1-channel-webhook-service.yaml | oc apply -f -

fi

if [ "${POLICY}" = "true" ]; then
  comment "info" "5. Installing ACM Policy component"

  comment "info" "5.1 Deploy policy CRDs on hosted cluster"

  export KUBECONFIG=${HOSTED_CLUSTER_KUBECONFIG}.kubeconfig
  oc apply -f policy/hosted/crds

  if [ "${APP}" != "true" ]; then

    comment "info" "5.1.1 Deploy App placementrule CRD on the hosted cluster"
    oc apply -f app/hosted/crds/apps.open-cluster-management.io_placementrules_crd_v1.yaml

    comment "info" "5.1.2 Deploy App placementrule hub component on the management cluster"

    export KUBECONFIG=hub.kubeconfig

    sed -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/management/1-service_account.yaml | oc apply -f -
    oc apply -f app/management/2-clusterrole.yaml
    sed -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/management/3-clusterrole_binding.yaml | oc apply -f -

    sed -e "s,\<SUBSCRIPTION\>,${SUBSCRIPTION}," -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," app/management/7-application-deployment.yaml | oc apply -f -
  fi

  comment "info" "5.2 Deploy Policy hub component on the management cluster"
  export KUBECONFIG=hub.kubeconfig

  sed -e "s,\<POLICY_PROPAGATOR\>,${POLICY_PROPAGATOR}," -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," policy/management/policy-propagator.yaml | oc apply -f -
  sed -e "s,\<POLICY_ADDON\>,${POLICY_ADDON}," -e "s,\<HOSTED_CLUSTER\>,${HOSTED_CLUSTER}," policy/management/policy-addon-controller.yaml | oc apply -f -
fi


comment "info" "6. Installing ACM Observability component"


