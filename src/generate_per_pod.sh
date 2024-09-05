#!/bin/bash
set -x
# Generate trafgen config per pod
# This script execute script inside each container
# and populate trafgen files.
#
# - src is base port and each pod offset from that.
# - dst is base port and each pod offset from that.
#
# by default generate for 64 byte packet.
# It also copies monitor_queue to each worker node.
# i.e. script inside a POD need to know dst mac / dst ip etc.
# -r will create profile with randomized src port
# -i payload size. Note not a entire frame size , only payloads size.
#
# Autor:
# Mus mbayramov@vmware.com

POD_NAMESPACE="flexran"

DEFAULT_SRC_PORT="9"
DEFAULT_DST_PORT="6666"

# default pd size on the wire, add all header on top
DEFAULT_PD_SIZE="22"
SRC_PORT="$DEFAULT_SRC_PORT"
DST_PORT="$DEFAULT_DST_PORT"
PD_SIZE="$DEFAULT_PD_SIZE"

target_pod_name="server0"
client_pod_name="client0"

KUBECONFIG_FILE="/etc/rancher/rke2/rke2.yaml"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "kubeconfig file not found in the current directory."
    exit 1
fi
export KUBECONFIG="$KUBECONFIG_FILE"

function validate_integer() {
    local re
    re='^[0-9]+$'
    if ! [[ $1 =~ $re ]] ; then
        echo "Error: Number must must be a positive integer." >&2; exit 1
    fi
}


function display_help() {
    echo "Usage: $0 [-s <source port>] [-d <destination port>] [-r] [-i <payload size>]"
    echo "-s: Source port for UDP traffic"
    echo "-d: Destination port for UDP traffic"
    echo "-r: Regenerate monitor_pps.sh script and push"
    echo "-i: Payload size for UDP packets"
}

function check_kube_connection() {
    if ! kubectl cluster-info &> /dev/null; then
        echo "Error: Unable to connect to the Kubernetes cluster. Please check your connection or kubeconfig settings."
        exit 1
    fi
}

check_kube_connection

function copy_queue_monitor() {
  local tx_node_name
  local rx_node_name
  local tx_node_addr
  local rx_node_addr
  local tx_pod_full_name
  local rx_pod_full_name

  # pod name
  tx_pod_full_name=$(kubectl get pods -n $POD_NAMESPACE | grep "$target_pod_name" | awk '{print $1}')
  rx_pod_full_name=$(kubectl get pods -n $POD_NAMESPACE | grep "$client_pod_name" | awk '{print $1}')

  # node name
  tx_node_name=$(kubectl get pod -n $POD_NAMESPACE "$tx_pod_full_name" -o=jsonpath='{.spec.nodeName}')
  rx_node_name=$(kubectl get pod -n $POD_NAMESPACE "$rx_pod_full_name" -o=jsonpath='{.spec.nodeName}')

  # node address
  tx_node_addr=$(kubectl get node -n $POD_NAMESPACE "$tx_node_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
  rx_node_addr=$(kubectl get node -n $POD_NAMESPACE "$rx_node_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

  echo "Copying monitor_queue_rate script to worker $tx_node_addr"
  scp monitor_queue_rate.sh "root@$tx_node_addr:/tmp/monitor_queue_rate.sh"
  echo "Copying monitor_queue_rate script to worker $rx_node_addr"
  scp monitor_queue_rate.sh "root@$rx_node_addr:/tmp/monitor_queue_rate.sh"
  echo "Copying monitor_txrx_int script to worker $tx_node_addr"
  scp monitor_txrx_int.sh "root@$tx_node_addr:/tmp/monitor_txrx_int.sh"
  echo "Copying monitor_txrx_int script to worker $rx_node_addr"
  scp monitor_txrx_int.sh "root@$rx_node_addr:/tmp/monitor_txrx_int.sh"
  echo "Copying monitor_softnet_stat script to worker $tx_node_addr"
  scp monitor_softnet_stat.py "root@$tx_node_addr:/tmp/monitor_softnet_stat.py"
  echo "Copying monitor_softnet_stat script to worker $rx_node_addr"
  scp monitor_softnet_stat.py "root@$rx_node_addr:/tmp/monitor_softnet_stat.py"
}

regenerate_monitor=false
while getopts ":s:d:ri:" opt; do
    case ${opt} in
        s)
            validate_integer "$OPTARG"
            SRC_PORT=$OPTARG
            ;;
        d)
            validate_integer "$OPTARG"
            DST_PORT=$OPTARG
            ;;
        r)
            regenerate_monitor=true
            ;;
        i)
            validate_integer "$OPTARG"
            PD_SIZE=$OPTARG
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

DEST_IPS=($(kubectl get pods -n $POD_NAMESPACE -l role=client -o jsonpath='{.items[*].status.podIP}'))
SERVER_IPS=($(kubectl get pods -n $POD_NAMESPACE -l role=server -o jsonpath='{.items[*].status.podIP}'))

#DEST_IPS=($(kubectl get pods -o wide | grep 'client' | awk '{print $6}'))
#SERVER_IPS=($(kubectl get pods -o wide | grep 'server' | awk '{print $6}'))

server_pods=($(kubectl get pods -n $POD_NAMESPACE | grep 'server' | awk '{print $1}'))
client_pods=($(kubectl get pods -n $POD_NAMESPACE | grep 'client' | awk '{print $1}'))

validate_ip_array() {
    local ips=("$@")
    local ip_pattern='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    for ip_addr in "${ips[@]}"; do
        if [[ ! $ip_addr =~ $ip_pattern ]]; then
            echo "Invalid IP address detected: $ip_addr"
            return 1
        fi
    done
    return 0
}

if ! validate_ip_array "${DEST_IPS[@]}"; then
    echo "Validation error in DEST_IPS"
    exit 1
fi

if ! validate_ip_array "${SERVER_IPS[@]}"; then
    echo "Validation error in SERVER_IPS"
    exit 1
fi

if [ ${#server_pods[@]} -ne ${#DEST_IPS[@]} ]; then
    echo "The number of server pods and destination IPs do not match."
    exit 1
fi

function copy_pps_monitor() {
  local cid
  for cid in "${!client_pods[@]}"; do
    local client_pod
    client_pod="${client_pods[$cid]}"
    echo "Copying monitor script to $client_pod"
    (
      kubectl cp -n $POD_NAMESPACE monitor_pps.sh "$client_pod":/tmp/monitor_pps.sh
      kubectl exec -n -n $POD_NAMESPACE "$client_pod" -- chmod +x /tmp/monitor_pps.sh
    ) &
  done

  local sid
  for sid in "${!server_pods[@]}"; do
    local server_pod
    server_pod="${server_pods[$sid]}"
    echo "Copying monitor script to $server_pod"
    (
      kubectl cp -n $POD_NAMESPACE monitor_pps.sh "$server_pod":/tmp/monitor_pps.sh
      kubectl exec -n $POD_NAMESPACE "$server_pod" -- chmod +x /tmp/monitor_pps.sh
    ) &
  done
  wait
}

# if regeneration we push monitor only
if "$regenerate_monitor"; then
  copy_pps_monitor
  copy_queue_monitor
  exit 1
fi

# Function to execute commands in parallel in all pods
# It uses array of DEST_IPS which must hold client IP addresses
execute_in_parallel() {
    local pods=("$@")
    local pod_id=0
    local pod
    for pod in "${pods[@]}"; do
          local dst_addr
          dst_addr="${DEST_IPS[$pod_id]}"
          SRC_PORT=$((1024 + pod_id))
          DST_PORT=$((1024 + pod_id))
        (
            kubectl cp -n $POD_NAMESPACE pkt_generate_template.sh "$pod":/tmp/pkt_generate_template.sh
            kubectl exec -n $POD_NAMESPACE "$pod" -- chmod +x /tmp/pkt_generate_template.sh

            kubectl cp -n $POD_NAMESPACE monitor_pps.sh "$pod":/tmp/monitor_pps.sh
            kubectl exec -n $POD_NAMESPACE "$pod" -- chmod +x /tmp/monitor_pps.sh
            kubectl exec -n $POD_NAMESPACE "$pod" -- sh -c "env DEST_IP='$dst_addr' \
            /tmp/pkt_generate_template.sh -p ${PD_SIZE} -s ${SRC_PORT} -d ${DST_PORT} > /tmp/udp_$PD_SIZE.trafgen"
            kubectl exec -n $POD_NAMESPACE "$pod" -- cat /tmp/udp_"$PD_SIZE".trafgen
            # randomized udp flow
            kubectl exec -n $POD_NAMESPACE "$pod" -- sh -c "env DEST_IP='$dst_addr' \
            /tmp/pkt_generate_template.sh -p ${PD_SIZE} -s ${SRC_PORT} -d ${DST_PORT} -r > /tmp/udp_$PD_SIZE.random.trafgen"

            # loopback profile for the first server pod to
            # use the second server pod as destination. ( this executed only once )
            if [ "$pod_id" -eq 0 ]; then
                dest_ip_loopback="${SERVER_IPS[1]}"
                kubectl exec -n $POD_NAMESPACE "$pod" -- sh -c "env DEST_IP='$dest_ip_loopback' \
                /tmp/pkt_generate_template.sh -p ${PD_SIZE} -s ${SRC_PORT} -d ${DST_PORT} > /tmp/udp.loopback_$PD_SIZE.trafgen"
                kubectl exec -n $POD_NAMESPACE "$pod" -- cat /tmp/udp.loopback_"$PD_SIZE".trafgen
            fi
        ) &
        ((pod_id++))
    done
    wait
}

# Function generate traffic profile on each TX pod
# for different frame size
function generate_traffic_profile() {
  local payload_sizes
    payload_sizes=(64 128 256 512 1024)
    local frame_size
    for frame_size in "${payload_sizes[@]}"; do
        echo "Generating profile for frame size ${frame_size} bytes"
        # Ethernet header (14 bytes), IP header (20 bytes), and UDP header (8 bytes)
        local payload_size
        payload_size=$((frame_size - 14 - 20 - 8))
        PD_SIZE="$payload_size"
        execute_in_parallel "${server_pods[@]}"
    done
}

generate_traffic_profile
copy_pps_monitor
copy_queue_monitor