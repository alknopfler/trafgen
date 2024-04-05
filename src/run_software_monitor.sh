#!/bin/bash
# This script collects soft irq output from sar
#
# Make sure you have tmux
# for mac
#   brew install tmux
#
# Author Mus
# mbayramov@vwmware.com

KUBECONFIG_FILE="kubeconfig"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "kubeconfig file not found in the current directory."
    exit 1
fi
export KUBECONFIG="$KUBECONFIG_FILE"

# loopback ( on same worker node)
target_pod_name="server0"
loopback_pod_name="server1"
client_pod_name="client0"

if [ "$OPT_IS_LOOPBACK" = "true" ]; then
  client_pod_name=$loopback_pod_name
fi

# single pod to pod loopback test
tx_pod_name=$(kubectl get pods | grep "$target_pod_name" | awk '{print $1}')
rx_pod_name=$(kubectl get pods | grep "$client_pod_name" | awk '{print $1}')

# node address only for a first pair.(server0/client0)
tx_node_name=$(kubectl get pod "$tx_pod_name" -o=jsonpath='{.spec.nodeName}')
rx_node_name=$(kubectl get pod "$rx_pod_name" -o=jsonpath='{.spec.nodeName}')

tx_node_addr=$(kubectl get node "$tx_node_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
rx_node_addr=$(kubectl get node "$rx_node_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

tmux new-session -s "soft_irq_monitor" -d -x "$(tput cols)" -y "$(tput lines)" "ssh capv@$tx_node_addr sar -u ALL -P ALL 1"
tmux split-window -vf "ssh capv@$rx_node_addr sar -u ALL -P ALL 1"
tmux attach -t "soft_irq_monitor"
echo "tmux session 'soft_irq_monitor' started."
