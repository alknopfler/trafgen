#!/bin/bash
# This script take path to private key i.e a key that require
# to connect to worker / controller node.
# for example VMware TKG uses by default a key that push to all nodes.
# This one get all worker node get IP of nodes and add in ssh/config private key, so you don't need
# pass. path to private key when you need ssh to a node.

# a path to private key and username TKG used capv
IDENTITY_FILE="id_rsa.private"
SSH_USER="capv"
SSH_CONFIG="$HOME/.ssh/config"

INTERNAL_IPS=$(kubectl get nodes -A -o wide | awk 'NR>1 {print $6}')

cp "$SSH_CONFIG" "$SSH_CONFIG.backup"

add_host_to_ssh_config() {
    local ip=$1
    if ! grep -q "Host $ip" "$SSH_CONFIG"; then
        echo -e "Host $ip\n  IdentityFile $IDENTITY_FILE\n  User $SSH_USER\n" >> "$SSH_CONFIG"
    fi
}

for ip in $INTERNAL_IPS; do
    add_host_to_ssh_config "$ip"
done

echo "Updated .ssh/config:"
cat "$SSH_CONFIG"
