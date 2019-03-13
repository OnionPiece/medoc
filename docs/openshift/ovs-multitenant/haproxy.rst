******************************************
基于OVS多租户的OpenShift网络N板斧——haproxy
******************************************

太长不看版
==========

OpenShift的Router Pod中启动的haproxy，会监听master节点的80和443端口，接受针对集群内Service的HTTP/HTTPS访问。我们添加的Route会在haproxy的相关配置文件中添加一个FQDN + path 到Service对应的haproxy backend的映射，而backend中的各个server即对应Pod。七层的请求在被haproxy接受后，通过ACL匹配出对应的haproxy backend，并丢过去进行处理。经过haproxy的负载均衡处理，请求就直接指向了某一个具体的Pod。


前言
====

Haproxy在OpenShift的网络中，主要用于Router Pod，担当着Cluster内容器服务的L7 gateway，将针对Service的HTTP/HTTPS访问进行”负载均衡”转发。Haproxy的配置与OpenShift的Route，Service，Pod等资源有所关联:

  - Route对应的是一条match特定URL的规则，这个规则将返回特定的backend
  - 而这个backend就是Service
  - backend中server就是Pod

当然一个Route可以配置多个alternateBackends，即多个Service。而在haproxy配置文件中backend的表现上来看，只是在同一个backend下的server会扩展出多个Service的Pod。同一个Service下的Pod所对应的server，具有相同的weight。


节点端口的监听
==============

在Router Pod的属性中，我们可以看到配置了hostNetwork，以及等值的hostPort与containerPort属性对。这种配置方式实现了将节点的端口直接映射到容器的端口，使得容器可以直接监听节点的TCP 80, 443等端口。因此，如果只是以监听端口80和443的角度来看，Router Pod里的haproxy可以理解为是直接启动在节点上的。


HTTP
====

对于HTTP服务，haproxy使用frontend public去监听（80端口），其主要配置有::

    # check if we need to redirect/force using https
    acl secure_redirect base,map_beg(/var/lib/haproxy/conf/\
          os_edge_http_redirect.map) -m found
    redirect scheme https if secure_redirect

    # check if it is an edge route exposed insecurely.
    acl edge_http_expose base,map_beg(/var/lib/haproxy/conf/\
          os_edge_http_expose.map) -m found
    use_backend be_edge_http_%[base,map_beg(/var/lib/haproxy/conf/\
          os_edge_http_expose.map)] if edge_http_expose

    # map to http backend
    # Search from most specific to general path (host case).
    acl http_backend base,map_beg(/var/lib/haproxy/conf/os_https_be.map) \
          -m found
    use_backend be_http_%[base,map_beg(/var/lib/haproxy/conf/\
          os_http_be.map)] if http_backend

    default_backend openshift_default

与上面三处的 *acl* 相关的一些知识（安装haproxy后，可以通过查看查看haproxy的本地文档进行了解，如 */usr/share/doc/haproxy/configurations.txt.gz* :

  - base::

      This returns the concatenation (string) of the first Host header and
      the path part of the request, which starts at the first slash and ends
      before the question mark.

    即该参数返回host + path 的string拼接，如www.example.com/foo/bar。

  - map_beg::

      map_<match_type>(<map_file>[,<default_value>])

      # for map_beg, <output_type> is str

      Search the input value from <map_file> using the <match_type>
      matching method, and return the associated value converted to the
      type <output_type>.
      ...
      The file contains one key + value per line.
      ...

    对文件（如 */var/lib/haproxy/conf/os_https_be.map* ）中的key-values进行匹配，
    如果，如果发现某个key以 *base* 的结果开头，那么就返回value。

  - -m::

      The "-m" flag is used to select a specific pattern matching method on
      the input sample.

  - found::

      only check if the requested sample could be found in the stream, but
      do not compare it against any pattern.

  - use_backend::

      Switch to a specific backend if/unless an ACL-based condition is
      matched.

总结起来，就是对于HTTP请求，haproxy会从三个key-value的文件

  - /var/lib/haproxy/conf/os_edge_http_redirect.map
  - /var/lib/haproxy/conf/os_edge_http_expose.map
  - /var/lib/haproxy/conf/os_https_be.map

中依次去，针对请求的FQDN + path去匹配key，如果找到了那么就

  - 替换为HTTPS转发，或者
  - 转发到前缀"be_edge_http\_" + value的backend去处理，或者
  - 转发到前缀"be_http\_" + value的backend去处理

如果都不匹配就转到openshift_default backend去处理。这里的FQDN由用户的信息 + 泛域名组成。因此匹配的key看起来像::

    Namespace-Service.example.com/path

    # 例如用户的namespace为Hello，Service为world，path 是 /，那么key则是:
    Hello-world.example.com/

而对于backend中的配置，目前我观察到的内容包括:

  - 设置HTTP headers，如 *X-Forwarded-Host* 等
  - 会对server（Pod）进行间隔为5s的4层健康检查
  - 当前配置的 *balance* 始终为 *leastconn* 。这可能是一个我们所用的版本的bug，因为无论是 *sessionAffinity* ，还是 *alternateBackends* ，都没有改变该值。而以我个人的预期来看，在这两种情况下，该值应该变为 *source* 以及 *roundrobin* 。
