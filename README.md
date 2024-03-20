# trafgen
set of bash script to create N pods to generate NxN UDP between pods

First, we copy a script that will produce a pod-specific C struct that is later consumed by traffic.
It is done for all pods that generate traffic.

First, we generate templates per each pod, that will populate
src mac / dst mac in header and src IP ( whatever pod has on eth0 )

In phase two, we get all client IPs, i.e, client pod or anything else 
that can count. 

For now it NxN 

```bash
#!/bin/bash
# Generate udp trafgen config per pod
# - get own IP req for IP header
# - resolve default gateway and send two pings so the arp cache populate
# - parse so we get dst mac
# - take your own src mac and unpack byte populate in a template
# create C struct
# generate and show in the console so we can verify
# Mus mbayramov@vmware.com

# Extract each byte from mac addr and return as comma separate str
get_src_ip_components() {
    ifconfig eth0 | grep 'inet ' | awk '{print $2}' | \
    awk -F '.' '{printf("%d, %d, %d, %d", $1, $2, $3, $4)}'
}

# Extract MAC address from ifconfig for eth0
get_mac_eth0() {
    ifconfig eth0 | grep 'ether ' | awk '{print $2}' | \
    awk -F ':' '{printf("0x%s, 0x%s, 0x%s, 0x%s, 0x%s, 0x%s", $1, $2, $3, $4, $5, $6)}'
}

# ping gw, do arping , get gateway mac addr
# create string i.e byte command seperated
get_gateway_mac() {
    local gateway_ip=$(ip route | grep default | awk '{print $3}')
    ping -c 2 "$gateway_ip" > /dev/null
    arping -c 1 -I eth0 "$gateway_ip" > /dev/null
    arp -n | awk -v gw="$gateway_ip" '$1 == gw {print $3}' | \
    head -n 1 | awk -F ':' '{printf("0x%s, 0x%s, 0x%s, 0x%s, 0x%s, 0x%s", $1, $2, $3, $4, $5, $6)}'
}

# generate config
generate_config() {
    local dst_ip="$DEST_IP"
    local dst_ip_arr=($(echo "$dst_ip" | tr '.' ' '))
    echo "#define ETH_P_IP 0x0800"
    echo "{"
    get_gateway_mac
    echo ","
    get_mac_eth0
    echo ","
    echo "const16(ETH_P_IP),"
    echo "0b01000101, 0,  /* IPv4 Version, IHL, TOS */"
    echo "const16(46),    /* IPv4 Total Len (UDP len + IP hdr 20 bytes)*/"
    echo "const16(2),     /* IPv4 Ident */"
    echo "0b01000000, 0,  /* IPv4 Flags, Frag Off */"
    echo "64,             /* IPv4 TTL */"
    echo "17,             /* Proto UDP */"
    echo "csumip(14, 33), /* IPv4 Checksum (IP header from, to) */"
    get_src_ip_components
    echo ","
    echo "${dst_ip_arr[0]}, ${dst_ip_arr[1]}, ${dst_ip_arr[2]}, ${dst_ip_arr[3]},"
    echo "const16(9),    /* UDP Source Port e.g. drnd(2)*/"
    echo "const16(6666), /* UDP Dest Port */"
    echo "const16(26),   /* UDP length (UDP hdr 8 bytes + payload size */"
    echo "const16(0),"
    echo "fill('B', 18),"
    echo "}"
}

generate_config
```

We run this script, and it runs generates_per_pod.sh on each pod.
That results in /tmp/udp.trafgen  file that we can use on each pod to 
generate.

```bash
#!/bin/bash
# Generate trafgen config per pod
# Mus mbayramov@vmware.com

DEST_IPS=($(kubectl get pods -o wide | grep 'client' | awk '{print $6}'))
server_pods=($(kubectl get pods | grep 'server' | awk '{print $1}'))

if [ ${#server_pods[@]} -ne ${#DEST_IPS[@]} ]; then
    echo "The number of server pods and destination IPs do not match."
    exit 1
fi

# Loop  each server, generate cpp spec, run cat for review
for i in "${!server_pods[@]}"
do
    pod="${server_pods[$i]}"
    dest_ip="${DEST_IPS[$i]}"

    echo "Copying script to $pod"
    kubectl cp traff_spec.sh "$pod":/tmp/generate_per_pod.sh
    kubectl exec "$pod" -- chmod +x /tmp/generate_per_pod.sh

    echo "Executing script on $pod with DEST_IP=$dest_ip"
    kubectl exec "$pod" -- sh -c "env DEST_IP='$dest_ip' /tmp/generate_per_pod.sh > /tmp/udp.trafgen"
    echo "Contents of /tmp/udp.trafgen on $pod:"
    kubectl exec "$pod" -- cat /tmp/udp.trafgen
done
```

Now we can start ( this still needs to be done ). 
Right now, only increase pps of no drop on geneve (TODO check RX drop from nic from container, 
i.e., container-xxx if no drop nether from container nor geneve nor eth0 increase pps)

Do with N pods
So we can binary search. 

```bash
#!/bin/bash

target_pod_name="server0"
initial_pps=10000
duration=60  # Duration in seconds to run each trafgen test
interval=10  # Interval in seconds to check the TX packet count

target_pod_interface="server0"
antrea_interface="antrea-gw0"
uplink_interface="eth0"


pod_name=$(kubectl get pods | grep "$target_pod_name" | awk '{print $1}')
node_name=$(kubectl get pod "$pod_name" -o=jsonpath='{.spec.nodeName}')
node_ip=$(kubectl get node "$node_name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
first_core=$(kubectl exec "$pod_name" -- numactl -s | grep 'physcpubind' | awk '{print $2}')

if [ -z "$pod_name" ] || [ -z "$node_name" ] || [ -z "$first_core" ]; then
    echo "Pod, node, or first core not found"
    exit 1
fi

function run_trafgen() {
    local pps=$1
    echo "Starting on pod $pod_name core $first_core with $pps pps"
    kubectl exec "$pod_name" -- /usr/local/sbin/trafgen --cpp \
    --dev eth0 -i /tmp/udp.trafgen --no-sock-mem --rate "${pps}pps" --bind-cpus "$first_core" -V > /dev/null 2>&1 &
    trafgen_pid=$!
}

function get_interface_stats() {
    ssh capv@"$node_ip" cat /proc/net/dev | grep 'genev_sys'
}

# this a pod interface server0--63ab25
function get_interface_stats() {
    ssh capv@"$node_ip" cat /proc/net/dev | grep $target_pod_name
}

# this a pod interface stats for antrea
function get_interface_stats() {
    ssh capv@"$node_ip" cat /proc/net/dev | grep antrea-gw0
}

# this a pod interface stats for uplink
function get_interface_stats() {
    ssh capv@"$node_ip" cat /proc/net/dev | grep "$uplink_interface"
}

function kill_all_traff_gens() {
  pods=$(kubectl get pods | grep 'server' | awk '{print $1}')
  for pod in $pods; do
    kubectl_pid=$(ps -ef | grep "kubectl exec $pod" | grep -v grep | awk '{print $2}')
    if [[ -n "$kubectl_pid" ]]; then
      kill "$kubectl_pid" > /dev/null 2>&1
    fi
    pids=$(kubectl exec "$pod" -- pgrep -f trafgen)
    if [[ -n "$pids" ]]; then
      kubectl exec "$pod" -- pkill -f trafgen > /dev/null 2>&1
    fi
  done
}


get_and_print_interface_stats() {
    local interface_name=$1
    interface_stats=$(ssh capv@"$node_ip" cat /proc/net/dev | grep "$interface_name")
    echo "$interface_stats" | while read line; do
        iface=$(echo "$line" | awk -F: '{print $1}')
        rx_pkts=$(echo "$line" | awk '{print $3}')  # RX pkt
        rx_drop=$(echo "$line" | awk '{print $5}')  # RX drop is in the 5th column
        tx_pkts=$(echo "$line" | awk '{print $11}') # TX pkt
        tx_drop=$(echo "$line" | awk '{print $13}') # TX drop
        printf "%-20s %10s %15s %10s %15s\n" "$iface" "$rx_drop" "$rx_pkts" "$tx_drop" "$tx_pkts"
    done
}

kill_all_traff_gens

# Initial run
current_pps=$initial_pps
run_trafgen $current_pps

start_time=$(date +%s)
previous_tx_drop=0

while [ $(($(date +%s) - start_time)) -lt $duration ]; do
    printf "%-20s %10s %15s %10s %15s\n" "Inf" "RX" "RX Drop" "TX" "TX Drop"
    get_and_print_interface_stats $uplink_interface
    get_and_print_interface_stats $antrea_interface
    get_and_print_interface_stats "genev_sys"
    get_and_print_interface_stats $target_pod_name

    current_tx_drop=$(echo "$interface_stats" | grep 'genev_sys' | awk '{print $13}')
    current_tx_drop=${current_tx_drop:-0}  # Default to 0 if empty

    echo "Current TX drop: $current_tx_drop, Previous TX drop: $previous_tx_drop"

    if [ "$current_tx_drop" -eq "$previous_tx_drop" ]; then
        echo "TX packet count has not increased, doubling PPS"
        ((current_pps*=2))
        kill_all_traff_gens
        sleep 1
        run_trafgen "$current_pps"
        start_time=$(date +%s)
    fi

    previous_tx_drop=$current_tx_drop
    sleep $interval
done

echo "Stopping trafgen process"
kubectl exec "$pod_name" -- kill $trafgen_pid
```
