#!/bin/bash
#
# run as root

pkill -9 -f "nginx"

rmmod ip_vs
rmmod ipip

brctl delif vswi172 vb-client1
brctl delif vswi172 vb-client2
brctl delif vswi172 vb-ertr-n

brctl delif vswi192 vb-lb1
brctl delif vswi192 vb-lb2
brctl delif vswi192 vb-ertr-s
brctl delif vswi192 vb-rtr-n

brctl delif vswi10 vb-rs1
brctl delif vswi10 vb-rs2
brctl delif vswi10 vb-rs3
brctl delif vswi10 vb-rtr-s

for i in 172 192 10; do
    ip l set vswi$i down
    brctl delbr vswi$i
done

for i in client1 client2 lb1 lb2 rs1 rs2 rs3 rtr ertr; do
    ip netns del $i
done
