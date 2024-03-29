#!/bin/bash
# This one read stats insider a pod at refresh rate.
# note if we need speed this we can write small C code that read that stats.
# On rx and tx we can run this script to sample TX/RX and all other stats.
# tuple serialize as comma separate value later passed to numpy hence vectorized
# do cross correlation.
# Mus
INTERVAL="1"

if [ -z "$1" ]; then
    echo "Usage: $0 [network-interface] [tx|rx|tuple]"
    echo "Example: $0 eth0 tx"
    echo "Shows packets-per-second for the specified interface and direction (tx or rx)"
    exit 1
fi


IF="$1"
DIRECTION="${2:-$DEFAULT_DIRECTION}"

#if [ "$DIRECTION" != "tx" ] && [ "$DIRECTION" != "rx" ] && [ "$DIRECTION" != "both" ]; then
#    echo "Invalid direction. Please specify 'tx', 'rx', or omit for both."
#    exit 1
#fi

while true; do

    R1=$(cat /sys/class/net/"$IF"/statistics/rx_packets)
    T1=$(cat /sys/class/net/"$IF"/statistics/tx_packets)

    RD1=$(cat /sys/class/net/"$IF"/statistics/rx_dropped)
    TD1=$(cat /sys/class/net/"$IF"/statistics/tx_dropped)

    RB1=$(cat /sys/class/net/"$IF"/statistics/rx_bytes)
    TB1=$(cat /sys/class/net/"$IF"/statistics/tx_bytes)

    RE1=$(cat /sys/class/net/"$IF"/statistics/rx_errors)
    TE1=$(cat /sys/class/net/"$IF"/statistics/tx_errors)

    IRQ2_T1=$(grep '^intr' /proc/stat | awk '{print $2}')
    SIRQ_T1=$(grep '^softirq' /proc/stat | awk '{print $2}')

    NET_TX1=$(awk '/NET_TX/ {sum=0; for(i=2; i<=NF; i++) sum+=$i; print sum}' /proc/softirqs)
    NET_RX1=$(awk '/NET_RX/ {sum=0; for(i=2; i<=NF; i++) sum+=$i; print sum}' /proc/softirqs)

    sleep "$INTERVAL"


    R2=$(cat /sys/class/net/"$IF"/statistics/rx_packets)
    T2=$(cat /sys/class/net/"$IF"/statistics/tx_packets)

    RD2=$(cat /sys/class/net/"$IF"/statistics/rx_dropped)
    TD2=$(cat /sys/class/net/"$IF"/statistics/tx_dropped)

    RB2=$(cat /sys/class/net/"$IF"/statistics/rx_bytes)
    TB2=$(cat /sys/class/net/"$IF"/statistics/tx_bytes)

    RE2=$(cat /sys/class/net/"$IF"/statistics/rx_errors)
    TE2=$(cat /sys/class/net/"$IF"/statistics/tx_errors)

    IRQ2_T2=$(grep '^intr' /proc/stat | awk '{print $2}')
    SIRQ_T2=$(grep '^softirq' /proc/stat | awk '{print $2}')

    NET_TX2=$(awk '/NET_TX/ {sum=0; for(i=2; i<=NF; i++) sum+=$i; print sum}' /proc/softirqs)
    NET_RX2=$(awk '/NET_RX/ {sum=0; for(i=2; i<=NF; i++) sum+=$i; print sum}' /proc/softirqs)

    NET_TX_RATE=$((NET_TX2 - NET_TX1))
    NET_RX_RATE=$((NET_RX2 - NET_RX1))

    TX_PPS=$((T2 - T1))
    RX_PPS=$((R2 - R1))

    TX_DROP=$((TD2 - TD1))
    RX_DROP=$((RD2 - RD1))

    TX_ERR=$((TE2 - TE1))
    RX_ERR=$((RE2 - RE1))

    TX_BYTES=$((TB2 - TB1))
    RX_BYTES=$((RB2 - RB1))

    IRQ_RATE=$((IRQ2_T2 - IRQ2_T1))
    S_IRQ_RATE=$((SIRQ_T2 - SIRQ_T1))

    if [ "$TX_PPS" -gt 0 ]; then
        AVG_TX_PACKET_SIZE=$((TX_BYTES / TX_PPS))
    else
        AVG_TX_PACKET_SIZE=0
    fi

    if [ "$RX_PPS" -gt 0 ]; then
        AVG_RX_PACKET_SIZE=$((RX_BYTES / RX_PPS))
    else
        AVG_RX_PACKET_SIZE=0
    fi

    if [ "$DIRECTION" = "tx" ]; then
        echo "$TX_PPS"
    elif [ "$DIRECTION" = "rx" ]; then
        echo "$RX_PPS"
    elif [ "$DIRECTION" = "tuple" ]; then
        echo "$RX_PPS, $TX_PPS, $RX_DROP, $TX_DROP, $RX_ERR, $TX_ERR, $RX_BYTES, $TX_BYTES, $IRQ_RATE, $S_IRQ_RATE, $NET_TX_RATE, $NET_RX_RATE"
    else
      echo "TX $IF: $TX_PPS pkts/s RX $IF: $RX_PPS pkts/s TX DROP: $TX_DROP pkts/s RX DROP: $RX_DROP pkts/s IRQ Rate: $IRQ_RATE, SIRQ Rate: $S_IRQ_RATE NET_TX_RATE: $NET_TX_RATE, NET_RX_RATE: $NET_RX_RATE AVG_RX_SIZE: $AVG_RX_PACKET_SIZE AVG_TX_SIZE: $AVG_TX_PACKET_SIZE"
    fi

done

