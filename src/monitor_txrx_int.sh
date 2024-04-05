#!/bin/bash

function display_help() {
  echo "Usage: $0 <interface_name>"
  echo "This script reads interrupts for the specified network interface and
    displays the cores with interrupts count greater than zero for each eth0-rxtx-X queue."
}

if [ "$#" -ne 1 ]; then
  display_help
  exit 1
fi

interface_name="$1"
readarray -t cores_array < <(cat /proc/interrupts | awk -v iface="$interface_name" '$0 ~ iface { $1 = ""; sub(/IR-PCI-MSI /, ""); print substr($0, 2, length($0) - 26) }')

# store list of core for particular rxtx
interrupts_core_array=()
# store list of values > 0
interrupts_val_array=()

# This function populate two array
# First is lis of cores that process particular rxtx queue
# List of actual interrupt that each core did.
# Example:
# This what awk produce we have N entities for each rxtx-eth0
#0 0 0 0 0 0 0 0 0 0 0 2014823 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 243 0
#0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 989567 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 114
#0 335 0 0 0 0 0 0 0 65083 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#0 0 498 0 0 0 0 415183 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#0 0 0 405 0 1297125 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
#0 0 0 0 85 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 5169530 0 0 0 0 0 0 0
#0 0 0 0 0 504 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 6271816 0 0 0 0 0 0 0 0 0
#0 0 0 0 0 0 32 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 4991357 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
function tx_rx_interrupts() {

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


tx_rx_interrupts

echo "Core IDs:"
for row in "${interrupts_core_array[@]}"; do
  echo "$row"
done

echo "Values corresponding to Core IDs:"
for val in "${interrupts_val_array[@]}"; do
  echo "$val"
done


