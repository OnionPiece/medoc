#!/bin/bash
#
# run as root
#
# the topology will look like:
#  
#          192.0.0.0/24               20.0.0.0/24
#               |            |             |
#  +--------+   |            +-----(R)-----+
#  | client +---+   +----+   |             |
#  +--------+   +---+ lb +---+   +-----+   |   +-----+
#      .10      |   +----+   +---+ rs1 |   +---+ rs2 |
#               |    .11     |   +-----+   |   +-----+
#                            |    .12      |    .13
#                            |
#                        10.0.0.0/24

# create namespaces, veth pairs for client, lb, rs1, rs2
for ns in client lb rs1 rs2; do
    ip netns add $ns
    ip l add vn-$ns type veth peer name vb-$ns
    ip l set dev vb-$ns up
    ip l set dev vn-$ns netns $ns
    ip netns exec $ns ip l set vn-$ns up
done

# create bridge for vswitches 192.0.0.0/24, 10.0.0.0/24, 20.0.0.0/24
for br in 192 10 20; do
    brctl addbr vswi$br
    ip l set vswi$br up
done

# set IPs for veth pairs
ip netns exec client ip a add 192.0.0.10/24 dev vn-client
ip netns exec lb ip a add 192.0.0.11/24 dev vn-lb
ip netns exec rs1 ip a add 10.0.0.12/24 dev vn-rs1
ip netns exec rs2 ip a add 20.0.0.13/24 dev vn-rs2

# attach veth pairs on bridges/vswitches
brctl addif vswi192 vb-client
brctl addif vswi192 vb-lb
brctl addif vswi10  vb-rs1
brctl addif vswi20  vb-rs2

# add router namespace to connect vswithces 10.0.0.0/24 and 20.0.0.0/24
ip netns add router
ip l add vn-rtr-10 type veth peer name vb-rtr-10
ip l add vn-rtr-20 type veth peer name vb-rtr-20
ip l set dev vb-rtr-10 up
ip l set dev vb-rtr-20 up
ip l set dev vn-rtr-10 netns router
ip l set dev vn-rtr-20 netns router
ip netns exec router ip l set dev vn-rtr-10 up
ip netns exec router ip l set dev vn-rtr-20 up
ip netns exec router ip a add dev vn-rtr-10 10.0.0.1/24
ip netns exec router ip a add dev vn-rtr-20 20.0.0.1/24
brctl addif vswi10 vb-rtr-10
brctl addif vswi20 vb-rtr-20
ip netns exec router sysctl net.ipv4.conf.all.forwarding=1
ip netns exec router sysctl net.ipv4.conf.all.rp_filter=0

# attach lb on vswitch 10.0.0.0/24
ip l add vn-lb-10 type veth peer name vb-lb-10
ip l set dev vb-lb-10 up
ip l set dev vn-lb-10 netns lb
ip netns exec lb ip l set vn-lb-10 up
ip netns exec lb ip a add dev vn-lb-10 10.0.0.11/24
brctl addif vswi10 vb-lb-10

# add route for lb to access vswitch 20.0.0.0/24
ip netns exec lb ip r add 20.0.0.0/24 via 10.0.0.1

# (optional) add route for rs1 to access vswitch 20.0.0.0/24
ip netns exec rs1 ip r add 20.0.0.0/24 via 10.0.0.1

# add route for rs2 to access vswitch 10.0.0.0/24
#ip netns exec rs2 ip r add 10.0.0.0/24 via 20.0.0.1
ip netns exec rs2 ip r add default via 20.0.0.1
