#!/bin/bash

KUBECONFIG_FILE="kubeconfig"
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo "kubeconfig file not found in the current directory."
    exit 1
fi
export KUBECONFIG="$KUBECONFIG_FILE"
kubectl exec -it server0-ve-56377f29-e603-11ee-a122-179ee4765847 /home/ubuntu/byte-unixbench/UnixBench/Run dhry2reg