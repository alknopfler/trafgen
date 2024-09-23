#!/bin/bash
# get running pids
#
# Author
# Mus mbayramov@vmware.com


KUBECONFIG_FILE="kubeconfig"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "kubeconfig file not found in the current directory."
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_FILE"
server_pods=($(kubectl get pods -l role=server -o jsonpath='{.items[*].status.podIP}'))

if [ ${#server_pods[@]} -ne ${#DEST_IPS[@]} ]; then
    echo "The number of server pods and destination IPs do not match."
    exit 1
fi

for i in "${!server_pods[@]}"
do
    pod="${server_pods[$i]}"
    echo "process list on a $pod"
    kubectl exec "$pod" -- ps auxwww
done