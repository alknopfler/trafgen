#!/bin/bash
# This script sample TX and RX queue pkt per second (pps)
# counters of adapter the main purpose identify imbalance
# either on TX or RX.
#
# It also sample CPU utilization per core.
#
# generate per pod script will copy this script to each
# worker node under /tmp during run we execute
# this script and sample.
#
# Author Mus
# mbayramov@vmware.com

OPT_MONITOR=""
SAMPLE_INTERVAL=1
#IF_NAME="eth0"
IF_NAME="eth1"
MODE="all"

# Function to display usage help
function display_help() {
    echo "Usage: $0 [-i interface_name] [-m] [-t type]"
    echo "Options:"
    echo "  -i <interface_name>: Specify the interface name."
    echo "  -m: Monitor mode. Continuously monitor."
    echo "  -t <type>: Type of data to collect (queue, cpu, all)."
}

# Parse command-line options
while getopts "mi:t:" opt; do
    case ${opt} in
        i)
            IF_NAME="$OPTARG"
            ;;
        m)
            OPT_MONITOR="true"
            ;;
        t)
            MODE="$OPTARG"
            ;;
        \? | *)
            display_help
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

_eth_output=$(ethtool -S "$IF_NAME")
if [[ $? -ne 0 || -z $_eth_output ]]; then
    echo "Error: Unable to fetch ethtool counters for $IF_NAME."
    exit 1
fi

declare -a TX_PPS_PER_QUEUE
declare -a RX_PPS_PER_QUEUE
declare -a TX_DROPS_PER_QUEUE
declare -a RX_DROPS_PER_QUEUE
declare -a TX_RING_FULL_PER_QUEUE
declare -a RX_RING_FULL_PER_QUEUE

# function sample pps rate for each queue
# output read from ethtool
function sample_queue_rates() {
  # sample ucast pkts tx/rx per queue each sample time
  # calculate rate per queue
  while true; do

    _eth_output=$(ethtool -S "$IF_NAME")
    if [[ $? -ne 0 || -z $_eth_output ]]; then
      echo "Error: Unable to fetch ethtool counters for eth0."
      exit 1
    fi

    # sample for T1
    local tx_queue_pps_t1
    local rx_queue_pps_t1
    tx_queue_pps_t1=($(echo "$_eth_output" | awk '/^Tx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts tx:/ { print $4 }'))
    rx_queue_pps_t1=($(echo "$_eth_output" | awk '/^Rx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts rx:/ { print $4 }'))

    local tx_queue_drops_t1
    local rx_queue_drops_t1
    tx_queue_drops_t1=($(echo "$_eth_output" | awk '/^Tx Queue#: [0-9]+$/ { queue=$3 } /tx dropped:/ { print $4 }'))
    rx_queue_drops_t1=($(echo "$_eth_output" | awk '/^Rx Queue#: [0-9]+$/ { queue=$3 } /rx dropped:/ { print $4 }'))

    local tx_queue_ring_full_t1
    local rx_queue_ring_full_t1
    tx_queue_ring_full_t1=($(echo "$_eth_output" | awk '/^Tx Queue#: [0-9]+$/ { queue=$3 } /tx ring full:/ { print $4 }'))
    rx_queue_ring_full_t1=($(echo "$_eth_output" | awk '/^Rx Queue#: [0-9]+$/ { queue=$3 } /rx ring full:/ { print $4 }'))

    sleep "$SAMPLE_INTERVAL"

    # update
    _eth_output=$(ethtool -S "$IF_NAME")
    if [[ $? -ne 0 || -z $_eth_output ]]; then
      echo "Error: Unable to fetch ethtool counters for $IF_NAME."
      exit 1
    fi

    local tx_queue_drops_t2
    local rx_queue_drops_t2

    tx_queue_drops_t2=($(echo "$_eth_output" | awk '/^Tx Queue#: [0-9]+$/ { queue=$3 } /tx dropped:/ { print $4 }'))
    rx_queue_drops_t2=($(echo "$_eth_output" | awk '/^Rx Queue#: [0-9]+$/ { queue=$3 } /rx dropped:/ { print $4 }'))

    local tx_queue_ring_full_t2
    local rx_queue_ring_full_t2
    tx_queue_ring_full_t2=($(echo "$_eth_output" | awk '/^Tx Queue#: [0-9]+$/ { queue=$3 } /tx ring full:/ { print $4 }'))
    rx_queue_ring_full_t2=($(echo "$_eth_output" | awk '/^Rx Queue#: [0-9]+$/ { queue=$3 } /rx ring full:/ { print $4 }'))

    # sample for T2
    local tx_queue_pps_t2
    local rx_queue_pps_t2
    tx_queue_pps_t2=($(echo "$_eth_output" | awk '/^Tx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts tx:/ { print $4 }'))
    rx_queue_pps_t2=($(echo "$_eth_output" | awk '/^Rx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts rx:/ { print $4 }'))

    # in case of VMXNET3 we have num RX queue and TX queue are the same
    # default it 8, thus we should have 8 elements in each array
    if [ "${#tx_queue_pps_t1[@]}" -ne "${#tx_queue_pps_t2[@]}" ] || \
       [ "${#rx_queue_pps_t1[@]}" -ne "${#rx_queue_pps_t2[@]}" ] || \
       [ "${#tx_queue_pps_t1[@]}" -ne "${#rx_queue_pps_t1[@]}" ]; then
       echo "Error: Array sizes are not consistent."
       exit 1
    fi

    local i
    for ((i = 0; i < ${#tx_queue_pps_t2[@]}; i++)); do
      TX_PPS_PER_QUEUE[i]=$((tx_queue_pps_t2[i] - tx_queue_pps_t1[i]))
      RX_PPS_PER_QUEUE[i]=$((rx_queue_pps_t2[i] - rx_queue_pps_t1[i]))
      TX_DROPS_PER_QUEUE[i]=$((tx_queue_drops_t2[i] - tx_queue_drops_t1[i]))
      RX_DROPS_PER_QUEUE[i]=$((rx_queue_drops_t2[i] - rx_queue_drops_t1[i]))
      TX_RING_FULL_PER_QUEUE[i]=$((tx_queue_ring_full_t2[i] - tx_queue_ring_full_t1[i]))
      RX_RING_FULL_PER_QUEUE[i]=$((rx_queue_ring_full_t2[i] - rx_queue_ring_full_t1[i]))
    done

    if [ -n "$OPT_MONITOR" ]; then
      echo "tx_q: ${TX_PPS_PER_QUEUE[*]}"
      echo "rx_q: ${RX_PPS_PER_QUEUE[*]}"
    else
      echo "${TX_PPS_PER_QUEUE[*]} ${RX_PPS_PER_QUEUE[*]} ${TX_DROPS_PER_QUEUE[*]} ${RX_DROPS_PER_QUEUE[*]} ${TX_RING_FULL_PER_QUEUE[*]} ${RX_RING_FULL_PER_QUEUE[*]}"
    fi
   done
}

# Function output vector of CPU utilization
# index position is cpu id.
function sample_cpu_utilization() {
    while true; do
        local cpu_times_t1=($(awk '/^cpu[0-9]/ {print $2+$3+$4+$5+$6+$7+$8+$9+$10, $5}' /proc/stat))

        sleep "$SAMPLE_INTERVAL"

        local cpu_times_t2=($(awk '/^cpu[0-9]/ {print $2+$3+$4+$5+$6+$7+$8+$9+$10, $5}' /proc/stat))

        local cpu_utilization=()
        for ((i=0; i<${#cpu_times_t1[@]}; i+=2)); do
            local total_time_t1=${cpu_times_t1[i]}
            local idle_time_t1=${cpu_times_t1[i+1]}
            local total_time_t2=${cpu_times_t2[i]}
            local idle_time_t2=${cpu_times_t2[i+1]}

            local total_diff=$((total_time_t2 - total_time_t1))
            local idle_diff=$((idle_time_t2 - idle_time_t1))

            if [ "$total_diff" -gt 0 ]; then
                local cpu_usage=$((100 * (total_diff - idle_diff) / total_diff))
                cpu_utilization+=($cpu_usage)
            else
                cpu_utilization+=(0)
            fi
        done

        echo "${cpu_utilization[*]}"
    done
}

case $MODE in
    queue)
        sample_queue_rates
        ;;
    cpu)
        sample_cpu_utilization
        ;;
    all)
        sample_queue_rates
        sample_cpu_utilization
        ;;
    *)
        echo "Invalid mode selected."
        display_help
        exit 1
        ;;
esac

