#!/bin/bash
# Generate trafgen config per pod
# This script execute script inside each container and populate two trafgen files.
# i.e. script inside a POD need to know dst mac / dst ip etc.
# Mus mbayramov@vmware.com

DEFAULT_SRC_PORT="9"
DEFAULT_DST_PORT="6666"

# default pd size on the wire, add all header on top
DEFAULT_PD_SIZE="22"
SRC_PORT="$DEFAULT_SRC_PORT"
DST_PORT="$DEFAULT_DST_PORT"
PD_SIZE="$DEFAULT_PD_SIZE"

KUBECONFIG_FILE="kubeconfig"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "kubeconfig file not found in the current directory."
    exit 1
fi
export KUBECONFIG="$KUBECONFIG_FILE"

display_help() {
    echo "Usage: $0 [-s <source port>] [-d <destination port>] [-p <payload size>]"
    echo "-s: Source port for UDP traffic"
    echo "-d: Destination port for UDP traffic"
    echo "-p: Payload size for UDP packets"
}

while getopts ":s:d:p:i:" opt; do
    case ${opt} in
        s)
            SRC_PORT=$OPTARG
            ;;
        d)
            DST_PORT=$OPTARG
            ;;
        p)
            PD_SIZE=$OPTARG
            ;;
        i)
            DEST_IP=$OPTARG
            ;;
        \?)
            display_help
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument."
            display_help
            exit 1
            ;;
    esac
done


DEST_IPS=($(kubectl get pods -o wide | grep 'client' | awk '{print $6}'))
SERVER_IPS=($(kubectl get pods -o wide | grep 'server' | awk '{print $6}'))
server_pods=($(kubectl get pods | grep 'server' | awk '{print $1}'))

if [ ${#server_pods[@]} -ne ${#DEST_IPS[@]} ]; then
    echo "The number of server pods and destination IPs do not match."
    exit 1
fi

for i in "${!server_pods[@]}"
do
    pod="${server_pods[$i]}"
    dest_ip="${DEST_IPS[$i]}"

    echo "process list on a $pod"
    kubectl exec "$pod" -- ps auxwww

done