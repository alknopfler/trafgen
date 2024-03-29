#!/bin/bash
# Create server and client pods.
# It uses pod template file to populate name node name etc.
# note by default it pick up two node one used for server one for client
# i.e. affinity set in way so server on worker a client on b

# This one for OCP same node
# Mus

export KUBECONFIG="kubeconfig"

# cleanup
kubectl get pods -o=name | grep -E 'client|server' | xargs kubectl delete

# defaults
mkdir -p pods

# default per pod.
DEFAULT_CPU_LIMIT="4"
DEFAULT_MEM_LIMIT="4000Mi"
DEFAULT_CPU_REQ="4"
DEFAULT_MEM_REQ="4000Mi"

# number of server-client pair pods
NUM_PAIRS=3

server_node=${nodes[0]}
client_node=${nodes[1]}

for i in $(seq 0 $((NUM_PAIRS - 1)))
do
    server_name="server$i"
    client_name="client$i"
    #
    sed "s/{{server-name}}/$server_name/g; s/{{node-name}}/$server_node/g; s/{{cpu-limit}}/$DEFAULT_CPU_LIMIT/g; s/{{memory-limit}}/$DEFAULT_MEM_LIMIT/g; s/{{cpu-request}}/$DEFAULT_CPU_REQ/g; s/{{memory-request}}/$DEFAULT_MEM_REQ/g" pod-server-template.yaml > "pods/pod-$server_name.yaml"
    sed "s/{{client-name}}/$client_name/g; s/{{node-name}}/$client_node/g; s/{{server-name}}/$server_name/g; s/{{cpu-limit}}/$DEFAULT_CPU_LIMIT/g; s/{{memory-limit}}/$DEFAULT_MEM_LIMIT/g; s/{{cpu-request}}/$DEFAULT_CPU_REQ/g; s/{{memory-request}}/$DEFAULT_MEM_REQ/g" pod-client-template-samenode.yaml > "pods/pod-$client_name.yaml"

    kubectl apply -f "pods/pod-$server_name.yaml"
    kubectl apply -f "pods/pod-$client_name.yaml"
done
