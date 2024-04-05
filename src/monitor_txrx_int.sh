#!/bin/bash
# This script sample interrupts for target adapter.
# Note I did not test anything outside vmxnet3.
#
# Author Mus
# mbayramov@vmware.com

OPT_MONITOR=""
INTERVAL=1
interface_name="eth0"

function display_help() {
  echo "Usage: $0 <interface_name> [-i <interface_name>] [-m]"
  echo "This script reads interrupts for the specified network interface and
    displays the cores with interrupts count greater than zero for each eth0-rxtx-X queue."
  echo "Options:"
  echo "  -i <interface_name>: Specify the interface name."
  echo "  -m: Monitor mode. Continuously monitor interrupts."
}

while getopts "mi:" opt; do
    case ${opt} in
        i)
          OPT_IF="$OPTARG"
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

interface_name="$1"

# store list of core for particular rxtx
interrupts_core_array=()
# store list of values > 0
interrupts_val_array=()

# This function populate two array
# First is lis of cores that process particular rxtx queue
# List of actual interrupt that each core did.
#
# Example:
# This what awk produce we have N entities for each rxtx-eth0
#  0 0 0 0 0 0 0 0 0 0 0 2014823 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 243 0
#  0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 989567 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 114
#  0 335 0 0 0 0 0 0 0 65083 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#  0 0 498 0 0 0 0 415183 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#  0 0 0 405 0 1297125 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#  0 0 0 0 85 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 5169530 0 0 0 0 0 0 0
#  0 0 0 0 0 504 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6271816 0 0 0 0 0 0 0 0 0
#  0 0 0 0 0 0 32 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4991357 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
function tx_rx_interrupts() {

  readarray -t cores_array < <(cat /proc/interrupts | awk -v iface="$interface_name" '$0 ~ iface { $1 = ""; sub(/IR-PCI-MSI /, ""); print substr($0, 2, length($0) - 26) }')

  local _out_line
  for _out_line in "${cores_array[@]}"; do

    read -ra values <<<"$_out_line"
    local rxtx_id

    local interrupts=()
    local interrupts_val=()

    for rxtx_id in "${!values[@]}"; do
      local _value
      _value="${values[rxtx_id]}"
      if [ "$_value" -gt 0 ]; then
        interrupts+=("$((rxtx_id + 1))")
        interrupts_val+=("$_value")
      fi
    done

    interrupts_core_array+=("${interrupts[*]}")
    interrupts_val_array+=("${interrupts_val[*]}")
  done
}

# in collect mode we output entire vector with N col
# where col is cpu ID
function collect() {
    readarray -t cores_array < <(cat /proc/interrupts | awk -v iface="$interface_name" '$0 ~ iface { $1 = ""; sub(/IR-PCI-MSI /, ""); print substr($0, 2, length($0) - 26) }')
    for out_line in "${cores_array[@]}"; do
        echo "$out_line"
    done
}

# function monitor interrupts
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

