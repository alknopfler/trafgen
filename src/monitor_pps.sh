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

    TXPPS=$((T2 - T1))
    RXPPS=$((R2 - R1))

    TXDROP=$((TD2 - TD1))
    RXDROP=$((RD2 - RD1))

    TXERR=$((TE2 - TE1))
    RXERR=$((RE2 - RE1))

    TXBYTES=$((TB2 - TB1))
    RXBYTES=$((RB2 - RB1))

    IRQ_RATE=$((IRQ2_T2 - IRQ2_T1))
    SIRQ_RATE=$((SIRQ_T2 - SIRQ_T1))

#    if [ "$TXPPS" -gt 0 ]; then
#        AVG_TX_PACKET_SIZE=$((TXBYTES / TXPPS))
#    else
#        AVG_TX_PACKET_SIZE=0
#    fi
#
#    if [ "$RXPPS" -gt 0 ]; then
#        AVG_RX_PACKET_SIZE=$((RXBYTES / RXPPS))
#    else
#        AVG_RX_PACKET_SIZE=0
#    fi
    if [ "$DIRECTION" = "tx" ]; then
        echo "$TXPPS"
    elif [ "$DIRECTION" = "rx" ]; then
        echo "$RXPPS"
    elif [ "$DIRECTION" = "tuple" ]; then
        echo "$RXPPS, $TXPPS, $RXDROP, $TXDROP, $RXERR, $TXERR, $RXBYTES, $TXBYTES, $IRQ_RATE, $SIRQ_RATE, $NET_TX_RATE, $NET_RX_RATE"
    else
      echo "TX $IF: $TXPPS pkts/s RX $IF: $RXPPS pkts/s TX DROP: $TXDROP pkts/s RX DROP: $RXDROP pkts/s IRQ Rate: $IRQ_RATE, SIRQ Rate: $SIRQ_RATE NET_TX_RATE: $NET_TX_RATE, NET_RX_RATE: $NET_RX_RATE"
    fi

done

