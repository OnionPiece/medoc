#!/bin/bash
#
# run as root

pkill -9 -f "nc -l -p 80"

rmmod ip_vs
rmmod ipip

brctl delif vswi192 vb-client
brctl delif vswi192 vb-lb
brctl delif vswi10 vb-lb-10
brctl delif vswi10 vb-rs1
brctl delif vswi10 vb-rtr-10
brctl delif vswi20 vb-rs2
brctl delif vswi20 vb-rtr-20

ip l set vswi192 down
ip l set vswi10 down
ip l set vswi20 down

brctl delbr vswi192
brctl delbr vswi10
brctl delbr vswi20

ip netns del client
ip netns del lb
ip netns del rs1
ip netns del rs2
ip netns del router
