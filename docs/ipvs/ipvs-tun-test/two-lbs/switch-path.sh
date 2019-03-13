cur_mac=`ip netns exec ertr ip n | awk '/192.0.0.100/{print $5}'`
lb1_mac=`ip netns exec lb1 ip l show vn-lb1 | awk '/ether/{print $2}'`
#lb2_mac=`ip netns exec lb2 ip l show vn-lb2 | awk '/ether/{print $2}'`

if [[ $cur_mac == $lb1_mac ]]; then
    ip netns exec lb1 sysctl net.ipv4.conf.vn-lb1.arp_ignore=8
    ip netns exec lb2 sysctl net.ipv4.conf.vn-lb2.arp_ignore=0
    for rs in rs1 rs2 rs3; do
        ip netns exec $rs ip r replace default dev tunl12 table 16
    done
else
    ip netns exec lb1 sysctl net.ipv4.conf.vn-lb1.arp_ignore=0
    ip netns exec lb2 sysctl net.ipv4.conf.vn-lb2.arp_ignore=8
    for rs in rs1 rs2 rs3; do
        ip netns exec $rs ip r replace default dev tunl11 table 16
    done
fi
ip netns exec ertr ip n del 192.0.0.100 dev vn-ertr-s
