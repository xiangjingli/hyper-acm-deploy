#!/bin/bash

# $1 - type e.g "error", "info" (yellow - 33; red -31 )
# $2 - message
function comment() {
if [ "$1" = "error" ]; then
    echo -e '\033[0;31m>>> '$2' <<<\033[0m'
else 
    echo -e '\033[0;33m>>> '$2' <<<\033[0m'
fi
}

function usage () {
    echo "hyper-acm-install.sh is to install ACM components on the hosted cluster namespace according to the given configuration file"
    echo ""
    echo "Options:"
    echo "  -f     Configuration ini file name"
    echo "  -n     Hosted cluster Namespace"
    echo "  -c     Hosted cluster Name"
    echo "  -h     Help"
    echo ""
    echo "Example: ./hyper-acm-install.sh -f acm.conf -n hypershift-clusters -c acm-1"
}

function uninstall_usage () {
    echo "hyper-acm-uninstall.sh is to uninstall ACM components from the hosted cluster and management cluster"
    echo ""
    echo "Options:"
    echo "  -n     Hosted cluster Namespace"
    echo "  -c     Hosted cluster Name"
    echo "  -h     Help"
    echo ""
    echo "Example: ./hyper-acm-uninstall.sh -n hypershift-clusters -c acm-1"
}

function import_cluster_usage () {
    echo "import-cluster.sh is to import a managed cluster to the hosted cluster"
    echo ""
    echo "Options:"
    echo "  -f     Configuration ini file name"
    echo "  -n     Hosted cluster Namespace"
    echo "  -c     Hosted cluster Name"
    echo "  -m     Managed cluster Name"
    echo "  -k     Managed cluster kubeconfig file name"
    echo "  -h     Help"
    echo ""
    echo "Example: ./import-cluster.sh -f acm.conf -n hypershift-clusters -c acm-1 -m cluster1 -k ~/.kube/kubeconfig.kind"
}

function detach_cluster_usage () {
    echo "detach-cluster.sh is to detach a managed cluster from the hosted cluster"
    echo ""
    echo "Options:"
    echo "  -n     Hosted cluster Namespace"
    echo "  -c     Hosted cluster Name"
    echo "  -m     Managed cluster Name"
    echo "  -k     Managed cluster kubeconfig file name"
    echo "  -h     Help"
    echo ""
    echo "Example: ./detach-cluster.sh -n hypershift-clusters -c acm-1 -m cluster1 -k ~/.kube/kubeconfig.kind"
}

function check_dependency () {
  which oc > /dev/null
  if [ $? -ne 0 ]; then
    echo "oc is not installed."
    exit 1
  fi
}

function cfg_parser ()
{
    ini="$(<$1)"                # read the file
    ini="${ini//[/\[}"          # escape [
    ini="${ini//]/\]}"          # escape ]
    IFS=$'\n' && ini=( ${ini} ) # convert to line-array
    ini=( ${ini[*]//;*/} )      # remove comments with ;
    ini=( ${ini[*]/\    =/=} )  # remove tabs before =
    ini=( ${ini[*]/=\   /=} )   # remove tabs after =
    ini=( ${ini[*]/\ =\ /=} )   # remove anything with a space around =
    ini=( ${ini[*]/#\\[/\}$'\n'cfg.section.} ) # set section prefix
    ini=( ${ini[*]/%\\]/ \(} )    # convert text2function (1)
    ini=( ${ini[*]/=/=\( } )    # convert item to array
    ini=( ${ini[*]/%/ \)} )     # close array parenthesis
    ini=( ${ini[*]/%\\ \)/ \\} ) # the multiline trick
    ini=( ${ini[*]/%\( \)/\(\) \{} ) # convert text2function (2)
    ini=( ${ini[*]/%\} \)/\}} ) # remove extra parenthesis
    ini[0]="" # remove first element
    ini[${#ini[*]} + 1]='}'    # add the last brace
    eval "$(echo "${ini[*]}")" # eval the result
}

cfg_writer ()
{
    IFS=' '$'\n'
    fun="$(declare -F)"
    fun="${fun//declare -f/}"
    for f in $fun; do
        [ "${f#cfg.section}" == "${f}" ] && continue
        item="$(declare -f ${f})"
        item="${item##*\{}"
        item="${item%\}}"
        item="${item//=*;/}"
        vars="${item//=*/}"
        eval $f
        echo "[${f#cfg.section.}]"
        for var in $vars; do
            echo $var=\"${!var}\"
        done
    done
}

waitForNoPods() {
    MINUTE=0
    resNamespace=$1
    while [ true ]; do
        # Wait up to 3min
        if [ $MINUTE -gt 180 ]; then
            echo "Timeout waiting for addons to be removed"
            exit 1
        fi
        operatorRes=`oc get pods -n ${resNamespace} | wc`

        if [ $? -eq 0 ]; then
            echo "All pods in the ${resNamespace} namespace removed"
            break
        fi
        echo "* STATUS: Pods still running in the ${resNamespace} namespace removed. Retry in 5 sec"
        sleep 5
        (( MINUTE = MINUTE + 5 ))
    done
}


waitForCMD() {
    eval CMD="$1"
    eval WAIT_MSG="$2"

    MINUTE=0
    while [ true ]; do
        # Wait up to 3min
        if [ $MINUTE -gt 180 ]; then
            echo "Timeout waiting for ${CMD}"
            exit 1
        fi
        echo ${CMD}
        eval ${CMD}
        if [ $? -eq 0 ]; then
            break
        fi
        echo "* STATUS: ${WAIT_MSG}. Retry in 5 sec"
        sleep 5
        (( MINUTE = MINUTE + 5 ))
    done
}

waitForRes() {
    FOUND=1
    MINUTE=0
    resKinds=$1
    resName=$2
    resNamespace=$3
    ignore=$4
    running="\([0-9]\+\)\/\1"
    printf "\n#####\nWait for ${resNamespace}/${resName} to reach running state (4min).\n"
    while [ ${FOUND} -eq 1 ]; do
        # Wait up to 3min, should only take about 20-30s
        if [ $MINUTE -gt 180 ]; then
            echo "Timeout waiting for the ${resNamespace}\/${resName}."
            echo "List of current resources:"
            oc get ${resKinds} -n ${resNamespace} ${resName}
            echo "You should see ${resNamespace}/${resName} ${resKinds}"
            if [ "${resKinds}" == "pods" ]; then
                oc describe deployments -n ${resNamespace} ${resName}
            fi
            exit 1
        fi
        if [ "$ignore" == "" ]; then
            operatorRes=`oc get ${resKinds} -n ${resNamespace} | grep ${resName}`
        else
            operatorRes=`oc get ${resKinds} -n ${resNamespace} | grep ${resName} | grep -v ${ignore}`
        fi
        if [[ $(echo $operatorRes | grep "${running}") ]]; then
            echo "* ${resName} is running"
            break
        elif [ "$operatorRes" == "" ]; then
            operatorRes="Waiting"
        fi
        echo "* STATUS: $operatorRes"
        sleep 5
        (( MINUTE = MINUTE + 5 ))
    done
}

