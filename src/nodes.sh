#!/bin/bash

KUBECONFIG_FILE="kubeconfig"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "kubeconfig file not found in the current directory."
    exit 1
fi
export KUBECONFIG="$KUBECONFIG_FILE"

node_ips=()

# Function to populate node_ips with unique node IP addresses
function populate_node_ips() {
  local _node_names
  _node_names=$(kubectl get pods -o=jsonpath='{.items[*].spec.nodeName}')
  local _node_ips=()
  for _node_ in $_node_names; do  # Use $_node_names
      local node_ip_addr=$(kubectl get node "$_node_" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
      _node_ips+=("$node_ip_addr")
  done
  local sorted_unique_ips
  sorted_unique_ips=($(echo "${_node_ips[@]}" | tr ' ' '\n' | sort -u))

  node_ips=("${sorted_unique_ips[@]}")
}

populate_node_ips
echo "Unique Node IPs: ${node_ips[@]}"

rx_ring_size=4096
tx_ring_size=4096
rx_mini_ring_size=512

for ip in "${node_ips[@]}"; do
    echo "Running ethtool command on node with IP: $ip"
    ssh capv@"$ip" sudo ethtool -N eth0 rx-flow-hash udp4 sdfn

    echo "Setting ring buffer sizes on node with IP: $ip"
    ssh capv@"$ip" sudo ethtool -G eth0 rx $rx_ring_size tx $tx_ring_size rx-mini $rx_mini_ring_size
    ssh capv@"$ip" sudo apt install numactl
done
