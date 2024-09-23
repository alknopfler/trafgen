#!/bin/bash
# I use this script to create server and client pods. It read template file for
# two POD template files, and it set target image, and other parameters
# for a pod.
#
# Note it doesn't read default KUBECONFIG to avoid dodgy case.
# Hence, put kubeconfig in same spot where is script.
#
# Note It uses pod template file to populate name node name etc.
# note by default it pick up two node one used for server
# one for client i.e. affinity set in way so server on worker a client on b
# if pass arg it will deploy all pod on same node.
#
# Note: by default it doesn't use control you can remove that check if needed.
#
# -c arg set CPU, -n num pairs.

# In case we have worker node and control plane node, on same node.
# Use -s flag so all pods deployed on same node.
#
# Author Mus
# mbayramov@vmware.com

KUBECONFIG_FILE="/etc/rancher/rke2/rke2.yaml"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "kubeconfig file not found in the current directory."
    exit 1
fi
export KUBECONFIG="$KUBECONFIG_FILE"

# cleanup
kubectl get pods -o=name | grep -E 'client|server' | xargs kubectl delete

# defaults
mkdir -p pods

# default per pod.
DEFAULT_CPU_LIMIT="4"
DEFAULT_MEM_LIMIT="4000Mi"
DEFAULT_CPU_REQ="4"
DEFAULT_MEM_REQ="4000Mi"
DEFAULT_IMAGE="voereir/touchstone-server-ubuntu:v3.11.1"
OPT_SAME_NODE=false

# Number of TX-RX pair pods
DEFAULT_NUM_PAIRS=3

function display_help() {
    echo "Usage: $0 [-s] [-i <image>] [-n <num_pairs>]"
    echo "-s: Deploy client on the same node as the server"
    echo "-i: Specify a custom image for the server and client (default: $DEFAULT_IMAGE)"
    echo "-c: Specify the CPU limit for each pod (default: $DEFAULT_CPU_LIMIT)"
    echo "-n: Specify the number of server-client pairs (default: $DEFAULT_NUM_PAIRS)"
    echo "-m: Specify the memory limit for each pod in MiB (default: $DEFAULT_MEM_LIMIT)"
}

function validate_integer() {
    local re
    re='^[0-9]+$'
    if ! [[ $1 =~ $re ]] ; then
        echo "Error: Number must must be a positive integer." >&2; exit 1
    fi
}

while getopts ":si:n:c:m:" opt; do
    case ${opt} in
        s)
            OPT_SAME_NODE="true"
            ;;
        i)
            CUSTOM_IMAGE=$OPTARG
            ;;
        n)
            validate_integer "$OPTARG"
            DEFAULT_NUM_PAIRS=$OPTARG
            ;;
        c)
            validate_integer "$OPTARG"
            DEFAULT_CPU_LIMIT=$OPTARG
            DEFAULT_CPU_REQ=$DEFAULT_CPU_LIMIT
            ;;
        m)
            validate_integer "$OPTARG"
            DEFAULT_MEM_LIMIT="${OPTARG}Mi"
            DEFAULT_MEM_REQ=$DEFAULT_MEM_LIMIT
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

shift $((OPTIND -1))

echo -e "Pod Configuration Information:\n\
Memory Limit:\t\t$DEFAULT_MEM_LIMIT\n\
Memory Request:\t\t$DEFAULT_MEM_REQ\n\
CPU Request:\t\t$DEFAULT_CPU_REQ\n\
CPU Limit:\t\t$DEFAULT_CPU_LIMIT\n\
Number of Server-Client Pairs:\t$DEFAULT_NUM_PAIRS"


if [ ! -z "$CUSTOM_IMAGE" ]; then
    DEFAULT_IMAGE="$CUSTOM_IMAGE"
fi

if [ "$OPT_SAME_NODE" = "false" ]; then
    while IFS= read -r line; do
        nodes+=("$line")
    done < <(kubectl get nodes --no-headers | awk '{print $1}')
    server_node=${nodes[0]}
    client_node=${nodes[1]}
else
    echo "Deploying all pod on same node"
    server_node=$(kubectl get nodes --selector='node-role.kubernetes.io/control-plane' --no-headers | awk 'NR==1{print $1}')
    client_node=$server_node
fi

for i in $(seq 0 $((DEFAULT_NUM_PAIRS - 1)))
do
    server_name="server$i"
    client_name="client$i"

    sed "s|{{server-name}}|$server_name|g; s|{{node-name}}|$server_node|g; s|{{cpu-limit}}|$DEFAULT_CPU_LIMIT|g; s|{{memory-limit}}|$DEFAULT_MEM_LIMIT|g; s|{{cpu-request}}|$DEFAULT_CPU_REQ|g; s|{{memory-request}}|$DEFAULT_MEM_REQ|g; s|{{image}}|$DEFAULT_IMAGE|g" pod-server-template.yaml > "pods/pod-$server_name.yaml"

    if [ "$OPT_SAME_NODE" = "true" ]; then
        TEMPLATE_FILE="pod-client-template-same_node.yaml"
    else
        TEMPLATE_FILE="pod-client-template.yaml"
    fi

    sed "s|{{client-name}}|$client_name|g; s|{{node-name}}|$client_node|g; s|{{server-name}}|$server_name|g; s|{{cpu-limit}}|$DEFAULT_CPU_LIMIT|g; s|{{memory-limit}}|$DEFAULT_MEM_LIMIT|g; s|{{cpu-request}}|$DEFAULT_CPU_REQ|g; s|{{memory-request}}|$DEFAULT_MEM_REQ|g; s|{{image}}|$DEFAULT_IMAGE|g" $TEMPLATE_FILE > "pods/pod-$client_name.yaml"

    kubectl apply -f "pods/pod-$server_name.yaml"
    kubectl apply -f "pods/pod-$client_name.yaml"
done

