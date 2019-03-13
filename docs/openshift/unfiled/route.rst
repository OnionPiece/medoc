******
Routes
******

From https://docs.openshift.com/container-platform/3.5/architecture/core_concepts/routes.html
Perfer https://github.com/openshift/origin/blob/master/docs/routing.md
Also prefer https://docs.openshift.com/container-platform/3.5/install_config/router/customized_haproxy_router.html


Overview
========

An OpenShift Container Platform route exposes a service at a host name, like www.example.com, so that external clients can reach it by name.

Route用来将内部的Service以域名的方式暴露出去。

DNS resolution for a host name is handled separately from routing. Your administrator may have configured a DNS wildcard entry that will resolve to the OpenShift Container Platform node that is running the OpenShift Container Platform router.

DNS的解析与Route本身无关，平台的管理员应该负责在DNS中配置泛域名来将访问平台上容器服务的流量引导到运行Router Pod的节点。

Each route consists of a name (limited to 63 characters), a service selector, and an optional security configuration.


Routers
=======

A router uses the service selector to find the service and the endpoints backing the service. 

Router通过route.spec.to和route.spec.alternateBackends指向Service，Service指向后边的Pod，来发现实际提供服务的server。

The suggested method is to define a cloud domain with a wildcard DNS entry pointing to one or more virtual IP (VIP) addresses backed by multiple router instances.

*oadm router --help* 并没有显示所谓的VIP，但在实际环境中，Router DC配置了 *hostNetwork* 和 *hostPort* ，而没有配置 *hostIP* ，说明Router将直接使用节点的IP及端口，但凡能够被外部网络将流量路由到节点的节点IP，都应该是所谓的VIP。这与IP Failover的VIP有所不同。

Sharding allows the operator to define multiple router groups. Each router in the group serves only a subset of traffic.

Sharing允许Router分组，来分摊不同的routes以及不同的traffic。


Template Routers
----------------

A template router is a type of router that provides certain infrastructure information to the underlying router implementation, such as:

  - A wrapper that watches endpoints and routes.
  - Endpoint and route data, which is saved into a consumable form.
  - Passing the internal state to a configurable template and executing the template.
  - Calling a reload script.

以上的内容说明了Router实现所需要达到的东西，也包括了一般Router的处理流程。监听endpoints和routes，这二者对应URL和backend中的server，当发生变化时，通过模板来刷新配置，然后通过reload脚本重启相应的service，如haproxy。


Available Router Plug-ins
=========================

Two plug-ins: https://docs.openshift.com/container-platform/3.5/install_config/router/index.html#install-config-router-overview . HAProxy template router and F5 router.



Not finished yet.
