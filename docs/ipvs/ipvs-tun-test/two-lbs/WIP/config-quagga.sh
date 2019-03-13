#!/bin/bash
#
# run as root
# suppose quagga has been installed

# for edge router
for rtr in edge-router router
do
    for i in zebra ospfd
    do
        cat > /opt/edge-router-${i}.conf << EOF
hostname $i
password $i
enable password $i
log file /opt/edge-router-${i}.log
EOF
        chown quagga:quagga /opt/edge-router-${i}.conf
        for j in log pid
        do
            touch /opt/edge-router-${i}.$j
            chown quagga:quagga /opt/edge-router-${i}.$j
        done
        ip netns exec $rtr $i -f /opt/edge-router-${i}.conf -i /opt/edge-router-${i}.pid -z /opt/edge-router-${i}.sock &
    done
done
