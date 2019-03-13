#!/bin/bash
#
# run as root

# config lb1 lb2, 192.0.0.100 will be VIP for the two lb to serve
# config connection sync
for ns in lb1 lb2; do
    ip netns exec $ns ip a add dev vn-$ns 192.0.0.100/32
    ip netns exec $ns ipvsadm -A -t 192.0.0.100:80 -s rr
    for rs in 11 12 13; do
        ip netns exec $ns ipvsadm -a -t 192.0.0.100:80 -r 10.0.0.$rs:80 -i
    done
    ip netns exec $ns ip l set tunl0 up
    for conf in "all.forwarding=1" "all.rp_filter=0" "tunl0.rp_filter=0"; do
        ip netns exec $ns sysctl net.ipv4.conf.$conf
    done
    for sync in 1 2; do
        state="backup"
        if [[ ${ns:${#ns}-1} -eq $sync ]]; then
            state="master"
        fi
        ip netns exec $ns ipvsadm --start-daemon $state --mcast-interface vn-$ns --syncid $sync
    done
done

# run nginx in rs1 rs2, rs3, and set tunl0 up
# setup ip tunnel for rs1 rs2 rs3 to response back to VIP on lb1, lb2
# add policy route to make sure response(src IP is VIP) will be routed via tunnel
for ns in rs1 rs2 rs3; do
    ip netns exec $ns nginx
    ip netns exec $ns ip l set tunl0 up
    host_id=${ns:${#ns}-1}
    for rmt in 11 12; do
        ip netns exec $ns ip tun add tunl$rmt mode ipip remote 192.0.0.$rmt local 10.0.0.1$host_id;
        ip netns exec $ns ip l set tunl$rmt up
        ip netns exec $ns ip a add dev tunl$rmt 192.0.0.100/32 brd 192.0.0.100
        for conf in "forwarding=1" "rp_filter=0"; do
            ip netns exec $ns sysctl net.ipv4.conf.tunl${rmt}.$conf
        done
    done
    ip netns exec $ns ip rule add from 192.0.0.100/32 table 16
    # this is just a initial value, we will change this in switch-path.sh
    ip netns exec $ns ip r add default dev tunl11 table 16
done

# add an initial neigh address for VIP in edge-router
ip netns exec ertr ip n add 192.0.0.100 dev vn-ertr-s lladdr `ip netns exec lb1 ip l show vn-lb1 | awk '/ether/{print $2}'` nud reachable

# add policy route for lb, lb2 to forward repsonse received via tunnel
#ip netns exec lb ip rule add iif tunl0 table 16
#ip netns exec lb ip r add 192.0.0.0/24 dev vn-lb table 16
#ip netns exec lb2 ip rule add iif tunl0 table 16
#ip netns exec lb2 ip r add 192.0.0.0/24 dev vn-lb2 table 16
