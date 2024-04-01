#!/bin/bash
# This script start trafgen pod
# and collect data from generator and receiver pod.
# Mus

KUBECONFIG_FILE="kubeconfig"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "kubeconfig file not found in the current directory."
    exit 1
fi
export KUBECONFIG="$KUBECONFIG_FILE"

DEFAULT_TIMEOUT="120"
DEFAULT_MONITOR_MARGIN="10"
OPT_PPS=""
OPT_SEC=""
OPT_MONITOR=""
NUM_CORES="1"
PACKET_SIZE="64"
output_dir="metrics"

DEFAULT_PD_SIZE="22"
PD_SIZE="$DEFAULT_PD_SIZE"

function display_help() {
    echo "Usage: $0 -p <pps> [-s <seconds>] [-m] [-c <num_cores>]"
    echo "Options:"
    echo "  -p <pps>: Specify the packets per second (pps) rate."
    echo "  -s <seconds>: Specify the duration in seconds (default: $DEFAULT_TIMEOUT)."
    echo "  -m: Enable monitoring mode."
    echo "  -c <num_cores>: Specify the number of CPU cores to use (default: $NUM_CORES)."
    exit 1
}

while getopts ":p:s:mc:" opt; do
    case ${opt} in
        p)
            OPT_PPS=$OPTARG
            ;;
        s)
            OPT_SEC=$OPTARG
            if [ -n "$OPT_SEC" ]; then
                DEFAULT_TIMEOUT="$OPT_SEC"
            fi
            ;;
        m)
            OPT_MONITOR="true"
            ;;
        c)
            NUM_CORES=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            display_help
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            display_help
            ;;
    esac
done
shift $((OPTIND -1))

mkdir -p "$output_dir"

if [ -z "$OPT_PPS" ]; then
    echo "Error: Option -p is required." >&2
    exit 1
fi

if [ -z "$OPT_SEC" ]; then
    OPT_SEC="$DEFAULT_TIMEOUT"
fi

DEFAULT_MONITOR_TIMEOUT=$((DEFAULT_TIMEOUT + DEFAULT_MONITOR_MARGIN))

target_pod_name="server0"
client_pod_name="server1"

DEFAULT_INIT_PPS=10000
trafgen_udp_file="/tmp/udp.loopback_$PD_SIZE.trafgen"

target_pod_interface="server0"
uplink_interface="eth0"

tx_pod_name=$(kubectl get pods | grep "$target_pod_name" | awk '{print $1}')
rx_pod_name=$(kubectl get pods | grep "$client_pod_name" | awk '{print $1}')

node_name=$(kubectl get pod "$tx_pod_name" -o=jsonpath='{.spec.nodeName}')
node_ip=$(kubectl get node "$node_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
default_core=$(kubectl exec "$tx_pod_name" -- numactl -s | grep 'physcpubind' | awk '{print $4}')
default_core_list=$(kubectl exec "$tx_pod_name" -- numactl -s | grep 'physcpubind')

if [ -z "$tx_pod_name" ] || [ -z "$node_name" ] || [ -z "$default_core" ]; then
    echo "Pod, node, or first core not found"
    exit 1
fi

if [[ "$NUM_CORES" =~ ^[0-9]+$ ]]; then
    NUM_CORES=$((NUM_CORES))
else
    echo "Error: Number of cores must be a positive integer current value $NUM_CORES."
    exit 1
fi


# Function to generate a range of CPU cores from the physcpubind string
# Arguments: physcpubind_string num_cores
# Example usage: generate_core_range "physcpubind: 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23" 2
generate_core_range() {

    local physcpubind_str=$1
    local num_cores=$2
    local cores=$(echo "$physcpubind_str" | awk -F': ' '{print $2}')

    IFS=' ' read -r -a cores_array <<< "$cores"
    local cores_count=${#cores_array[@]}

    if [ "$num_cores" -lt 1 ] || [ "$num_cores" -gt "$cores_count" ]; then
        echo "Invalid number of cores requested"
        return 1
    fi

    local start_idx=$(( (cores_count - num_cores) / 2 ))
    local end_idx=$(( start_idx + num_cores - 1 ))
    local core_range="${cores_array[$start_idx]}-${cores_array[$end_idx]}"
    echo "$core_range"
}

if [ "$NUM_CORES" -gt 1 ]; then
    default_core=$(generate_core_range "$default_core_list" "$NUM_CORES")
fi

# main routine called on start trafgen
function run_trafgen() {
    local pps=$1
    echo "Starting on pod $tx_pod_name core $default_core with $pps pps for ${DEFAULT_TIMEOUT} sec"
    kubectl exec "$tx_pod_name" -- timeout "${DEFAULT_TIMEOUT}s" /usr/local/sbin/trafgen --cpp --dev eth0 -i "$trafgen_udp_file" --no-sock-mem --rate "${pps}pps" --bind-cpus "$default_core" -V > /dev/null 2>&1 &
    trafgen_pid=$!
}

function run_monitor() {
    echo "Starting monitor pod $tx_pod_name core $default_core"
    kubectl exec "$rx_pod_name" -- timeout "${DEFAULT_MONITOR_TIMEOUT}s" /tmp/monitor_pps.sh eth0 "$default_core"
}

# collect metric from both sender and receiver
function collect_pps_rate() {
    local pps=$1
    local timestamp=$(date +"%Y%m%d%H%M%S")
    local rx_output_file="${output_dir}/rx_${pps}pps_${DEFAULT_TIMEOUT}_core_${default_core}_size_${PACKET_SIZE}_${timestamp}.txt"
    local tx_output_file="${output_dir}/tx_${pps}pps_${DEFAULT_TIMEOUT}_core_${default_core}_size_${PACKET_SIZE}_${timestamp}.txt"
    echo "Starting collection from pod $rx_pod_name for core $default_core ${DEFAULT_MONITOR_TIMEOUT} sec with $pps pps for RX direction"

    kubectl exec "$rx_pod_name" -- timeout "${DEFAULT_MONITOR_TIMEOUT}s" /tmp/monitor_pps.sh eth0 tuple "$default_core"> "$rx_output_file" &
    rx_pod_pid=$!
    kubectl exec "$tx_pod_name" -- timeout "${DEFAULT_MONITOR_TIMEOUT}s" /tmp/monitor_pps.sh eth0 tuple "$default_core"> "$tx_output_file" &
    tx_pod_pid=$!
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

function kill_all_trafgen() {
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

echo "Starting traffic generator with $OPT_PPS pps for $DEFAULT_TIMEOUT seconds on cores $default_core"

DEFAULT_INIT_PPS="$OPT_PPS"
kill_all_trafgen

current_pps="$DEFAULT_INIT_PPS"
run_trafgen "$current_pps"

#
if [ "$OPT_MONITOR" = "true" ]; then
  run_monitor
else
  collect_pps_rate "$current_pps"
fi

wait
##kill_all_trafgen