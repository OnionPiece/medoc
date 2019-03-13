**************************************
基于OVS多租户的OpenShift网络N板斧——dns
**************************************


这里主要考虑容器以local domain方式访问Service场景下的DNS处理上的一些细节。这种访问，类似::

    curl http://flask.happy.svc.cluster.local/

其中flask是我的Service名，happy是我的namespace，而后面的svc.cluster.local属于集群内的local domain。


Pod内的/etc/resolv.conf
=======================

容器的resolver会根据/etc/resolv.conf的配置向DNS服务器发起请求，该配置文件的内容大致为::

    search NAMESPACE.svc.cluster.local svc.cluster.local cluster.local
    nameserver DNS_IP
    nameserver EXTERNAL_DNS
    options ndots:5

其中:

  - DNS_IP 是在node-config.yaml中进行配置的，对应字段为dnsIP。一般的有效值有节点的IP，或者Cluster Service的第一个IP，如172.30.0.1。
  - *ndots:N* 要求DNS请求返回的结果如果包含了至少N个点，那么就认为结果正确；否则，认为这个结果并不属于我们想要的域名。

service + namespace + svc.cluster.local 过程了集群内DNS可识别的FQDN, 且也只能由集群内的DNS进行解析（并且也只有这namespace + svc.cluster.local的domain 经测试是对用户Service有效的）。因此，DNS请求将由容器发向所在节点。

关于容器内的/etc/resolv.conf生成的配置，可以参考 https://docs.openshift.org/1.5/install_config/install/prerequisites.html#prereq-dns 


计算节点上的dnsmasq
===================

经过OVS处理，来自容器的DNS请求会通过tun0进入节点的网络空间，并由计算节点上运行的 *dnsmasq* 进程接受并处理。在 *dnsmasq* 的默认配置文件中，配置 *conf-dir=/etc/dnsmasq.d* 指向了实际的配置文件位置。该路径下，只有一个文件，即 */etc/dnsmasq.d/origin-dns.conf* ，其内容大致为::

    no-resolv
    domain-needed
    server=/cluster.local/172.30.0.1
    no-negcache
    max-cache-ttl=1

相应的解释为:

  - no-resolv: dnsmasq不会读取 /etc/resolv.conf的内容
  - domain-needed: dnsmasq不会只发hostname，即会带着domain部分
  - server: 添加了集群的DNS server，并指定domain
    （集群的DNS server 将以Service CIDR的第一个IP为地址）
  - no-negcache: 并不会缓存失败的DNS请求，如果缓存了，则代表认识请求的域名不存在
  - max-cache-ttl: 缓存的中的DNS记录的时效性，单位为秒

之后计算节点的本地的 *dnsmasq* 进程会将DNS请求进一步转发到上游的DNS服务器，即 172.30.0.1。在路由后，iptables将发挥作用，对DNS请求进行“负载均衡“处理，并最终转向master节点，参考 :ref:`容器以local domain访问Service <dns_local_domain_iptables>` 。

在iptables处理后，DNS请求将不再进入OVS，而是直接在节点间投递。
