#!/bin/bash
# Generate trafgen config per pod
# This script execute script inside each container and populate two trafgen files.
# i.e. script inside a POD need to know dst mac / dst ip etc.
# Mus mbayramov@vmware.com

KUBECONFIG_FILE="kubeconfig"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "kubeconfig file not found in the current directory."
    exit 1
fi
export KUBECONFIG="$KUBECONFIG_FILE"

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

    echo "Copying udp template generator to $pod"
    kubectl cp pkt_generate_template.sh "$pod":/tmp/pkt_generate_template.sh
    kubectl exec "$pod" -- chmod +x /tmp/pkt_generate_template.sh

    kubectl cp monitor_pps.sh "$pod":/tmp/monitor_pps.sh
    kubectl exec "$pod" -- chmod +x /tmp/monitor_pps.sh

    echo "Executing udp template generator on $pod with pod DEST_IP=$dest_ip"
    kubectl exec "$pod" -- sh -c "env DEST_IP='$dest_ip' /tmp/pkt_generate_template.sh > /tmp/udp.trafgen"
    echo "Contents of /tmp/udp.trafgen on $pod:"
    kubectl exec "$pod" -- cat /tmp/udp.trafgen

    # loopback profile for the first server
    # pod to use the second server pod as destination
    if [ "$i" -eq 0 ]; then
        dest_ip_loopback="${SERVER_IPS[1]}"
        echo "Executing loopback profile on $pod with pod DEST_IP=$dest_ip_loopback"
        kubectl exec "$pod" -- sh -c "env DEST_IP='$dest_ip_loopback' /tmp/pkt_generate_template.sh > /tmp/udp.loopback.trafgen"
        echo "Contents of /tmp/udp.loopback.trafgen on $pod:"
        kubectl exec "$pod" -- cat /tmp/udp.loopback.trafgen
    fi
done

