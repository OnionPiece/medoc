#!/bin/bash
#
# run as root

# run a simple server on 80 via netcat for ns1 and ns2
ip netns exec rs1 sh -c "while true; do echo 'rs1>hello world' | nc -l -p 80; done > /dev/null &"
ip netns exec rs2 sh -c "while true; do echo 'rs2>hello world' | nc -l -p 80; done > /dev/null &"

lsmod | grep -q ip_vs || modprobe ip_vs
lsmod | grep -q ipip || modprobe ipip

# add virtual service and real servers in lb namespace via ipvsadm
ip netns exec lb sh -c "ipvsadm -A -t 192.0.0.11:80 -s rr"
ip netns exec lb sh -c "ipvsadm -a -t 192.0.0.11:80 -r 10.0.0.12:80 -i"
ip netns exec lb sh -c "ipvsadm -a -t 192.0.0.11:80 -r 20.0.0.13:80 -i"

# setup tunl0 in lb, rs1, rs2 namespaces
ip netns exec lb ip l set tunl0 up
ip netns exec lb sysctl net.ipv4.conf.all.forwarding=1
ip netns exec lb sysctl net.ipv4.conf.all.rp_filter=0
ip netns exec lb sysctl net.ipv4.conf.tunl0.rp_filter=0
ip netns exec rs1 ip l set tunl0 up
ip netns exec rs2 ip l set tunl0 up

# setup ip tunnel for rs1, rs2 to response back to lb
ip netns exec rs1 ip tun add tunl1 mode ipip remote 10.0.0.11 local 10.0.0.12
ip netns exec rs2 ip tun add tunl1 mode ipip remote 10.0.0.11 local 20.0.0.13
for ns in rs1 rs2; do
    ip netns exec $ns ip l set tunl1 up
    ip netns exec $ns sysctl net.ipv4.conf.tunl1.arp_ignore=1
    ip netns exec $ns sysctl net.ipv4.conf.tunl1.forwarding=1
    ip netns exec $ns sysctl net.ipv4.conf.tunl1.rp_filter=0
    ip netns exec $ns ip a add dev tunl1 192.0.0.11/32 brd 192.0.0.11

    # add policy route to make sure response(src IP is VIP) will be routed via tunnel
    ip netns exec $ns ip rule add from 192.0.0.11/32 table 16
    ip netns exec $ns ip r add default dev tunl1 table 16
done

# add policy route for lb to forward repsonse received via tunnel
ip netns exec lb ip rule add iif tunl0 table 16
ip netns exec lb ip r add 192.0.0.0/24 dev vn-lb table 16
