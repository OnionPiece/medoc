#!/bin/bash
#
# run as root
#
# the topology will look like:
#
#     ---(client1)----(client2)-----+-- 172.0.0.0/24
#          .11\         /.12        |
#              \       /            |
#               \     /             | .1
#                [VIP]         (Edge Router)
#               /     \             | .1
#              /       \            |
#             /         \           |
#      ----(lb1)------(lb2)---------+-- 192.0.0.0/24
#         .11|\ \     / /|.12       |
#            | \ \   / / |          |
#            |  \ \ / /  |          |.254
#            |   \ X /   |       (Router)
#            |    X X    |          |.1
#            |   / X \   |          |
#         .11|  / / \ \  |.12       |
#      ----(rs1)-(rs3)-(rs2)---------+-- 10.0.0.0/24
#                 .13

lsmod | grep -q ip_vs || modprobe ip_vs
lsmod | grep -q ipip || modprobe ipip

# create bridge for vswitches 172.0.0.0/24, 192.0.0.0/24, 10.0.0.0/24
for br in 172 192 10; do
    brctl addbr vswi$br
    ip l set vswi$br up
done

# create namespaces, veth pairs for client1, client2, lb1, lb2, rs1, rs2, rs3
# attach peer into namespace and vswitch
# add IP, default route
for ns in client1 client2 lb1 lb2 rs1 rs2 rs3; do
    ip netns add $ns
    ip l add vn-$ns type veth peer name vb-$ns
    ip l set dev vb-$ns up
    vswi=""
    net_id=""
    if [[ ${ns:0:6} == "client" ]]; then
        vswi="vswi172"
        net_id="172"
    elif [[ ${ns:0:2} == "lb" ]]; then
        vswi="vswi192"
        net_id="192"
    else
        vswi="vswi10"
        net_id="10"
    fi
    brctl addif $vswi vb-$ns
    ip l set dev vn-$ns netns $ns
    ip netns exec $ns ip l set vn-$ns up
    host_id=${ns:${#ns}-1}
    ip netns exec $ns ip a add ${net_id}.0.0.1${host_id}/24 dev vn-$ns
    ip netns exec $ns ip r add default via ${net_id}.0.0.1
done

# create namespece for router, edge-router, and attach with vswitches
for ns in ertr rtr; do
    ip netns add $ns
    for d in n s; do
        ip l add vn-$ns-$d type veth peer name vb-$ns-$d
        ip l set dev vb-$ns-$d up
        ip l set dev vn-$ns-$d netns $ns
        ip netns exec $ns ip l set dev vn-$ns-$d up
        net_id=""
        intf_id="1"
        if [[ $ns == "ertr" ]]; then
           if [[ $d == "n" ]]; then
               net_id="172"
           else
               net_id="192"
           fi
        else
           if [[ $d == "n" ]]; then
               net_id="192"
               intf_id="254"
           else
               net_id="10"
           fi
        fi
        ip netns exec $ns ip a add dev vn-$ns-$d ${net_id}.0.0.${intf_id}/24
        brctl addif vswi$net_id vb-$ns-$d
    done
    ip netns exec $ns sysctl net.ipv4.conf.all.forwarding=1
    ip netns exec $ns sysctl net.ipv4.conf.all.rp_filter=0
done

# additional route
ip netns exec rtr ip r add 172.0.0.0/24 via 192.0.0.1
for ns in lb1 lb2
do
    ip netns exec $ns ip r add 10.0.0.0/24 via 192.0.0.254
done
