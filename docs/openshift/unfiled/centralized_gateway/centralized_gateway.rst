*******************
Centralized Gateway
*******************

用户场景
========

私有云场景下，容器云的用户需求一个对标虚机云的浮动IP的功能。

用户可能有一个数据库是放在容器云集群外的，并且处于安全考虑，设置了基于IP的访问策略。现在容器云上的容器想要访问该数据库，那么容器将以所在节点的IP对数据库发起访问。这就需要网络安全策略调整为对节点IP放行。而这一后果是，这一节点上的所有容器都可以绕过安全策略来访问数据库，安全策略从而失效。

但如果容器云能提供浮动IP的功能，即当容器主动访问外部网络时，可以以某个具体的外部网络IP作为源IP，而不再是节点的IP。

相对的，也会有反过来的需求场景，对于以TCP方式暴露的服务，用户希望限定的来源才能访问。这时用户就需要在Pod内可以获得外部请求的源IP，或者需要平台能够提供一个IP过滤接口。


功能原型
========

这个预想功能的原型是K8S的Service.externalIPs + :ref:`OpenShift的ip failover <ip_failover>`:

  - ip failover 提供了以集群外部IP为目的的流量能够被路由到集群边界的能力
  - externalIPs 提供了以集群外部IP为目的的流量在到达集群边界后能通过DNAT能转化为集群内部IP的能力，从而使得该流量可以进入集群内的容器网络

ip failover简单的说，就是通过在容器内起keepalived，让keepalived来管理VIP，使得VIP能挂在集群的节点上，并且是主备HA的。

externalIPs是由K8S原生提供的功能，初步检查了ovs-multitenant和flanneld这两个网络插件，确认在externalIPs这个功能的实现是不受网络插件影响的。externalIPs仅仅提供了DNAT能力，即主要处理来自外部网络的访问流量，但是对于集群内容器主动访问外部网络的场景，并不会做NAT处理。


解决思路
========

需要定制化修改，以实现依托于externalIPs + IP failover的centralized gateway(CGW)的功能。CGW有点像OpenStack的Router + 端口映射；相对与容器平台的各个节点具有的分布式网关属性而言，CGW是集中式的。

CGW的HA属性由所依托的OpenShift IP Failover提供支持。

而北向流量的SNAT处理需要 :ref:`定制化修改iptables proxier <customize_iptables_proxier>` 。

由于是GW，因此不会像Service的负载均衡实现那样对南向流量做SNAT处理。因此对于Pod而言，来自外部访问的源IP是可见的，这需要 :ref:`再次定制化修改iptables proxier <customize_iptables_proxier_v2>` 。

在 :ref:`再次定制化修改iptables proxier <customize_iptables_proxier_v2>` 的结尾提到了对OVS flows的修改，以实现Service后面的Pod的南北向流量能被路由到CGW。目前相关的实现还需要进一步调研。


其他concern
===========

在ip failover的基础上，VIP TCP方式暴露的服务可以做到HA，但这种方案不保证全局情况下集群节点的流量均衡。对于这种情况，外部负载均衡无济于事，可以考虑的方案是通过配置keepalived的script来节点流量的检查，当高于某一阈值时，则退避，不成为master去挂载VIP。但这样做的缺点也十分明显，其一，流量阈值很难评估，并且是静态的值，无法动态调整；其二，如果整个集群当前都处于高网络负载，那么VIP抖动漂移可能会频发，并且考虑添加新的VIP会导致Keepalived reload，而这一过程会导致VIP漂移，进一步加剧了VIP抖动漂移的风险。
