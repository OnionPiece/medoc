.. _ip_failover:

***********
IP Failover
***********

From https://docs.openshift.com/container-platform/3.5/admin_guide/high_availability.html


Overview
========

This topic describes setting up high availability for pods and services on your OpenShift Container Platform cluster.

**IP failover monitors a port on each VIP to determine whether the port is reachable on the node**. If the port is not reachable, the VIP will not be assigned to the node. If the port is set to 0, this check is suppressed. The check script does the needed testing.

IP failover uses Keepalived to host a set of externally accessible VIP addresses on a set of hosts.

VIP是一个由集群外部IP构成的池子，将由集群node构成的池子来hold，二者的规模不必对等。最终应该是通过externalIPs或者nodePort的方式打通外部IP和容器的。

OpenShift Container Platform supports creation of IP failover deployment configuration, by running the *oc adm ipfailover* command. ... Each node in the IP failover configuration runs an IP failover pod, and this pod runs Keepalived.

加入池子的节点将运行一个跑着keepalived的容器，keepalived将检查节点上的被容器所使用的端口是否可用，如果不可用，则当前节点不能成为master。

对于配置了hostNetwork的容器，当使用VIP进行访问时，需要确保容器的部分跑在每一个加入到VIP池的节点上；但如果是访问Service则不需要。原因显而易见。不过话说回来，hostNetwork的方式通常而言，并不适合一般用户使用。

There are a maximum of 255 VIPs in the cluster.

集群内的节点属于同一个二层广播域，而对于keepalived，同一个广播域内只能有255 VRRP ID。VRRP ID数量的限制和VIP的数量限制其实是没有关系的，但是OpenShift在release-3.9及更早版本的实现，导致在keepalived.conf配置文件中，限制了一个vrrp_instance的virtual_ipaddress中只能有一个IP，因此，整个集群内的VIP数量被限制在了255个。在本篇最后的小节将对VIP和VRRP ID限制关联的代码进行简单的说明。


Configuring IP Failover
=======================

Using selector to restrict where the ipfailover is deployed.


Check and Notify Scripts
------------------------

When a check script is not provided, a simple default script is run that tests the TCP connection. **This default test is suppressed when the monitor port is 0.**

The recommended approach for providing the scripts is to use a ConfigMap.

**The defaultMode for the mounted configMap files must allow execution.** A value of 0755 (493 decimal) is typical.

In the spec.container.env field, add the OPENSHIFT_HA_CHECK_SCRIPT environment variable to point to the mounted script file.


Keepalived Multicast
--------------------

Before starting the keepalived daemon, the startup script verifies the iptables rule that allows multicast traffic to flow. If there is no such rule, the startup script creates a new rule and adds it to the IP tables configuration...If there is an --iptables-chain= option specified, the rule gets added to the specified chain in the option. Otherwise, the rule is added to the INPUT chain.


Command Line Options and Environment Variables
----------------------------------------------

--interface OPENSHIFT_HA_NETWORK_INTERFACE

  The interface name for ipfailover to use, to send VRRP traffic. By default, eth0 is used.

--vrrp-id-offset OPENSHIFT_HA_VRRP_ID_OFFSET

  Default 0. Base 1, so 1 + 0.

--check-script OPENSHIFT_HA_CHECK_SCRIPT

  Full path name in the pod file system of a script that is periodically run to verify the application is operating. See this discussion for more details.

--check-interval OPENSHIFT_HA_CHECK_INTERVAL

  Default 2. The period, in seconds, that the check script is run.

--notify-script OPENSHIFT_HA_NOTIFY_SCRIPT

  Full path name in the pod file system of a script that is run whenever the state changes. See this discussion for more details.


Configuring a Highly-available Service
--------------------------------------

You can either reuse service account created previously or a new ipfailover service account.

The following example creates a new service account with the name ipfailover in the default namespace::

    $ oc create serviceaccount ipfailover -n default

Add the ipfailover service account in the default namespace to the privileged SCC::

    $ oc adm policy add-scc-to-user privileged system:serviceaccount:default:ipfailover


个人补充
========

NodePort 类型的服务
-------------------

对于这类的服务，需要配置OPENSHIFT_HA_MONITOR_PORT为对应端口。


配备 externalIPs 的 ClusterIP 类型的服务
----------------------------------------

对于这类的服务，需要配置OPENSHIFT_HA_MONITOR_PORT为0。


VRRP_ID_OFFSET
--------------

管理员需要负责确保VRRP_ID_OFFSET不会重复。否则，将导致同一广播域的VRRP ID重复，其结果就是新配置的ip failover无法工作，具体表现是ip failover的Pod及keepalived在启动后，相应的VIP不会挂在由nodeSelector所选择的节点上。


OPENSHIFT_HA_NETWORK_INTERFACE
------------------------------

实测环境中，没有eth0，并且也做了bonding，创建的ip failover服务也没有配置OPENSHIFT_HA_NETWORK_INTERFACE，但结果发现，多次测试VIP都挂在了默认路由的网口上。

通过查看ipfailover的代码 https://github.com/openshift/origin/blob/master/images/ipfailover/keepalived/lib/utils.sh#L246-L255 ，发现当不指定interface参数的时候，会通过命令 *ip route get 8.8.8.8* 来判断VIP需要挂载的网口，所以最终会指向默认路由的网口上。


keepalived virtual_ipaddress 配置生成代码调研
---------------------------------------------

在测试了ip failover功能后，困惑于VIP数量与VRRP ID数量挂钩，导致整个集群只能有255个VIP，遂决定学习一下ip failover的实现代码，了解一下为什么。

keepalived配置“落地”后，一个virtual_ipaddress中只有一个IP，因此最直接的想法是通过grep virtual_ipaddress来>定位一个学习代码的切入点。可以发现，ip failover功能使用函数 `generate_vip_section
<https://github.com/openshift/origin/blob/master/images/ipfailover/keepalived/lib/config-generators.sh#L145-L165>`_ 来产生virtual_ipaddress的配置。

generate_vip_section 接受两个参数，即vips和interface。generate_vip_section的代码虽然写明了会用for循环来写>入多个VIP，但实际的结果并不相符，说明所传入的参数vips很可能是个单值，而不是多个VIP的array。

generate_vip_section 的调用者是generate_vrrpd_instance_config，而后者又被 `generate_failover_config
<https://github.com/openshift/origin/blob/master/images/ipfailover/keepalived/lib/config-generators.sh#L219-L296>`_ 。从master上的代码来看，已经在考虑用vip_groups来对VIP进行分组了，猜测需要通过配置OPENSHIFT_HA_VIP_GROUPS来开启该功能，并且GROUPS需要大于0。

而反观release-3.9及更早的分支，则没有相应的逻辑，在generate_failover_config中会直接用for循环来遍历所有的VIP，然后逐个调用generate_vrrpd_instance_config。

所以要突破集群全局255个VIP的限制，可能需要cherry-pick引入vip_groups的patch来解决。在github上通过blame查看>到相应的patch是 https://github.com/openshift/origin/commit/78c2f0ec11c687a371ae85c51f6b3002e5d79bb4 。

(Update)
虽然vip_groups可以使得整个集群突破255个VIP的限制，但是VIP分组还是255个。如果一个集群的所有节点都在同一个广播域里，那么由于vrid最多只有255个，VIP也将只有255个。所以，如果把集群的节点放置在不同的广播域可能是个思路。
