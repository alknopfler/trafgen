#!/bin/bash
# This script sample interrupts for target adapter.
# Note I did not test anything outside VMXNET3.
#
# Author Mus
# mbayramov@vmware.com

OPT_MONITOR=""
INTERVAL=1
#IF_NAME="eth0"
IF_NAME="eth1"
TEST_MODE=false
TEST_FILE="test.int.data"

function display_help() {
  echo "Usage: $0 <interface_name> [-i <interface_name>] [-m]"
  echo "This script reads interrupts for the specified network interface and
    displays the cores with interrupts count greater than zero for each eth0-rxtx-X queue."
  echo "Options:"
  echo "  -i <interface_name>: Specify the interface name."
  echo "  -m: Monitor mode. Continuously monitor interrupts."
  echo "  -t <test_file>: Test mode. Use the specified test file instead of /proc/interrupts."

}

while getopts "mi:t" opt; do
  case ${opt} in
  i)
    IF_NAME="$OPTARG"
    ;;
  m)
    OPT_MONITOR="true"
    ;;
  t)
    TEST_MODE="true"
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
shift $((OPTIND - 1))

if [ "$TEST_MODE" = false ]; then
  ethtool_output=$(command -v ethtool >/dev/null && ethtool -S "$IF_NAME")
  if [[ $? -ne 0 || -z $ethtool_output ]]; then
    echo "Error: Unable to fetch ethtool counters for $IF_NAME."
    exit 1
  fi
fi

# store list of core for particular rxtx
interrupts_core_array=()
# store list of values > 0
interrupts_val_array=()

# This function populate two array
# First is lis of cores that process particular rxtx queue
# List of actual interrupt that each core did.
#
# Example:
# This what awk produce, we have N entities for each rxtx-eth0
#  0 0 0 0 0 0 0 0 0 0 0 2014823 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 243 0
#  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 989567 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 114
#  0 335 0 0 0 0 0 0 0 65083 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#  0 0 498 0 0 0 0 415183 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#  0 0 0 405 0 1297125 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#  0 0 0 0 85 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 5169530 0 0 0 0 0 0 0
#  0 0 0 0 0 504 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6271816 0 0 0 0 0 0 0 0 0
#  0 0 0 0 0 0 32 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4991357 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
function tx_rx_interrupts() {

  if [ "$TEST_MODE" = true ]; then
    if [ ! -f "$TEST_FILE" ]; then
      echo "Error: Test file '$TEST_FILE' not found."
      exit 1
    elif [ ! -s "$TEST_FILE" ]; then
      echo "Error: Test file '$TEST_FILE' is empty."
      exit 1
    fi
    echo "Reading interrupts data from test file: $TEST_FILE"
    read_from="$TEST_FILE"
  else
    echo "Reading interrupts data from /proc/interrupts"
    read_from="/proc/interrupts"
  fi

  interrupts_core_array=()
  interrupts_val_array=()

  local num_cpus
  num_cpus=$(head -n 1 "$read_from" | grep -o 'CPU[0-9]\+' | wc -l)
  num_cpus=$((num_cpus))

  local num_queues
#num_queues=$(grep -c "$IF_NAME-rxtx" "$read_from")
  num_queues=$(grep -c "$IF_NAME-TxRx" "$read_from")
  echo "num_queues: $num_queues"

readarray -t cores_array < <(awk -v iface="$IF_NAME-TxRx" -v num_cpus="$num_cpus" \
    '$0 ~ iface { for (i=2; i<=num_cpus + 1; i++) printf "%s ", $i; printf "\n" }' "$read_from")

  local _out_line

  for _out_line in "${cores_array[@]}"; do
    local values
    read -ra values <<<"$_out_line"
    local rxtx_id

    local interrupts=()
    local interrupts_val=()

    for rxtx_id in "${!values[@]}"; do
      local _value
      _value="${values[rxtx_id]}"
      if [ "$_value" -gt 0 ]; then
        interrupts+=("$rxtx_id")
        interrupts_val+=("$_value")
      fi
    done

    interrupts_core_array+=("${interrupts[*]}")
    interrupts_val_array+=("${interrupts_val[*]}")
  done
}

# Function collect mode we output entire vector with N col
# where col is cpu ID
function collect() {

  if [ "$TEST_MODE" = true ]; then
    if [ ! -f "$TEST_FILE" ]; then
      echo "Error: Test file '$TEST_FILE' not found."
      exit 1
    elif [ ! -s "$TEST_FILE" ]; then
      echo "Error: Test file '$TEST_FILE' is empty."
      exit 1
    fi
    read_from="$TEST_FILE"
  else
    read_from="/proc/interrupts"
  fi

  local num_cpus
  num_cpus=$(head -n 1 "$read_from" | grep -o 'CPU[0-9]\+' | wc -l)
  num_cpus=$((num_cpus))

  local num_queues
  num_queues=$(grep -c "$IF_NAME-TxRx" "$read_from")

  while true; do
    local queue_id=0
    readarray -t cores_array < <(awk -v iface="$IF_NAME-TxRx" -v num_cpus="$num_cpus" \
      '$0 ~ iface { printf "%d ", queue_id++; for (i=2; i<=num_cpus + 1; i++) printf "%s ", $i; printf "\n" }' "$read_from")

    local out_line

    for out_line in "${cores_array[@]}"; do
      echo "$out_line"
    done

    sleep "$INTERVAL"
  done
}

# function monitor interrupts counter for each rxtx queue
# and output adapter interrupts and cpu id per rxtx queue
function monitor() {
  while true; do

    tx_rx_interrupts

    echo "Core IDs:"
    local core_row
    for core_row in "${interrupts_core_array[@]}"; do
      echo "$core_row"
    done

    echo "Values corresponding to Core IDs:"
    local int_val
    for int_val in "${interrupts_val_array[@]}"; do
      echo "$int_val"
    done

    sleep "$INTERVAL"
  done
}

if [ "$OPT_MONITOR" = "true" ]; then
  monitor
else
  collect
fi
