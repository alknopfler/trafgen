#!/bin/bash

INTERVAL="1"

display_help() {
    echo "Usage: $0"
    echo "This script captures ethtool counters for TX and RX queues of eth0"
}

if [ "$#" -ne 0 ]; then
    display_help
    exit 1
fi

ethtool_output=$(ethtool -S eth0)
if [[ $? -ne 0 || -z $ethtool_output ]]; then
    echo "Error: Unable to fetch ethtool counters for eth0."
    exit 1
fi

while true; do
  ethtool_output=$(ssh capv@198.19.57.175 ethtool -S eth0)
  if [[ $? -ne 0 || -z $ethtool_output ]]; then
      echo "Error: Unable to fetch ethtool counters for eth0."
      exit 1
  fi

  tx_queue_pps_t1=($(echo "$ethtool_output" | awk '/^Tx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts tx:/ { print $4 }'))
  rx_queue_pps_t1=($(echo "$ethtool_output" | awk '/^Rx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts tx:/ { print $4 }'))

  sleep "$INTERVAL"

  ethtool_output=$(ssh capv@198.19.57.175 ethtool -S eth0)
  if [[ $? -ne 0 || -z $ethtool_output ]]; then
      echo "Error: Unable to fetch ethtool counters for eth0."
      exit 1
  fi

  tx_queue_pps_t2=($(echo "$ethtool_output" | awk '/^Tx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts tx:/ { print $4 }'))
  rx_queue_pps_t2=($(echo "$ethtool_output" | awk '/^Rx Queue#: [0-9]+$/ { queue=$3 } /ucast pkts tx:/ { print $4 }'))

  for ((i = 0; i < ${#tx_queue_pps_t2[@]}; i++)); do
    TX_PPS_PER_QUEUE[i]=$((tx_queue_pps_t2[i] - tx_queue_pps_t1[i]))
    RX_PPS_PER_QUEUE[i]=$((rx_queue_pps_t2[i] - rx_queue_pps_t1[i]))
    echo "tx_q $i: ${TX_PPS_PER_QUEUE[i]}, rx_q $i: ${RX_PPS_PER_QUEUE[i]}"
  done

done


