#!/bin/bash
# This script start trafgen pod and collect data
# from generator and receiver pod.

# Usage examples:
# run
# -p 10000 10k pps
# -l local pod to pod,  by default it pod to pod server0 - client1, server1 - client1 etc.
# -m run monitor mode will collect metric on RX pods and output to stoud.
# -c use 2 core, by default it 1 core per TX pod.
#
# ./run_monitor_pps.sh -p 10000 -l -m -c 2
#
# Single core loopback pods
# ./run_monitor_pps.sh -p 10000 -l -m
#  Will pick up first core and will use it. single core per generation.
#
# Multicore multi pod ( 2 core per TX pod ) * 3 POD
# ./run_monitor_pps.sh -p 10000 -m -c 2
#
# Author Mus
# mbayramov@vwmware.com

KUBECONFIG_FILE="kubeconfig"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "kubeconfig file not found in the current directory."
    exit 1
fi
export KUBECONFIG="$KUBECONFIG_FILE"

# by default, we run for 128 sec
DEFAULT_TIMEOUT="120"
# default margin added to for monitor. i.e wait all trafgen to stop.
DEFAULT_MONITOR_MARGIN="10"
OPT_PPS=""
OPT_SEC=""
OPT_MONITOR=""
OPT_IS_LOOPBACK=""
NUM_CORES="1"
PACKET_SIZE="64"
DEFAULT_IF_NAME="eth0"

output_dir="metrics"

ETHERNET_HEADER_SIZE=14
IP_HEADER_SIZE=20
UDP_HEADER_SIZE=8
USE_TASKSET="false"

TOTAL_OVERHEAD=$((ETHERNET_HEADER_SIZE + IP_HEADER_SIZE + UDP_HEADER_SIZE))

DEFAULT_PD_SIZE="22"
# default payload size.
PD_SIZE="$DEFAULT_PD_SIZE"
# number of pair TX/RX
DEFAULT_NUM_PAIRS=3

# Function to check args for integer
function validate_integer() {
    local re
    re='^[0-9]+$'
    if ! [[ $1 =~ $re ]] ; then
        echo "Error: Number must must be a positive integer." >&2; exit 1
    fi
}

function calculate_payload_size() {
    local packet_size=$1
    if (( packet_size > TOTAL_OVERHEAD )); then
        PD_SIZE=$((packet_size - TOTAL_OVERHEAD))
    else
        echo "Packet size too small to accommodate headers." >&2
        exit 1
    fi
}

# Function to check that the server-client pairs are running
function check_server_client_pairs() {
    local server_name
    local client_name
    local num_pairs
    num_pairs=$1

    local pod_id
    for pod_id in $(seq 0 $((num_pairs - 1))); do
        server_name="server$pod_id"
        client_name="client$pod_id"
        if [ "$(kubectl get pods | grep -E "$server_name|$client_name" | grep Running | wc -l)" -ne 2 ]; then
            echo "Error: $server_name or $client_name is not running."
            exit 1
        fi
    done

    if [ "$pod_id" -eq "$((num_pairs - 1))" ]; then
        echo "All $num_pairs server-client pairs are running."
    else
        echo "Error: Number of running pod pairs does not match the expected number ($num_pairs) num running ($((pod_id + 1)))."
        exit 1
    fi
}

# Function to generate a range of CPU cores from the physcpubind string
# Arguments: physcpubind_string num_cores
# Example usage: generate_core_range "physcpubind: 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23" 2
function generate_core_range() {

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

# Function to generate a command seperated list of cores
# Arguments: "2-5" will generate 2,3,4,5
function expand_core_range() {
    local core_range=$1
    local start_core
    local end_core

    start_core=$(echo "$core_range" | cut -d'-' -f1)
    end_core=$(echo "$core_range" | cut -d'-' -f2)

    local core_list=""
    for (( core = start_core; core <= end_core; core++ )); do
        if [ -z "$core_list" ]; then
            core_list="$core"
        else
            core_list+=",${core}"
        fi
    done

    echo "$core_list"
}

function display_help() {
    echo "Usage: $0 -p <pps> [-s <seconds>] [-m] [-c <num_cores>] [-n <num_pairs>] [-l] [-r] [-z <packet_size>]"
    echo "Options:"
    echo "  -p <pps>: Specify the packets per second (pps) rate."
    echo "  -s <seconds>: Specify the duration in seconds (default: $DEFAULT_TIMEOUT)."
    echo "  -m: Enable monitoring mode."
    echo "  -c <num_cores>: Specify the number of CPU cores to use (default: $NUM_CORES)."
    echo "  -n <num_pairs>: Specify the number of server-client pairs (default: $DEFAULT_NUM_PAIRS)."
    echo "  -l: Enable loopback mode."
    echo "  -r: Use randomized source port."
    echo "  -z <packet_size>: Specify the packet size in bytes (e.g., 64/128/512/etc)."
    exit 1
}

while getopts ":p:s:mc:n:lrz:" opt; do
    case ${opt} in
        p)
            validate_integer "$OPTARG"
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
            validate_integer "$OPTARG"
            NUM_CORES=$OPTARG
            ;;
        n)
            validate_integer "$OPTARG"
            check_server_client_pairs "$OPTARG"
            DEFAULT_NUM_PAIRS=$OPTARG
            ;;
        l)
            OPT_IS_LOOPBACK="true"
           ;;
        r)
            RANDOMIZED_SRC_PORT="true"
            ;;
        z)
            # we accept 64/128/512 etc.
            validate_integer "$OPTARG"
            PACKET_SIZE=$OPTARG
            calculate_payload_size "$PACKET_SIZE"
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

# loopback ( on same worker node)
target_pod_name="server0"
loopback_pod_name="server1"
client_pod_name="client0"

if [ "$OPT_IS_LOOPBACK" = "true" ]; then
  client_pod_name=$loopback_pod_name
fi

# pod to pod ( inter pod mapping, create two array index is pair)
for ((i=0; i<DEFAULT_NUM_PAIRS; i++)); do
    target_pod_names+=("server$i")
done

for ((i=0; i<DEFAULT_NUM_PAIRS; i++)); do
    client_pod_names+=("client$i")
done

DEFAULT_INIT_PPS=10000
# loopback profile
trafgen_udp_file="/tmp/udp.loopback_$PD_SIZE.trafgen"
trafgen_udp_file2="/tmp/udp_$PD_SIZE.trafgen"

if [ "$RANDOMIZED_SRC_PORT" = "true" ]; then
    trafgen_udp_file2="/tmp/udp_$PD_SIZE.random.trafgen"
fi

target_pod_interface="server0"
uplink_interface="eth0"

# single pod to pod loopback test
tx_pod_name=$(kubectl get pods | grep "$target_pod_name" | awk '{print $1}')
rx_pod_name=$(kubectl get pods | grep "$client_pod_name" | awk '{print $1}')

# Multi pod multi node test
tx_pod_names=()
rx_pod_names=()
for i in "${!target_pod_names[@]}"; do
    tx_pod_names+=($(kubectl get pods | grep "${target_pod_names[$i]}" | awk '{print $1}'))
    rx_pod_names+=($(kubectl get pods | grep "${client_pod_names[$i]}" | awk '{print $1}'))
done

# node address only for a first pair.(server0/client0)
tx_node_name=$(kubectl get pod "$tx_pod_name" -o=jsonpath='{.spec.nodeName}')
rx_node_name=$(kubectl get pod "$rx_pod_name" -o=jsonpath='{.spec.nodeName}')

tx_node_addr=$(kubectl get node "$tx_node_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
rx_node_addr=$(kubectl get node "$rx_node_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

default_core=$(kubectl exec "$tx_pod_name" -- numactl -s | grep 'physcpubind' | awk '{print $2}')
default_core_list=$(kubectl exec "$tx_pod_name" -- numactl -s | grep 'physcpubind')
task_set_core=$default_core

# default_cores array store core per each pod and taskset core range
# here default_cores is index to a pod idx, same for taskset index is pod idx.
default_cores=()
task_set_cores=()
for _tx_pod_name in "${tx_pod_names[@]}"; do
    # list of core on each tx pod, by default we use single core per tx.
    pod_default_core_list=$(kubectl exec "$_tx_pod_name" -- numactl -s | grep 'physcpubind')
    default_core_=$(kubectl exec "$_tx_pod_name" -- numactl -s | grep 'physcpubind' | awk '{print $2}')
    task_set_core_=$default_core_

    # if we need more then 1 core per pod for tx pod
    # task_set_core_ hold a range x-y where x and y lower
    # and upper bound on core range.
    if [ "$NUM_CORES" -gt 1 ]; then
        task_set_core_=$(generate_core_range "$pod_default_core_list" "$NUM_CORES")
        default_core_=$(expand_core_range "$task_set_core_")
    fi

    echo " "
    echo " - Allocated for tx pod $_tx_pod_name cores: $default_core_ taskset cores: $task_set_core_"
    default_cores+=("$default_core_")
    task_set_cores+=("$task_set_core_")
done

printf "\nNode Information:\n"
printf "%-30s %s\n" "TX Node name:" "$tx_node_name"
printf "%-30s %s\n" "TX pod worker address:" "$tx_node_addr"
printf "%-30s %s\n" "RX pod worker address:" "$rx_node_addr"
printf "%-30s %s\n" "Num cores per pod:" "$NUM_CORES"

if [ -z "$tx_pod_name" ] || [ -z "$tx_node_name" ] || [ -z "$default_core" ]; then
    echo "Pod, node, or first core not found"
    exit 1
fi

if [[ "$NUM_CORES" =~ ^[0-9]+$ ]]; then
    NUM_CORES=$((NUM_CORES))
else
    echo "Error: Number of cores must be a positive integer current value $NUM_CORES."
    exit 1
fi

# If the number of cores is greater than 1,
# generate a range of cores
# task_set_core is range 2-4, while default_core is command separated list
if [ "$NUM_CORES" -gt 1 ]; then
    task_set_core=$(generate_core_range "$default_core_list" "$NUM_CORES")
    default_core=$(expand_core_range "$task_set_core")
fi

# Main routine called on start trafgen
function run_trafgen() {
    local pps=$1
    local cmd

    echo "Starting on pod $tx_pod_name core $default_core with $pps pps for ${DEFAULT_TIMEOUT} sec"

    if [ "$USE_TASKSET" == "true" ]; then
        cmd="taskset -c $default_core"
    else
        cmd=""
    fi

    kubectl exec "$tx_pod_name" -- timeout "${DEFAULT_TIMEOUT}s" $cmd /usr/local/sbin/trafgen --cpp --dev "$DEFAULT_IF_NAME" -i "$trafgen_udp_file" --no-sock-mem --rate "${pps}pps" --bind-cpus "$default_core" -V -H > /dev/null 2>&1 &
    trafgen_pid=$!
}


# Main routine for inter-pod multi pod test
function run_trafgen_inter_pod() {
    local pps=$1
    declare -a trafgen_pids

    for i in "${!tx_pod_names[@]}"; do
        local _tx_pod_name="${tx_pod_names[$i]}"
        local _default_core="${default_cores[$i]}"
        local _task_set_core="${task_set_cores[$i]}"
        local opt_cmd
        opt_cmd=""

        echo "Starting on pod $_tx_pod_name with core $_default_core and pps "\
        "$pps for ${DEFAULT_TIMEOUT} sec taskset $_task_set_core dev "\
        "$DEFAULT_IF_NAME profile $trafgen_udp_file2"

        if [ "$USE_TASKSET" == "true" ]; then
            opt_cmd="taskset -c $_task_set_core"
        fi

        kubectl exec "$_tx_pod_name" -- timeout "${DEFAULT_TIMEOUT}s" \
        /usr/local/sbin/trafgen --cpp --dev "$DEFAULT_IF_NAME" -i \
        "$trafgen_udp_file2" --no-sock-mem --rate "${pps}pps" --bind-cpus "$_default_core" -H > /dev/null 2>&1 &

        trafgen_pids+=($!)
    done

    sleep 1
    echo "Checking if all trafgen processes have started..."
    local started_pid
    for started_pid in "${trafgen_pids[@]}"; do
        if ps -p "$started_pid" > /dev/null 2>&1; then
            echo " - Trafgen process with PID $started_pid is running."
        else
            echo "- Trafgen process with PID $started_pid failed to start."
        fi
    done
}


# Function check that each tx and rx
# pod has monitor script, it will print all
# pod where script missing.
function check_monitor_script() {
    local missing_pods=()
    for rx_pod_name in "${rx_pod_names[@]}"; do
        if ! kubectl exec "$rx_pod_name" -- ls /tmp/monitor_pps.sh &> /dev/null; then
            missing_pods+=("$rx_pod_name")
        fi
    done

    if [ "${#missing_pods[@]}" -gt 0 ]; then
        echo "Error: The following receiver pods are missing the monitor script '/tmp/monitor_pps.sh':"
        printf '%s\n' "${missing_pods[@]}"
        exit 1
    else
        echo " "
        echo "All receiver pods have the monitor script '/tmp/monitor_pps.sh'."
    fi
}

# monitor single pod
function run_monitor() {
    echo "Starting monitor pod $tx_pod_name core $default_core"
    kubectl exec "$rx_pod_name" -- timeout "${DEFAULT_MONITOR_TIMEOUT}s" /tmp/monitor_pps.sh -i "$DEFAULT_IF_NAME" -c "$task_set_core"
}

# Execute monitors pps script on all receiver pods
# Each monitor write to own log and function tail all logs
# in same console
function run_monitor_all() {
  for i in "${!rx_pod_names[@]}"; do
     local _rx_pod_name="${rx_pod_names[$i]}"
     local _default_core="${default_cores[$i]}"
     echo "Starting monitor on pod $_rx_pod_name with core $_default_core"
     kubectl exec "$_rx_pod_name" -- timeout "${DEFAULT_MONITOR_TIMEOUT}s" \
     /tmp/monitor_pps.sh -i eth0 > "/tmp/monitor_${_rx_pod_name}.log" 2>&1 &
    done

    local tail_cmd="tail -f"
    for _pod_name_ in "${rx_pod_names[@]}"; do
        tail_cmd+=" /tmp/monitor_${_pod_name_}.log"
    done
    eval "$tail_cmd"
}

# Function collects metric from both sender and receiver
# This for loopback case where both server and receiver deployed on same worker.
# File
function collect_pps_rate() {
    local pps=$1
    local timestamp
    timestamp=$(date +"%Y%m%d%H%M%S")

    local rx_output_file="${output_dir}/rx_${pps}pps_${DEFAULT_TIMEOUT}_core_"\
    "${default_core}_size_${PACKET_SIZE}_${timestamp}.log"

    local tx_output_file="${output_dir}/tx_${pps}pps_${DEFAULT_TIMEOUT}_core_"\
    "${default_core}_size_${PACKET_SIZE}_${timestamp}.log"

    echo "txt $rx_pod_name for core $default_core ${DEFAULT_MONITOR_TIMEOUT} sec with $pps pps for RX direction"

    kubectl exec "$rx_pod_name" -- timeout "${DEFAULT_MONITOR_TIMEOUT}s" \
    /tmp/monitor_pps.sh -i "$DEFAULT_IF_NAME" -d tuple -c "$default_core"> "$rx_output_file" &
    kubectl exec "$tx_pod_name" -- timeout "${DEFAULT_MONITOR_TIMEOUT}s" \
    /tmp/monitor_pps.sh -i "$DEFAULT_IF_NAME" -d tuple -c "$default_core"> "$tx_output_file" &
}

# Function collect stats from all client pods in multi pod config
# generated file per pod on rx side.
function collect_pps_rate_all() {

  local pps=$1
  local num_cores=$2
  local num_pairs=$3

  local client_pods
  local server_pods

  client_pods=($(kubectl get pods | grep 'client' | awk '{print $1}'))
  server_pods=($(kubectl get pods | grep 'server' | awk '{print $1}'))

  local timestamp
  timestamp=$(date +"%Y%m%d%H%M%S")
  local pod_id
  local pod_ith=0
  for pod_id in "${client_pods[@]}"; do
      local target_cores
      local target_cores="${task_set_cores[$pod_ith]}"
      local output_file="${output_dir}/client_${pod_id}_pr_${pps}_runtime_${DEFAULT_TIMEOUT}_cores_${num_cores}_pairs_${num_pairs}_size_${PACKET_SIZE}_core_list_${target_cores}_ts_${timestamp}.log"
      echo "Starting collection from client pod $pod for core "\
      "$target_cores ${DEFAULT_MONITOR_TIMEOUT} sec with $pps pps"

      kubectl exec "$pod_id" -- timeout "${DEFAULT_MONITOR_TIMEOUT}s" \
      /tmp/monitor_pps.sh -i "$DEFAULT_IF_NAME" -d tuple> "$output_file" &
      ((pod_ith++))
  done

  local pod_ith=0
  for pod_id in "${server_pods[@]}"; do
      local target_cores
      local target_cores="${task_set_cores[$pod_ith]}"
      local output_file="${output_dir}/server_${pod_id}_pr_${pps}_runtime_${DEFAULT_TIMEOUT}_cores_${num_cores}_pairs_${num_pairs}_size_${PACKET_SIZE}_core_list_${target_cores}_ts_${timestamp}.log"

      echo "Starting collection from server pod $pod for core "\
      "$target_cores ${DEFAULT_MONITOR_TIMEOUT} sec with $pps pps"

      kubectl exec "$pod_id" -- timeout "${DEFAULT_MONITOR_TIMEOUT}s" \
      /tmp/monitor_pps.sh -i eth0 -d tuple> "$output_file" &
      ((pod_ith++))
  done
}

# Function to get the interface stats from the TX node
function get_geneve_interface_stats() {
    ssh capv@"$tx_node_addr" cat /proc/net/dev | grep 'genev_sys' > "$output_file" &
}

# This a pod interface server0--63ab25
function get_pod_interface_stats() {
    ssh capv@"$tx_node_addr" cat /proc/net/dev | grep $target_pod_name > "$output_file" &
}

# this a pod interface stats for Andrea
function get_antrea_interface_stats() {
    ssh capv@"$tx_node_addr" cat /proc/net/dev | grep antrea-gw0 > "$output_file" &
}

# Function collect queue rate per TX and RX from
# TX and RX worker node
function collect_queue_rates() {
    local pps=$1
    local num_cores=$2
    local num_pairs=$3
    local packet_size=$4

    local timestamp
    timestamp=$(date +"%Y%m%d%H%M%S")

    local tx_queue_output_file="${output_dir}/tx-pod-queue_pr_${pps}_runtime_${DEFAULT_TIMEOUT}_cores_${num_cores}_pairs_${num_pairs}_size_${packet_size}_ts_${timestamp}.log"
    local rx_queue_output_file="${output_dir}/rx-pod-queue_pr_${pps}_runtime_${DEFAULT_TIMEOUT}_cores_${num_cores}_pairs_${num_pairs}_size_${packet_size}_ts_${timestamp}.log"
    local tx_cpu_output_file="${output_dir}/tx-pod-cpu_pr_${pps}_runtime_${DEFAULT_TIMEOUT}_cores_${num_cores}_pairs_${num_pairs}_size_${packet_size}_ts_${timestamp}.log"
    local rx_cpu_output_file="${output_dir}/rx-pod-cpu_pr_${pps}_runtime_${DEFAULT_TIMEOUT}_cores_${num_cores}_pairs_${num_pairs}_size_${packet_size}_ts_${timestamp}.log"
    local tx_soft_net_log="${output_dir}/tx_softnet_stat_${pps}_runtime_${DEFAULT_TIMEOUT}_cores_${num_cores}_pairs_${num_pairs}_size_${packet_size}_ts_${timestamp}.log"
    local rx_soft_net_log="${output_dir}/rx_softnet_stat_${pps}_runtime_${DEFAULT_TIMEOUT}_cores_${num_cores}_pairs_${num_pairs}_size_${packet_size}_ts_${timestamp}.log"

    echo "Collecting queue rates and CPU utilization from workers at $timestamp..."
    ssh capv@"$tx_node_addr" timeout "${DEFAULT_MONITOR_TIMEOUT}s" \
    /bin/bash /tmp/monitor_queue_rate.sh -t queue > "$tx_queue_output_file" 2>&1 &
    ssh capv@"$tx_node_addr" timeout "${DEFAULT_MONITOR_TIMEOUT}s" \
    /bin/bash /tmp/monitor_queue_rate.sh -t cpu > "$tx_cpu_output_file" 2>&1 &

    echo "Collecting queue rates and CPU utilization from workers at $timestamp..."
    ssh capv@"$rx_node_addr" timeout "${DEFAULT_MONITOR_TIMEOUT}s" \
    /bin/bash /tmp/monitor_queue_rate.sh -t queue > "$rx_queue_output_file" 2>&1 &
    ssh capv@"$rx_node_addr" timeout "${DEFAULT_MONITOR_TIMEOUT}s" \
    /bin/bash /tmp/monitor_queue_rate.sh -t cpu > "$rx_cpu_output_file" 2>&1 &

    echo "Collecting soft net statistics from from workers at $timestamp..."
    ssh capv@"$tx_node_addr" timeout "${DEFAULT_MONITOR_TIMEOUT}s" \
    python /tmp/monitor_softnet_stat.py --concise -c > "$tx_soft_net_log" 2>&1 &
    ssh capv@"$rx_node_addr" timeout "${DEFAULT_MONITOR_TIMEOUT}s" \
    python /tmp/monitor_softnet_stat.py --concise -c > "$rx_soft_net_log" 2>&1 &
}

# Function collect interrupt rate per TX and RX
# from each worker node.
function collect_tx_rx_int() {
    local pps=$1
    local num_cores=$2
    local num_pairs=$3
    local packet_size=$4

    local timestamp
    timestamp=$(date +"%Y%m%d%H%M%S")

    local tx_output_file="${output_dir}/tx-pod-int_pr_${pps}_runtime_${DEFAULT_TIMEOUT}_cores_${num_cores}_pairs_${num_pairs}_size_${packet_size}_${timestamp}.log"
    echo "Collecting TX/RX interrupt data from tx_node at $timestamp..."
    ssh capv@"$tx_node_addr" timeout "${DEFAULT_MONITOR_TIMEOUT}s" /bin/bash /tmp/monitor_txrx_int.sh > "$tx_output_file" &

    local rx_output_file="${output_dir}/rx-pod-int_pr_${pps}_runtime_${DEFAULT_TIMEOUT}_cores_${num_cores}_pairs_${num_pairs}_size_${packet_size}_${timestamp}.log"
    echo "Collecting TX/RX interrupt data from rx_node at $timestamp..."
    ssh capv@"$rx_node_addr" timeout "${DEFAULT_MONITOR_TIMEOUT}s" /bin/bash /tmp/monitor_txrx_int.sh > "$rx_output_file" &
}

# this a pod interface stats for uplink
function get_interface_stats() {
    ssh capv@"$tx_node_addr" cat /proc/net/dev | grep "$uplink_interface"
}

# Kill all trafgen pids
function kill_all_trafgen() {
  local pods
  pods=$(kubectl get pods | grep 'server' | awk '{print $1}')
  for pod in $pods; do
    local kubectl_pid
    kubectl_pid=$(ps -ef | grep "kubectl exec $pod" | grep -v grep | awk '{print $2}')
    if [[ -n "$kubectl_pid" ]]; then
      echo "Killing trafgen process in pod $pod with PID(s): $(echo "$kubectl_pid" | tr '\n' ' ')"
      kill "$kubectl_pid" > /dev/null 2>&1 || true
    fi
    local trafgen_pids
    trafgen_pids=$(kubectl exec "$pod" -- pgrep -f trafgen 2>/dev/null)
    if [[ -n "$trafgen_pids" ]]; then
      echo "Killing trafgen process in pod $pod with PID(s): $(echo "$trafgen_pids" | tr '\n' ' ')"
      kubectl exec "$pod" -- pkill -f trafgen > /dev/null 2>&1 || true
    fi
  done
}

# Function allow monitor netdev like eth0/vmxnet3
# during test execution.
function get_and_print_interface_stats() {
    local if_name
    if_name=$1
    interface_stats=$(ssh capv@"$tx_node_addr" cat /proc/net/dev | grep "$if_name")
    echo "$interface_stats" | while read line; do
        iface=$(echo "$line" | awk -F: '{print $1}')
        rx_pkts=$(echo "$line" | awk '{print $3}')  # RX pkt
        rx_drop=$(echo "$line" | awk '{print $5}')  # RX drop is in the 5th column
        tx_pkts=$(echo "$line" | awk '{print $11}') # TX pkt
        tx_drop=$(echo "$line" | awk '{print $13}') # TX drop
        printf "%-20s %10s %15s %10s %15s\n" "$iface" "$rx_drop" "$rx_pkts" "$tx_drop" "$tx_pkts"
    done
}

echo " - Starting $DEFAULT_NUM_PAIRS pair, traffic generator with $OPT_PPS pps for $DEFAULT_TIMEOUT seconds."


DEFAULT_INIT_PPS="$OPT_PPS"
kill_all_trafgen

current_pps="$DEFAULT_INIT_PPS"
# in loopback mode monitor or collect
if [ "$OPT_IS_LOOPBACK" = "true" ]; then
  run_trafgen "$current_pps"
  if [ "$OPT_MONITOR" = "true" ]; then
     run_monitor
  else
     collect_pps_rate "$current_pps"
  fi
else
  # inter-pod monitor or collect.
  check_monitor_script
  run_trafgen_inter_pod "$current_pps"
  if [ "$OPT_MONITOR" = "true" ]; then
     run_monitor_all
  else
     collect_pps_rate_all "$current_pps" "$NUM_CORES" "$DEFAULT_NUM_PAIRS" &
     collect_queue_rates "$current_pps" "$NUM_CORES" "$DEFAULT_NUM_PAIRS" "$PACKET_SIZE" &
     collect_tx_rx_int "$current_pps" "$NUM_CORES" "$DEFAULT_NUM_PAIRS" "$PACKET_SIZE" &
  fi
fi

wait
exit 0
##kill_all_trafgen