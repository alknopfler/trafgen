#!/bin/bash
# Create server and client pods.
# It uses pod template file to populate name node name etc.
# note by default it pick up two node one used for server one for client
# i.e. affinity set in way so server on worker a client on b
# Mus

# by default expect same dir

export KUBECONFIG="kubeconfig"
mkdir -p pods

cpu_limit="4"
memory_limit="4000Mi"
cpu_request="4"
memory_request="4000Mi"


while IFS= read -r line; do
    nodes+=("$line")
done < <(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' --no-headers | awk '{print $1}')

server_node=${nodes[0]}
client_node=${nodes[1]}

num_pods=3
for i in $(seq 0 $((num_pods - 1)))
do
    server_name="server$i"
    client_name="client$i"
    #
    sed "s/{{server-name}}/$server_name/g; s/{{node-name}}/$server_node/g; s/{{cpu-limit}}/$cpu_limit/g; s/{{memory-limit}}/$memory_limit/g; s/{{cpu-request}}/$cpu_request/g; s/{{memory-request}}/$memory_request/g" pod-server-template.yaml > "pods/pod-$server_name.yaml"
    sed "s/{{client-name}}/$client_name/g; s/{{node-name}}/$client_node/g; s/{{server-name}}/$server_name/g; s/{{cpu-limit}}/$cpu_limit/g; s/{{memory-limit}}/$memory_limit/g; s/{{cpu-request}}/$cpu_request/g; s/{{memory-request}}/$memory_request/g" pod-client-template.yaml > "pods/pod-$client_name.yaml"

    kubectl apply -f "pods/pod-$server_name.yaml"
    kubectl apply -f "pods/pod-$client_name.yaml"
done
