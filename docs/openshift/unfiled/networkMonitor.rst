*********************
OpenShift平台网络监控
*********************

这里的监控只针对与平台自身，而不包括对于用户业务的监控。

SDN网络连通性
=============

参考 https://github.com/lizk1989/octopus/tree/master/sdnChecker 。该项目的实现逻辑包括:

  - 各个节点，包括Master和Node，都会以daemonSet的方式跑一个包含监控容器；
  - 这个监控容器内部运行一个haproxy来检查该容器到其他节点tun0的可达性，暴露stat metrics在容器的1936端口；
  - 同时，这个容器内部还会运行一个简单的web server，暴露两个接口，一个查询本容器内的haproxy metrics并返回，另一个查询所有监控容器的haproxy metrics并返回；
  - 最后，通过OpenShift Server将deamonSets组织起来，并通过Route暴露服务。

重复VIP
=======

参考 https://github.com/lizk1989/octopus/tree/master/dupVIPMonitor 。 该项目的实现逻辑包括:

  - 以DC的方式在不会绑定VIP的节点上部署监控容器；
  - 这个监控容器内部运行一个监控程序，通过 https://github.com/ThomasHabets/arping 通过检查是否重复的ARP应答来判断VIP是否有重复；
  - 同时这个容器运行一个web server暴露检查结果。

Router的可用性
==============

Prometheus应该有对接。通过curl就可以查验router的可用性::

    curl -u admin:$(oc get dc router -o yaml | grep STATS_PASSWORD -A 1 | awk '/value/{print $2}') ${ROUTER_HOST_IP}:1936/healthz

延伸一下，集群外部的负载均衡，可以添加对Router healthz的httpc check。参考:

  - https://github.com/openshift/openshift-ansible/issues/7986
  - https://bugzilla.redhat.com/show_bug.cgi?id=1579054

Router metcics
==============

Router除了暴露healthz接口外，还暴露了metrics接口，通过curl可查验::

    curl -u admin:$(oc get dc router -o yaml | grep STATS_PASSWORD -A 1 | awk '/value/{print $2}') ${ROUTER_HOST_IP}:1936/metrics
