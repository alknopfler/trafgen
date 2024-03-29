# trafgen

## Instruction
Set of bash script and inference scripts that I use to benchmark Linux IP stack.
This script create N profile on each POD and run trafgen for each profile.  It collect data
on sender and receiver pod.  

All data collected to separate file and later passed to inference offline mode to perform
set of correlation and visualization.


## Usage

First create pods by running create_pods.sh script.  This script will create N server and N client pods.
Then run generate_config.sh script to generate config for each pod.  This script will copy to each pod
pkt_generate_template.sh

pkt_generate_template later executed.  What this script does it first resolve default gateway IP address.
It will perform single icmp packet to resolve ARP cache an arping.  It will use default gateway mac address
as dst mac address on generated frame.

The destination IP address passed to each pod so we have 1:1 mapping between server and clinet. 
I.e we have pair of N server-client where each server will send traffic to it corresponding client.


This phase need to be done only once during pod creation.

### Data collection.

in case we want monitor or collect run ./run_monitor_ssh script.  This script will run trafgen between two POD
i.e we want to validate POD to POD communication on same worker node.

script take -p as mandatory arg it pps rate in second -p 1000 1000 pps per sec.
same script launch trafgen and and collect data on sender and receiver pod.

All data read from sysfs and collected to separate file.  

Assume we want use default core ( single core per trafgen)
```bash
./run_monitor_ssh.sh -p 1000
./run_monitor_ssh.sh -p 10000
./run_monitor_ssh.sh -p 100000
./run_monitor_ssh.sh -p 1000000
```


This will create 8 files in metric folder.

Example

```bash
    rx_1000000pps_120_core_0_size_64_20240328122409.txt
    rx_100000pps_120_core_0_size_64_20240328120635.txt
    rx_10000pps_120_core_0_size_64_20240328120118.txt
    rx_1000pps_120_core_0-1_size_64_20240328112149.txt
    rx_1000pps_120_core_0_size_64_20240328115617.txt
    rx_1200000pps_120_core_0_size_64_20240328122905.txt
    rx_200000pps_120_core_0_size_64_20240328134551.txt
    tx_1000000pps_120_core_0_size_64_20240328122409.txt
    tx_100000pps_120_core_0_size_64_20240328120635.txt
    tx_10000pps_120_core_0_size_64_20240328120118.txt
    tx_1000pps_120_core_0-1_size_64_20240328112149.txt
    tx_1200000pps_120_core_0_size_64_20240328122905.txt
    tx_200000pps_120_core_0_size_64_20240328134551.txt
```

Later we can run inference.py to read all this file and 
run cross correlation and visualization.


