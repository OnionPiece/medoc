.. _customize_sdn_controller:

****************************
修改OpenShift SDN controller
****************************

在 :ref:`再次修改OpenShift iptables proxier <customize_iptables_proxier_v2>` 的末尾提到了对OVS flows的修改，以解决Service后面的Pod的南北向流量能被路由到centralized gateway的问题。在简单测试环境中，面对固定变量，OVS flows很容易设计，但在实际中，我们需要考虑更多的问题:

  - VIP漂移所带来的centralized gateway改变
  - Pods come and go
  - origin-node服务重启所带来的tun0的MAC改变

这里回顾一下workaround的OVS flows，以便后续有针对性的展开。其中前两条规则是相对固定的，只要Cluster CIDR定了，基本上这个规则可以在集群内的所有节点上都默认生成；而我们需要主要关注的是第三条::

    # A节点:
    # table 0:
    priority=160,ip,in_port=1,nw_src=10.128.0.0/18 actions=move:NXM_NX_TUN_ID[0..31]->NXM_NX_REG0[],goto_table:100

    # B节点:
    # table 0:
    priority=160,ip,in_port=1,nw_dst=10.128.0.0/18 actions=move:NXM_NX_TUN_ID[0..31]->NXM_NX_REG0[],goto_table:10
    # table 100:
    ip,nw_src=10.128.11.100 actions=set_field:4a:2e:a7:e0:60:79->eth_dst,move:NXM_NX_REG0[]->NXM_NX_TUN_ID[0..31],set_field:192.168.39.238->tun_dst,output:1


VIP漂移
-------

当发生VIP漂移时，我们需要有机制能够通知Centralized Gateway(CGW)的变迁，从上面的flow中可以看出，主要需要通知的是tun0的MAC，以及dst_tun的IP。正确的通知在触发flows更新后，可以确保来自容器的北向流量能够被转发到CGW。

由于ipfailover Pod使用的是hostNetwork，在容器内获取tun0的MAC和dst_tun的IP是很容易做到的。并且配合keepalived的notify script，可以很容易实现将Master所在的节点的相关MAC和IP通过API的方式更新到Service，例如更新到Service的annotations。

值得注意的是，代码中对于Service是否改变的逻辑判断是基于ports的，不会考虑annotations，因此针对CGW，需要作出改变，让Service认为annotations的改变也是一种改变。

如果考虑将受影响的Pod IP也由notify script来通知，则会产生非必要的问题，毕竟Service和Pod毕竟是两种资源，Pod的生死变迁是不会通知到Service的。因此，需要利用其他方法让Pod的北向流量能够知道它应该走的是本节点的网关出去，还是通过CGW出去，并且还得知道对应的CGW在哪里。


Pods come and go
----------------

Pod的生死变迁所带来的IP变换无法也无需与CGW进行协调，虽然VIP是挂在CGW所对应的Service上，而Pod又与Service关联。考虑Pod的生死和Service的更新，他们实际上是在两条不同的处理流程上，有着不同的触发源，并且在代码层面，有不同的“管理员”来分别负责维护他们。从这个角度来看，上面的table 100中flow设计的是有问题的。对此，需要的改动是，将数据包来源的判断和所做的修改eth_dst和tun_dst的部分拆开。同样在代码层面上，table 100是由Service“负责维护”的，因此与Pod有关的东西也不应该加在这里。

考虑OVS多租户插件的现有套路，其实我们也不必要在table 100添加针对Pod IP的过滤，在table 20添加register就好。并且这样，就可以实现Pod和Service各自维护不同的OVS flows。这种方式，唯一需要考虑的问题是如何指定register。因为一个VIP可以挂在不同的Service上，而同一个namespace下不一定所有的Service都挂载VIP。因此所有配置VIP的Service需要与Pod“协商”一个register ID。一种比较简单的做法就是通过annotations，DC中配置annotations可以由Pod来“继承”，而Service配置同样的值，于是乎，table 20和table 100中flows的关联逻辑就可以打通了。


origin-node的重启
-----------------

当origin-node服务重启后，tun0会被重建，这将导致tun0的MAC发生改变，相应的如果Master在这个节点上并且在重启期间没有发生主备切换，那么已经通过API更新的tun0 MAC将会变成脏数据。对此，一种可行的方式是通过配置check script来检查Master当前的tun0 MAC与上一次通报的tun0 MAC是否一致。
