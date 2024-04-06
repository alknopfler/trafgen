#!/bin/bash
# This script sample TX and RX queue pkt per second (pps)
# counters of adapter the main purpose identify imbalance
# either on TX or RX.
#
# generate per pod script will copy this script to each
# worker node under /tmp during run we execute
# this script and sample.
#
# Author Mus
# mbayramov@vmware.com

OPT_MONITOR=""
SAMPLE_INTERVAL=1
IF_NAME="eth0"

function display_help() {
    echo "Usage: $0"
    echo "This script captures ethtool counters for TX and RX queues of eth0"
    echo "  -i <interface_name>: Specify the interface name."
    echo "  -m: Monitor mode. Continuously monitor interrupts."
}

while getopts "mi:" opt; do
  case ${opt} in
    i)
      IF_NAME="$OPTARG"
      ;;
    m)
      OPT_MONITOR="true"
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

_eth_output=$(ethtool -S "$IF_NAME")
if [[ $? -ne 0 || -z $_eth_output ]]; then
    echo "Error: Unable to fetch ethtool counters for $IF_NAME."
    exit 1
fi

declare -a TX_PPS_PER_QUEUE
declare -a RX_PPS_PER_QUEUE

function sample_pps() {
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
    declare -a tx_queue_pps_t1
    tx_queue_pps_t1=($(echo "$_eth_output" | awk '/^Tx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts tx:/ { print $4 }'))
    local rx_queue_pps_t1
    rx_queue_pps_t1=($(echo "$_eth_output" | awk '/^Rx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts tx:/ { print $4 }'))

    sleep "$SAMPLE_INTERVAL"

    _eth_output=$(ethtool -S "$IF_NAME")
    if [[ $? -ne 0 || -z $_eth_output ]]; then
      echo "Error: Unable to fetch ethtool counters for eth0."
      exit 1
    fi

    # sample for T2
    local tx_queue_pps_t2
    tx_queue_pps_t2=($(echo "$_eth_output" | awk '/^Tx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts tx:/ { print $4 }'))
    local rx_queue_pps_t2
    rx_queue_pps_t2=($(echo "$_eth_output" | awk '/^Rx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts tx:/ { print $4 }'))

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
    done

    if [ -n "$OPT_MONITOR" ]; then
      echo "tx_q: ${TX_PPS_PER_QUEUE[*]}"
      echo "rx_q: ${RX_PPS_PER_QUEUE[*]}"
    else
      echo "${TX_PPS_PER_QUEUE[*]} ${RX_PPS_PER_QUEUE[*]}"
    fi

   done
}

sample_pps

