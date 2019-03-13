**************************
两层负载均衡下Router的修改
**************************


负载均衡的陷阱
==============

为了达到集群的高可用和负载均匀的目的，我们在集群外部搭建了负载均衡。而负载均衡对于OpenShift当前提供的功能，却有着一定的反作用。最突出的问题就是，Service的sessionAffinity，无法在处理7层访问时起到作用。相应的现象就是，即使有多个后端，Router Pod也总是始终将请求路由到某一个Pod上，而不会负载到其他Pod上。

注: 为一个Route添加annotation，haproxy.router.openshift.io/balance，可以修改其在Router Pod haproxy配置中的balance，可选值包括leastconn, roundrobin, source。

注: 由于cookie的原因，在浏览器端测试时，可能无法明显的看出不同负载均衡算法的不同，这是需要额外在为Route添加一条annotation，haproxy.router.openshift.io/disable_cookies: "true"。


问题&解决办法
=============

源IP
----

我们当前环境中架设的负载均衡（无论是F5，还是haproxy）工作在fullnat模式，即Master Node接受到的请求的源IP是负载均衡内测的IP。所以，Router Pod接受到的IP始终都是一个，也因此配置成balance source后，来自外部的7层请求只会被路由到一个Pod上，达不到负载均摊的目的。

以下内容将只针对haproxy。


balance hdr
-----------

haproxy提供了除上述三个基本方法外的其他负载均衡算法，其中 *hdr* 可以从7层请求的Headers中提取字段（如hdr(X-Forwarded-For)，并用于hash，如果一个请求中没有指定的header，那么将退化到roundrobin。 这是一个比较好的方法，一方面我们本来就有提供源IP的功能需求，因此外部负载均衡会将Client IP放在X-Forwarded-For中，另一方面对现有架构不会有任何的改动，算是具有比较好的场景适应性。

OpenShift并不直接支持hdr这样的balance算法，但是可以通过自定义router template来实现。参考 https://docs.openshift.com/container-platform/3.5/install_config/router/customized_haproxy_router.html

比较偷懒的修改是::

    ...
      {{ with $balanceAlgo := index $cfg.Annotations "haproxy.router.openshift.io/balance" }}
        {{ with $matchValue := (matchValues $balanceAlgo "roundrobin" "leastconn" "source" ) }}
    balance {{ $balanceAlgo }}
        {{ else }}
    balance hdr(X-Forwarded-For)
        {{ end }}
      {{ else }}
    ...

参考官方文档，建议的做法是用configMap生成一个template，然后在Router DC中修改TEMPLATE_FILE来指向模板文件的挂载位置。修改后，需要重新部署Router Pod。


option forwardfor
-----------------

当前Router Pod haproxy的配置中，后端有option forwardfor，该字段会向请求中加入HTTP Header —— X-Forwarded-For。在两层负载均衡架构中，外层负载均衡很有可能对请求添加了X-Forwarded-For，并且添加的将是实际的client IP；而在此基础上，如果内层负载均衡再配置option forwardfor，那么将导致server收到的最终的X-Forwarded-For header中将有两个IP，如::

    ('X-Forwarded-For', u'20.0.0.4,20.0.0.3')

经实验，这样并不影响balance hdr(X-Forwarded-For)，但是很明显，内层的负载均衡IP不应该被用户所看到。因此Router Pod haproxy的option forwardfor 在两层负载均衡架构下的实用意义不大。
