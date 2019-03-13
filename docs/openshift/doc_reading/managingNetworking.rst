*******************
Managing Networking
*******************

From: https://docs.openshift.com/container-platform/3.9/admin_guide/managing_networking.html

Pod-level networking features, such as per-pod bandwidth limits, are discussed in https://docs.okd.io/3.9/admin_guide/managing_pods.html#admin-guide-manage-pods-limit-bandwidth 。


Disabling Host Name Collision Prevention For Routes and Ingress Objects
=======================================================================

In OpenShift Container Platform, host name collision prevention for routes and ingress objects is enabled by default. This means that users without the cluster-admin role can set the host name in a route or ingress object only on creation and cannot change it afterwards. 

如果允许了，那么在haproxy的acl文本文件中，只有排在上面的那个路由能够生效。一般用户只能在创建时指定host name而不能后续修改，所以这看起来是个软防护。一旦新创建的route发生了冲突，那么只能删了重建。

Because OpenShift Container Platform uses the object creation timestamp to determine the oldest route or ingress object for a given host name, a route or ingress object can hijack a host name of a newer route if the older route changes its host name, or if an ingress object is introduced.

所以是最先创建的object排在acl文本的上方。

可以选择role来赋予update的权限，或者修改master-config.yaml。


Controlling Egress Traffic
==========================

They can then deploy an egress router from the developer’s project, using a nodeSelector in the deployment configuration to ensure that the pod lands on the host with the pre-allocated static IP address. ... The egress pod’s deployment declares one of the source IPs, the destination IP of the protected service, and a gateway IP to reach the destination. After the pod is deployed, you can create a service to access the egress router pod, then add that source IP to the corporate firewall. The developer then has access information to the egress router service that was created in their project, for example, service.project.cluster.domainname.com. ... When the developer needs to access the external, firewalled service, they can call out to the egress router pod’s service in their application.

创建一个egress router pod来做流量代理。管理员需要在具体的某个节点上配置固定IP(/32)，因此这个pod需要用nodeSelector来“绑定”到固定的节点。其他Pod以service name访问这个Pod，然后这个Pod再以固定IP访问外部服务。不过 The egress router is not available for OpenShift Dedicated.

当然也可以通过 Enabling Static IPs for External Project Traffic 来将固定的外部IP绑定到namespace，来使整个namespace的容器都可以以固定IP直接对外访问，不过这会不会overkill，毕竟不是所有的服务都需要对外访问。

管理员有三种方式管控访外里流量:

  - Firewall: 针对指定namespace，进行针对pods访问外部指定IP(range)或endpoints的限制
  - Router: 也就是前面的egress router pod，可以引入安全认证，即哪些pod可以访问外部服务
  - iptables: 底层环境的修改，所以无法针对特定namespace


Using an Egress Firewall to Limit Access to External Resources
--------------------------------------------------------------

As an OpenShift Container Platform cluster administrator, you can use egress firewall policy to limit the external addresses that some or all pods can access from within the cluster,

注意，这里是说platform cluser admin，平台管理员才有权限。当然，即使一般的用户如果也有权限，那谁又会为自己过不去呢。

so that:

  - A pod can only talk to internal hosts, and cannot initiate connections to the public Internet.
  - A pod can only talk to the public Internet, and cannot initiate connections to internal hosts (outside the cluster).
  - A pod cannot reach specified internal subnets/hosts that it should have no reason to contact.

所有能够或者不能够访问的外部，是指出了容器网络的外部，因此集群的节点也属于外部范畴。

Egress policies can be set at the pod selector-level and project-level. For example, you can allow <project A> access to a specified IP range but deny the same access to <project B>. Or, you can restrict application developers from updating from (Python) pip mirrors, and force updates to only come from approved sources.

可以基于pod selector(?)或者project来设置规则，文档中给出了基于project创建规则的例子，但是没有基于pod selector的。并且oc explain egressnetworkpolicy.spec看到的属性中也没有类似selector的。

Project administrators can neither create EgressNetworkPolicy objects, nor edit the ones you create in their project.

只有平台管理员可以维护EgressNetworkPolicy，项目管理员则不行。

There are also several other restrictions on where EgressNetworkPolicy can be created:

  - The default project (and any other project that has been made global via oc adm pod-network make-projects-global) cannot have egress policy.
  - If you merge two projects together (via oc adm pod-network join-projects), then you cannot use egress policy in any of the joined projects.
  - No project may have more than one egress policy object.

简单地说，所有非隔离的项目都不能创建EgressNetworkPolicy，并且一个项目只能有一个EgressNetworkPolicy。

Violating any of these restrictions results in broken egress policy for the project, and may cause all external network traffic to be dropped.

而违反限制的话，会导致所有的访外流量被drop。

代码片段::

    {
        "kind": "EgressNetworkPolicy",
        "apiVersion": "v1",
        "metadata": {
            "name": "default"
        },
        "spec": {
            "egress": [
                {
                    "type": "Allow",
                    "to": {
                        "cidrSelector": "1.2.3.0/24"
                    }
                },
                {
                    "type": "Allow",
                    "to": {
                        "dnsName": "www.foo.com"
                    }
                },
                {
                    "type": "Deny",
                    "to": {
                        "cidrSelector": "0.0.0.0/0"
                    }
                }
            ]
        }
    }

虽然不能oc create egressnetworkpolicy，但是oc get egressnetworkpolicy和oc explain egressnetworkpolicy都可以使用。

The rules in an EgressNetworkPolicy are checked in order.

顺序添加（到ovs flows），顺序过滤。

Domain name updates are polled based on the TTL (time to live) value of the domain returned by the local non-authoritative servers. The pod should also resolve the domain from the same local nameservers when necessary, otherwise the IP addresses for the domain perceived by the egress network policy controller and the pod will be different, and the egress network policy may not be enforced as expected. Since egress network policy controller and pod are asynchronously polling the same local nameserver, there could be a race condition where pod may get the updated IP before the egress controller. Due to this current limitation, domain name usage in EgressNetworkPolicy is only recommended for domains with infrequent IP address changes.

基于域名的rule，应该确保pod和egress network policy controller用来获取域名的local non-authoritative dns server应该是相同的，否则将无法保证rule的有效性。并且考虑TTL的影响，controller对域名更新的反映不会有pod那样及时，因此ovs flows的刷新不会及时，当域名跟新时，Pod可能会出现暂时无法同域名通信的情况。

关于ovs flows，在“干净”的情况下，在table 100中有规则::

    table=100, priority=0 actions=output:2

即直接从tun0向外输出。而当添加了前面代码示例中的Policy后::

    table=100, priority=0 actions=goto_table:101

    table=101, priority=51,tcp,nw_dst=10.70.94.90,tp_dst=53 actions=output:2
    table=101, riority=51,udp,nw_dst=10.70.94.90,tp_dst=53 actions=output:2
    table=101, priority=3,ip,reg0=0x735a9,nw_dst=1.2.3.0/24 actions=output:2
    table=101, priority=2,ip,reg0=0x735a9,nw_dst=34.192.125.243 actions=output:2
    table=101, priority=2,ip,reg0=0x735a9,nw_dst=54.84.212.61 actions=output:2
    table=101, priority=1,ip,reg0=0x735a9 actions=drop
    table=101, priority=0 actions=output:2

其中 10.70.94.90是节点IP，0x735a9是所处项目的VNID（oc get netnamespaces)，34.192.125.243 和 54.84.212.61是 www.foo.com 对应的IP（nslookup) 。

The egress firewall always allows pods access to the external interface of the node the pod is on for DNS resolution. If your DNS resolution is not handled by something on the local node, then you will need to add egress firewall rules allowing access to the DNS server’s IP addresses if you are using domain names in your pods.

egress firewall会默认放行DNS解析的流量，但也主要是针对node的本地dns代理，如果Pod里配置了集群外部的DNS，则需要在policy中添加规则来放行。

Exposing services by creating routes will ignore EgressNetworkPolicy. Egress network policy service endpoint filtering is done at the node kubeproxy. When the router is involved, kubeproxy is bypassed and egress network policy enforcement is not applied. Administrators can prevent this bypass by limiting access to create routes.

不太能理解egress firewall和route能有什么关联。毕竟二者的作用路径是不一样的。


Using an Egress Router to Allow External Resources to Recognize Pod Traffic
---------------------------------------------------------------------------

The Egress router adds a second IP address and MAC address to the node’s primary network interface. If you are not running OpenShift Container Platform on bare metal, you may need to configure your hypervisor or cloud provider to allow the additional address.

Interesting，向节点的主网卡添加IP和MAC。

The egress router can run in two different modes: redirect mode and HTTP proxy mode. Redirect mode works for all services except for HTTP and HTTPS. For HTTP and HTTPS services, use HTTP proxy mode.


Deploying an Egress Router Pod in Redirect Mode
```````````````````````````````````````````````

In redirect mode, the egress router sets up iptables rules to redirect traffic from its own IP address to one or more destination IP addresses. 

代码片段::

    apiVersion: v1
    kind: Pod
    metadata:
      name: egress-1
      labels:
        name: egress-1
      annotations:
        pod.network.openshift.io/assign-macvlan: "true" 
    spec:
      initContainers:
      - name: egress-router
        image: registry.access.redhat.com/openshift3/ose-egress-router
        securityContext:
          privileged: true
        env:
        - name: EGRESS_SOURCE 
          value: 192.168.12.99/24
        - name: EGRESS_GATEWAY 
          value: 192.168.12.1
        - name: EGRESS_DESTINATION 
          value: 203.0.113.25
        - name: EGRESS_ROUTER_MODE 
          value: init
      containers:
      - name: egress-router-wait
        image: registry.access.redhat.com/openshift3/ose-pod
      nodeSelector:
        site: springfield-1 

相关解释见官方文档，其中最终要的是 **Creates a Macvlan network interface on the primary network interface, then moves it into the pod’s network project before starting the egress-router container.** ，及会先在host上创建一个macvlan子接口在默认的主网卡（或指定网卡）上，然后将macvlan子接口挪到pod的netns里。

关于如何进入pod的netns，参考https://stackoverflow.com/questions/31265993/docker-networking-namespace-not-visible-in-ip-netns-list，即::

    # (as root)
    pid=$(docker inspect -f '{{.State.Pid}}' ${container_id})
    mkdir -p /var/run/netns/
    ln -sfT /proc/$pid/ns/net /var/run/netns/$container_id
    ip netns exec "${container_id}" bash

进入后:

  - 通过ip a可以观察到pod有两个网口，eth0和macvlan，分别用于接入ovs网络和host的eth0（即物理网络），macvlan的IP(/prefix)即由EGRESS_SOURCE指定，而default route由EGRESS_GATEWAY指定。
  - 通过iptables -t nat -S可以观察到针对所有从eth0（即容器网络）来的流量都做了DNAT，destination由EGRESS_DESTINATION指定，并且从macvlan接口出去时会SNAT为EGRESS_SOURCE指定的IP。

The egress router setup is performed by an "init container" created from the openshift3/ose-egress-router image, and that container is run privileged so that it can configure the Macvlan interface and set up iptables rules. After it finishes setting up the iptables rules, it exits and the openshift3/ose-pod container will run (doing nothing) until the pod is killed.

egress-router(registry.access.redhat.com/openshift3/ose-egress-router) 创建了macvlan，及iptables规则，而后续的egress-router-wait(registry.access.redhat.com/openshift3/ose-pod)则什么都不做，类似一个占位符，只是为了保持已创建的配置能被hold。


Redirecting to Multiple Destinations
````````````````````````````````````

相较与之前，代码片段改变的地方是::

    - name: EGRESS_DESTINATION 
      value: |
        80   tcp 203.0.113.25
        8080 tcp 203.0.113.26 80
        8443 tcp 203.0.113.26 443
        203.0.113.27

EGRESS_DESTINATION的每一行需要是如下格式的:

  - <port> <protocol> <IP address>
  - <port> <protocol> <IP address> <remote port>
  - <fallback IP address>

即 [-p PROTOCOL --dport PORT] -j DNAT --to-destination REMOTE_IP [--dport REMOTE_PORT]


Deploying an Egress Router HTTP Proxy Pod
`````````````````````````````````````````

In HTTP proxy mode, the egress router runs as an HTTP proxy on port 8080. This only works for clients talking to HTTP or HTTPS-based services.

必须为8080。

相较与之前，代码片段改变的地方是::

  - name: egress-router-proxy
    image: registry.access.redhat.com/openshift3/ose-egress-http-proxy
    env:
    - name: EGRESS_HTTP_PROXY_DESTINATION 
      value: |
        !*.example.com
        !192.168.1.0/24
        *

关于EGRESS_HTTP_PROXY_DESTINATION的配置(yaml)，规则为:

  - 支持IP，IP/prefix，域名，及泛域名
  - !代表deny，不加!则代表allow
  - If the last line is \*, then anything that hasn’t been denied will be allowed. Otherwise, anything that hasn’t been allowed will be denied. 

    即最后一行为\*，则通配allow，如果没有\*，则通配deny

pod里将运行squid作为代理服务，squid.conf的内容大致为::

    http_port 8080
    cache deny all
    access_log none all
    debug_options ALL,0
    shutdown_lifetime 0
    
    acl dest1 dstdomain .example.com
    http_access deny dest1
    
    acl dest2 dst 192.168.1.0/24
    http_access deny dest2
    
    http_access allow all

作为egress-router-proxy pod的用户，其他的pod需要配置环境变量http_proxy or https_proxy (export http_proxy=http\://SERVICE:8080)。

可以使用rc来提升服务质量，但副本数只能为1，毕竟同一时间内，EGRESS_SOURCE对应的IP只能挂在一个地方。


Using iptables Rules to Limit Access to External Resources
----------------------------------------------------------

OpenShift Container Platform does not provide a way to add custom iptables rules automatically, but it does provide a place where such rules can be added manually by the administrator. Each node, on startup, will create an empty chain called OPENSHIFT-ADMIN-OUTPUT-RULES in the filter table.

自己动手（在每个节点的filter表中，FORWARD下的OPENSHIFT-ADMIN-OUTPUT-RULES链中添加），丰衣足食。


Enabling Static IPs for External Project Traffic
================================================

（虽然我很想吐槽它的单点性，毕竟我在3.5的基础上实现了HA）

相关操作很简单::

    $ oc patch netnamespace MyProject -p '{"egressIPs": ["192.168.1.100"]}'
    $ oc patch hostsubnet NODE_NAME -p '{"egressIPs": ["192.168.1.100", "192.168.1.200"]}'

其中192.168.1.200可能是其他netnamespace/project使用的Static IP。

相关的"黑魔法"::

    # 当容器所在节点不是egress IP所在节点时，需要先过这部分处理
    # 10.70.94.92为egress IP所在节点的隧道IP
    table=100, priority=100,ip,reg0=0x735a9 actions=move:NXM_NX_REG0[]->NXM_NX_TUN_ID[0..31],set_field:10.70.94.92->tun_dst,output:1

    # gress IP所在节点, ovs部分
    # set_field eth_dst指向节点的tun0 mac
    # set_field pkt_mark将用于后续的iptables规则
    table=100, priority=100,ip,reg0=0x735a9 actions=set_field:a6:7f:78:33:27:98->eth_dst,set_field:0x10735a8->pkt_mark,goto_table:101
    table=101, priority=51,tcp,nw_dst=10.70.94.92,tp_dst=53 actions=output:2
    table=101, priority=51,udp,nw_dst=10.70.94.92,tp_dst=53 actions=output:2
    table=101, priority=0 actions=output:2

    # gress IP所在节点,  iptables部分
    # -m mark --mark 0x10735a8 与前面set_field pkt_mark呼应
    -A POSTROUTING -m comment --comment "rules for masquerading OpenShift traffic" -j OPENSHIFT-MASQUERADE
    -A OPENSHIFT-MASQUERADE -s 10.128.0.0/18 -m mark --mark 0x10735a8 -j SNAT --to-source 192.168.1.100
    -A OPENSHIFT-MASQUERADE -s 10.128.0.0/18 -m comment --comment "masquerade pod-to-service and pod-to-external traffic" -j MASQUERADE

Unlike the egress router, this is subject to EgressNetworkPolicy firewall rules.

受制于EgressNetworkPolicy，因为它们的作用链有重叠部分。


Enabling Multicast
==================

::
    $ oc annotate netnamespace <namespace> \
        netnamespace.network.openshift.io/multicast-enabled=true
    
    $ oc annotate netnamespace <namespace> \
        netnamespace.network.openshift.io/multicast-enabled-

很容易实现，用OVS。


Enabling NetworkPolicy
======================

需要ovs有状态防火墙支持，需要linux内核4.3以上，待测试。


Enabling HTTP Strict Transport Security
=======================================

HSTS works only with secure routes (either edge terminated or re-encrypt). The configuration is ineffective on HTTP or passthrough routes.

To enable HSTS to a route, add the haproxy.router.openshift.io/hsts_header value to the edge terminated or re-encrypt route::

    apiVersion: v1
    kind: Route
    metadata:
      annotations:
        haproxy.router.openshift.io/hsts_header: max-age=31536000;includeSubDomains;preload
