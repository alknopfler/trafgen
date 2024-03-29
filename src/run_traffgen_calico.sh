#!/bin/bash

target_pod_name="server0"
initial_pps=10000

duration=60
interval=10

target_pod_interface="server0"
uplink_interface="eth0"

pod_name=$(kubectl get pods | grep "$target_pod_name" | awk '{print $1}')
node_name=$(kubectl get pod "$pod_name" -o=jsonpath='{.spec.nodeName}')
node_ip=$(kubectl get node "$node_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
first_core=$(kubectl exec "$pod_name" -- numactl -s | grep 'physcpubind' | awk '{print $2}')

if [ -z "$pod_name" ] || [ -z "$node_name" ] || [ -z "$first_core" ]; then
    echo "Pod, node, or first core not found"
    exit 1
fi

function run_trafgen() {
    local pps=$1
    echo "Starting on pod $pod_name core $first_core with $pps pps"
    kubectl exec "$pod_name" -- /usr/local/sbin/trafgen --cpp \
    --dev eth0 -i /tmp/udp.trafgen --no-sock-mem --rate "${pps}pps" --bind-cpus "$first_core" -V > /dev/null 2>&1 &
    trafgen_pid=$!
}

function get_interface_stats() {
    ssh capv@"$node_ip" cat /proc/net/dev | grep 'genev_sys'
}

# this a pod interface server0--63ab25
function get_interface_stats() {
    ssh capv@"$node_ip" cat /proc/net/dev | grep $target_pod_name
}

# this a pod interface stats for antrea
function get_interface_stats() {
    ssh capv@"$node_ip" cat /proc/net/dev | grep antrea-gw0
}

# this a pod interface stats for uplink
function get_interface_stats() {
    ssh capv@"$node_ip" cat /proc/net/dev | grep "$uplink_interface"
}

function kill_all_traff_gens() {
  pods=$(kubectl get pods | grep 'server' | awk '{print $1}')
  for pod in $pods; do
    kubectl_pid=$(ps -ef | grep "kubectl exec $pod" | grep -v grep | awk '{print $2}')
    if [[ -n "$kubectl_pid" ]]; then
      kill "$kubectl_pid" > /dev/null 2>&1
    fi
    pids=$(kubectl exec "$pod" -- pgrep -f trafgen)
    if [[ -n "$pids" ]]; then
      kubectl exec "$pod" -- pkill -f trafgen > /dev/null 2>&1
    fi
  done
}


get_and_print_interface_stats() {
    local interface_name=$1
    interface_stats=$(ssh capv@"$node_ip" cat /proc/net/dev | grep "$interface_name")
    echo "$interface_stats" | while read line; do
        iface=$(echo "$line" | awk -F: '{print $1}')
        rx_pkts=$(echo "$line" | awk '{print $3}')  # RX pkt
        rx_drop=$(echo "$line" | awk '{print $5}')  # RX drop is in the 5th column
        tx_pkts=$(echo "$line" | awk '{print $11}') # TX pkt
        tx_drop=$(echo "$line" | awk '{print $13}') # TX drop
        printf "%-20s %10s %15s %10s %15s\n" "$iface" "$rx_drop" "$rx_pkts" "$tx_drop" "$tx_pkts"
    done
}

kill_all_traff_gens

# Initial run
current_pps=$initial_pps
run_trafgen $current_pps

start_time=$(date +%s)
previous_tx_drop=0

while [ $(($(date +%s) - start_time)) -lt $duration ]; do
    printf "%-20s %10s %15s %10s %15s\n" "Inf" "RX" "RX Drop" "TX" "TX Drop"
    get_and_print_interface_stats $uplink_interface
    get_and_print_interface_stats $target_pod_name

    current_tx_drop=$(echo "$interface_stats" | grep 'genev_sys' | awk '{print $13}')
    current_tx_drop=${current_tx_drop:-0}  # Default to 0 if empty

    echo "Current TX drop: $current_tx_drop, Previous TX drop: $previous_tx_drop"

    if [ "$current_tx_drop" -eq "$previous_tx_drop" ]; then
        echo "TX packet count has not increased, doubling PPS"
        ((current_pps*=2))
        kill_all_traff_gens
        sleep 1
        run_trafgen "$current_pps"
        start_time=$(date +%s)
    fi

    previous_tx_drop=$current_tx_drop
    sleep $interval
done

echo "Stopping trafgen process"
kubectl exec "$pod_name" -- kill $trafgen_pid
