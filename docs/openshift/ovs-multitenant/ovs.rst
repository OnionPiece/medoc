**************************************
基于OVS多租户的OpenShift网络N板斧——OVS
**************************************

关于OVS多租户下的OVS flows，可以查看 :ref:`OpenShift OVS flows <openshift_ovs_flows>` 。

这里只针对容器接在OVS网桥上的veth端口进行一点说明。在检查流量的时候，无论是查看流表，还是使用tcpdump抓包，都需要明确容器对应的veth端口是哪个，以下将简单介绍三个方法。


通过iflink和ifindex的映射
=========================


通过查看文件
------------

参考 https://forums.docker.com/t/relationship-between-interface-vethxxxxx-and-container/12872/20 。


通过命令查看网卡
----------------

在容器内，通过命令 *ip a* 查看 *eth0* ，举例看到::

    eth0@if1740:
      inet 10.128.11.146/23 scope global eth0


而在节点上，通过命令 *ip l | grep XXX* （本例中XXX为上面看到的1740），那么我们看到::

    $ ip l | grep 1740
    1740: veth12345678@if3: ...

那么veth12345678 就是容器网卡对应的OVS网桥上的端口。


通过OVS flows查看
=================

在 :ref:`OpenShift OVS flows <openshift_ovs_flows>` 中提到table 70会根据数据包的目的IP设置转发出口标记。因此，我们可以从table 70中，通过容器的IP读到容器对应的OVS端口编号。读到的编号为16进制，可以用命令如 *printf "%d" 0xABC* 来获取相应的十进制数。获取后，通过OVS命令 *ovs-ofctl show br0 | grep XXX* 即可得到对应的OVS端口。
