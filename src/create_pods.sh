#!/bin/bash
# Create server and client pods.
# It uses pod template file to populate name node name etc.
# note by default it pick up two node one used for server one for client
# i.e. affinity set in way so server on worker a client on b

# This one for OCP same node
# Mus

KUBECONFIG_FILE="kubeconfig"
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

# number of server-client pair pods
NUM_PAIRS=3

display_help() {
    echo "Usage: $0 [-s] [-i <image>]"
    echo "-s: Deploy client on the same node as server"
    echo "-i: Specify custom image for server and client"
}

while getopts ":si:" opt; do
    case ${opt} in
        s)
            OPT_SAME_NODE="true"
            ;;
        i)
            CUSTOM_IMAGE=$OPTARG
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

if [ ! -z "$CUSTOM_IMAGE" ]; then
    DEFAULT_IMAGE="$CUSTOM_IMAGE"
fi

if [ "$OPT_SAME_NODE" = "false" ]; then
    while IFS= read -r line; do
        nodes+=("$line")
    done < <(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' --no-headers | awk '{print $1}')
    server_node=${nodes[0]}
    client_node=${nodes[1]}
else
    echo "Deploying all pod on same node"
    server_node=$(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' --no-headers | awk 'NR==1{print $1}')
    client_node=$server_node
fi

for i in $(seq 0 $((NUM_PAIRS - 1)))
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

