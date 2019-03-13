.. _customize_iptables_proxier_v2:

**********************************
二次修改OpenShift iptables proxier
**********************************

在 :ref:`初次修改OpenShift iptables proxier <customize_iptables_proxier>` 的基础上，本篇尝试二次修改，以实现以下目标:

  - externalIPs可以在不被SNAT的情况下被Pod的veth接收
  - externalIPs的流量做入口检查，当且仅当流量的协议，目的端口与Service匹配时，流量会被放行，否则drop


意义有限的第一次修改
====================

在初次修改的代码基础上，进行了如下的修改::

    diff --git a/vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go b/vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go
    index ad9bcb1..23da10e 100644
    --- a/vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go
    +++ b/vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go
    @@ -73,6 +73,9 @@ const (

        // the mark-for-drop chain
        KubeMarkDropChain utiliptables.Chain = "KUBE-MARK-DROP"
    +
    +	// the service external ips chain
    +	kubeExternalIPsChain utiliptables.Chain = "KUBE-EXTERNAL-IPS"
     )
     
     // IPTablesVersioner can query the current iptables version.
    @@ -846,6 +849,16 @@ func (proxier *Proxier) syncProxyRules() {
                }
        }
     
    +        // NOTE(lizk1989): create and link the kube external ips chain.
    +        if _, err := proxier.iptables.EnsureChain(utiliptables.TableFilter, kubeExternalIPsChain); err != nil {
    +                glog.Errorf("Failed to ensure that %s chain %s exists: %v", utiliptables.TableFilter, kubeExternalIPsChain, err)
    +                return
    +        }
    +        if _, err := proxier.iptables.EnsureRule(utiliptables.Prepend, utiliptables.TableFilter, utiliptables.ChainInput, "-j", string(kubeExternalIPsChain)); err != nil {
    +                glog.Errorf("Failed to ensure that %s chain %s jumps to %s: %v", utiliptables.TableFilter, utiliptables.ChainInput, kubeExternalIPsChain, err)
    +                return
    +        }
    +
        // Get iptables-save output so we can check for existing chains and rules.
        // This will be a map of chain name to chain with rules as stored in iptables-save/iptables-restore
        existingFilterChains := make(map[utiliptables.Chain]string)
    @@ -1029,16 +1042,45 @@ func (proxier *Proxier) syncProxyRules() {
     				        endpoints = append(endpoints, ep)
     					}
     					for _, endpoint := range endpoints {
    -					        args := []string{
    +					        egressArgs := []string{
     					                "-m", protocol, "-p", protocol,
     					                "-s", fmt.Sprintf("%s/32", strings.Split(endpoint.ip, ":")[0]),
     					                "!", "-d", proxier.clusterCIDR,
     					                "-j", "SNAT", "--to-source", externalIP,
     					        }
    -						if _, err := proxier.iptables.EnsureRule(utiliptables.Prepend, utiliptables.TableNAT, utiliptables.ChainPostrouting, args...); err != nil {
    +						if _, err := proxier.iptables.EnsureRule(utiliptables.Prepend, utiliptables.TableNAT, utiliptables.ChainPostrouting, egressArgs...); err != nil {
     						        glog.Errorf("Failed to ensure egress SNAT rule for externalIPs for Service %s", svcName.String())
     						        return
     						}
    +					        ingressArgs := []string{
    +					                "-m", protocol, "-p", protocol,
    +					                "!", "-s", proxier.clusterCIDR,
    +					                "-d", fmt.Sprintf("%s/32", strings.Split(endpoint.ip, ":")[0]),
    +					                "-j", "ACCEPT",
    +					        }
    +						if _, err := proxier.iptables.EnsureRule(utiliptables.Prepend, utiliptables.TableNAT, utiliptables.ChainPostrouting, ingressArgs...); err != nil {
    +						        glog.Errorf("Failed to ensure ingress ACCEPT rule for externalIPs for Service %s", svcName.String())
    +						        return
    +						}
    +                                                firewallArgs := []string{
    +					                "-m", protocol, "-p", protocol,
    +							"-d", fmt.Sprintf("%s/32", externalIP),
    +							"--dport", fmt.Sprintf("%d", svcInfo.port),
    +					                "-j", "ACCEPT",
    +					        }
    +						if _, err := proxier.iptables.EnsureRule(utiliptables.Prepend, utiliptables.TableFilter, kubeExternalIPsChain, firewallArgs...); err != nil {
    +						        glog.Errorf("Failed to ensure ingress ACCEPT rule for externalIPs for Service %s in chain %v", svcName.String(), kubeExternalIPsChain)
    +						        return
    +						}
    +                                                firewallDropArgs := []string{
    +					                "-m", protocol, "-p", protocol,
    +							"-d", fmt.Sprintf("%s/32", externalIP),
    +					                "-j", "DROP",
    +					        }
    +						if _, err := proxier.iptables.EnsureRule(utiliptables.Append, utiliptables.TableFilter, kubeExternalIPsChain, firewallDropArgs...); err != nil {
    +						        glog.Errorf("Failed to ensure ingress ACCEPT rule for externalIPs for Service %s in chain %v", svcName.String(), kubeExternalIPsChain)
    +						        return
    +						}
     					        installedEgressSNAT = true
     					}
     			        }


上述的修改对于单点是通的，无论是入还是出。这里的单点是指keepalived与Service后面的Pod都在同一个节点上，但是这样做并没有实际意义。


更多的考虑
==========

当扩展到更实际的场景，如keepalived在节点A,B,C上，而Service的endpoints在节点D,E,F上时，我们需要考虑更棘手的问题—— centralized SNAT(C-SNAT):

  - 从外部来的，针对externalIPs的访问，在集群边界上只有一个入口。对应的，以externalIPs为出口IP的流量，在集群边界上也应该只有一个出口，否则:

    - 交换机的MAC表可能会发生频繁MAC记录更新
    - 由于MAC表的变动等原因，来自外部的访问数据包可能会被路由到不同的节点，不同节点上的iptables实例很可能会将数据包分发到不同的Pod上，从而导致链接无法建立等问题

  - 对应的，为了使得出口唯一，即C-SNAT，需要让所有绑定了externalIPs的Pod的访外流量都能将流量路由到唯一出口节点上。并且考虑到keepalived提供的主备能力，VIP可能漂移，那么相应的，C-SNAT也会漂移，对此，Pod的访外流量需要有途径能够灵活的获取到达C-SNAT的下一跳
  - 考虑到容器朝生幕死的特点，任何基于IP的来确定流量是否需要被路由到C-SNAT的方式都会受到挑战，即伴随这容器的更迭，相应的规则需要被调整

在综合考虑以及测试下，个人认为比较合适的处理是，将相关的Pod的对外的主动或被动流量，通过openshift SDN实现将数据路由到C-SNAT节点，然后统一做SNAT处理，以externalIPs出去。


测试环境及workaround
--------------------

测试环境中有两个节点A和B，绑定externalIPs的Service有两个Pod c和d，分别位于A和B。并且externalIP是绑定在A的默认路由出口网卡上。测试环境使用了redhat/ovs-multitenant网络插件。通过添加如下的OVS flows可以使得Pod的主动和被动访外流量能够路由到C-SNAT::

    # A节点:
    # table 0:
    priority=160,ip,in_port=1,nw_src=10.128.0.0/18 actions=move:NXM_NX_TUN_ID[0..31]->NXM_NX_REG0[],goto_table:100

    # B节点:
    # table 0:
    priority=160,ip,in_port=1,nw_dst=10.128.0.0/18 actions=move:NXM_NX_TUN_ID[0..31]->NXM_NX_REG0[],goto_table:10
    # table 100:
    ip,nw_src=10.128.11.100 actions=set_field:4a:2e:a7:e0:60:79->eth_dst,move:NXM_NX_REG0[]->NXM_NX_TUN_ID[0..31],set_field:192.168.39.238->tun_dst,output:1

其中，Cluster CIDR为10.128.0.0/18，IP 10.128.11.100为Pod d的IP，MAC地址4a:2e:a7:e0:60:79为节点A上的tun0的MAC，IP 192.168.39.238为节点A的IP。


代码化的思路
------------

上述的workarounds中，最主要的变量有三个，并且都集中在 table 100:

  - nw_src=${POD_IP}
  - set_field:${C-SNAT-TUN0-MAC}->eth_dst
  - set_field:${C-SNAT-NODE-IP}->tun_dst

*POD_IP* 在节点上进行Service的处理时就可以获取，而难点在于C-SNAT的相关数据，tun0的MAC和Node IP。这涉及到几个问题:

  - 对于OVS flows，相关数据是否具有初始化数据，或者默认数据
  - 当keepalived发生主备切换时，相关数据如何更新，flow如何更新
  - 由于keepalived是不抗脑裂的，因此当发生脑裂时，多个Master会如何影响flow

可以想象到的思路是，通过配置keepalived的nitify script，当Master产生后，触发某种事件接口，并由OpenShift处理，来更新相应的flows。
