.. _customize_iptables_proxier:

**********************************
尝试修改OpenShift iptables proxier
**********************************

前言
====

这篇的目的，主要是记录我第一次尝试修改OpenShift代码的心路历程。但作为前置条件，我已经明确了以下几点:

  - externalIPs这个功能是网络插件无关的，我试验了ovs-multitenant和flanneld，它们的实现机制都基本一致
  - 在一个模拟环境中，在为iptables添加了现有的OpenShift环境中相关的iptables规则的基础上，可以稍加改动来达成预设的目的

另外，一个不成熟的想法是：在具有一定基础知识和使用经验的基础上，如果一个项目的代码还是很难看懂，那么一定是项目代码写的太烂了。


流水帐：代码切入点
==================

对于一个陌生的项目，想要阅读它的代码，寻找切入点是比较难的，因为可选的入口太多了:

  - API入口
  - service启动流程
  - 数据库接口与ORM
  - ...

更何况，我此前也只看了半天的《Go入门指南》，因此对于代码行为，有些只能靠猜。但好在成熟的项目有一个好处，即旁证博引，你可以从更多的代码逻辑中，摸索出线索，而对于孤例则会有很好的注释说明。

但好在我们这次的目的很明确，即修改externalIPs，或者说是修改iptables在POSTROUTING链上的行为，因此对于入口的搜寻也很明确。


使用grep来寻找代码切入点
------------------------

(以下内容均在origin下进行。值得说明的是，之所以用流水帐的方式来记录源码学习过程，是因为源码的学习本身就是一个反复入栈/出栈的过程，你需要不断的寻找线索，直到与某一个可信的流程环节接轨，才能认为是建立了可信的线索地图。之后才是根据具体的方向，向子分支去拓展细节的摸索)

*grep -nr 'externalIPs' .* 帮我定位到三个可能的代码入口:

  - pkg/proxy/userspace/proxier.go
  - vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go
  - vendor/k8s.io/kubernetes/pkg/proxy/userspace/proxier.go

在并不明确哪一个是潜在目标的情况下，只能选择其中一个先看。在 pkg/proxy/userspace/proxier.go 中，我观察到两个函数，openPortal 和 OnServiceUpdate。其中 openPortal 大概长这样::

    func (proxier *Proxier) openPortal(service proxy.ServicePortName, info *ServiceInfo) error {
            err := proxier.openOnePortal(info.portal, info.protocol, proxier.listenIP, info.proxyPort, service)
            if err != nil {
                    return err
            }
            for _, publicIP := range info.externalIPs {
                    err = proxier.openOnePortal(portal{net.ParseIP(publicIP), info.portal.port, true}, info.protocol, proxier.listenIP, info.proxyPort, service)
                    if err != nil {
                            return err
                    }
            }

我知道的是: openPortal 是函数名，proxy.ServicePortName 和 ServiceInfo 是参数，error 返回值类型。而至于 Proxier，我猜测是类似类的存在，因此openPortal可能认为是个类方法。

在 pkg/proxy/userspace/proxier.go 中，方法 NewProxier 将产生结构体 Proxier。而调用 NewProxier 的地方有:

  - pkg/cmd/server/kubernetes/node.go
  - vendor/k8s.io/kubernetes/cmd/kube-proxy/app/server.go

继续摸石头过河，在 pkg/cmd/server/kubernetes/node.go 中，调用 NewProxier 的函数是 RunProxy ，大概长这样::

    switch c.ProxyConfig.Mode {
    case componentconfig.ProxyModeIPTables:
            proxierIptables, err := iptables.NewProxier(...)
            ...
    // periodically sync k8s iptables rules
    go utilwait.Forever(proxier.SyncLoop, 0)

(这里的proxier.SyncLoop将在后续提到)

其中 iptables 为::

    import (
            ...
            "k8s.io/kubernetes/pkg/proxy/iptables"
            ...
    )

这里没有别名，似乎说明可以用模块名可以表达为 path/module 。并且，这里也说明我们之前找寻的与externalIPs相关的处理代码应该是在 vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go 中。但即使到了这里，我们也不必着急到 vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go 去看相关的代码片段，因为我们还是不能确定是正轨，需要向上游寻找源头来进行确认。


向上寻找“源头”
--------------

进一步地，调用 RunProxy 的函数是 pkg/cmd/server/start/start_node.go 中的 StartNode::

    if components.Enabled(ComponentProxy) {
            ...
            config.RunProxy()
            ...

我没有进一步细究 components.Enabled 的相关逻辑，不过作为参考，node-config.yaml中指明了使用iptables proxy，那么我猜测proxy应该是enabled了的::

    proxyArguments:
      proxy-mode:
         - iptables

以下是对 StartNode 调用者的追溯，代码片段被省略::

    func (o NodeOptions) RunNode() error {
            if err := StartNode(*nodeConfig, o.NodeArgs.Components); err != nil {

    func (o NodeOptions) StartNode() error {
            if err := o.RunNode(); err != nil {

    func (options *NodeOptions) Run(c *cobra.Command, errout io.Writer, args []string) {
            if err := options.StartNode(); err != nil {

    // NewCommandStartNode provides a CLI handler for 'start node' command
    func NewCommandStartNode(basename string, out, errout io.Writer) (*cobra.Command, *NodeOptions) {
            options := &NodeOptions{
                    ExpireDays: crypto.DefaultCertificateLifetimeInDays,
                    Output:     out,
            }
            cmd := &cobra.Command{
                    Use:   "node",
                    Short: "Launch a node",
                    Long:  fmt.Sprintf(nodeLong, basename),
                    Run: func(c *cobra.Command, args []string) {
                            options.Run(c, errout, args)

追溯到这里，由 NewCommandStartNode 那行注释可以关联到 *openshift node start* 命令，这似乎预示着已经追溯到服务的启动环节了。在确认了”源头“后，可以回到 vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go 中去寻找 externalIPs 的处理代码，寻找相关函数的调用入口。


处理代码的调用入口
------------------

在 vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go 中，externalIPs 的处理代码在函数 syncProxyRules中，大致为::

    // This is where all of the iptables-save/restore calls happen.
    // The only other iptables rules are those that are setup in iptablesInit()
    // assumes proxier.mu is held
    func (proxier *Proxier) syncProxyRules() {
            ...
            // Build rules for each service.
            for svcName, svcInfo := range proxier.serviceMap {
                    ...
                    // Create the per-service chain, retaining counters if possible.
                    svcChain := servicePortChainName(svcName, protocol)  // utiliptables.Chain("KUBE-SVC-" + portProtoHash(s, protocol))
                    ...
                    // Capture externalIPs.
                    for _, externalIP := range svcInfo.externalIPs {
                            ...
                            } // We're holding the port, so it's OK to install iptables rules.
                            args := []string{
                                    "-A", string(kubeServicesChain),
                                    "-m", "comment", "--comment", fmt.Sprintf(`"%s external IP"`, svcName.String()),
                                    "-m", protocol, "-p", protocol,
                                    "-d", fmt.Sprintf("%s/32", externalIP),
                                    "--dport", fmt.Sprintf("%d", svcInfo.port),
                            }
                            ...
                            dstLocalOnlyArgs := append(args, "-m", "addrtype", "--dst-type", "LOCAL")
                            // Allow traffic bound for external IPs that happen to be recognized as local IPs to stay local.
                            // This covers cases like GCE load-balancers which get added to the local routing table.
                            writeLine(natRules, append(dstLocalOnlyArgs, "-j", string(svcChain))...)

接下来寻找调用入口，一共有三个疑似入口::

    // OnEndpointsUpdate takes in a slice of updated endpoints.
    OnEndpointsUpdate

    // OnServiceUpdate tracks the active set of service proxies.
    // They will be synchronized using syncProxyRules()
    OnServiceUpdate

    // SyncLoop runs periodic work.  This is expected to run as a goroutine or as the main loop of the app.  It does not return.
    SyncLoop
        // Sync is called to immediately synchronize the proxier state to iptables
        Sync
            proxier.syncProxyRules()

我选择 SyncLoop 作为线索目标，因为作为 periodic work ，一定是会和服务流程直接挂钩的，并且对于已经添加了externalIPs的Service也便于测试；而如果去追踪前两个与事件触发相关的函数，则需要进一步深入相关的事件机制，就目前而言，没必要扩大战场。

而 SyncLoop 在前面所看到的 pkg/cmd/server/kubernetes/node.go 的代码中也恰巧有关联，在 RunProxy 函数中::

    // periodically sync k8s iptables rules
    go utilwait.Forever(proxier.SyncLoop, 0)

如果想要进一步追踪 OnEndpointsUpdate 和 OnServiceUpdate ，可以尝试先了解函数的注册位置，在 vendor/k8s.io/kubernetes/pkg/proxy/config/config.go 中::

    func (c *EndpointsConfig) RegisterHandler(handler EndpointsConfigHandler) {
            ...
            handler.OnEndpointsUpdate(instance.([]api.Endpoints))

    func (c *ServiceConfig) RegisterHandler(handler ServiceConfigHandler) {
            ...
            handler.OnServiceUpdate(instance.([]api.Service))

但目前驱动的事件是什么，我还不知道。


拼凑改动代码
============

在追踪完相关代码位置上下游的基础上，下一步就是尝试修改代码了。

没有写过go语言，不太清楚项目的代码规范，那么想要做代码改动的话，最直接的方式就是就地取材，拼凑代码。

以下通过 git diff 展示了在release-1.5基础上的代码改动::

    diff --git a/vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go b/vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go
    index cfa3c36..eec2b39 100644
    --- a/vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go
    +++ b/vendor/k8s.io/kubernetes/pkg/proxy/iptables/proxier.go
    @@ -969,6 +969,9 @@ func (proxier *Proxier) syncProxyRules() {
                    }
                    writeLine(natRules, append(args, "-j", string(svcChain))...)
    +
    +               // NOTE(lizk1989) Used to install SNAT rules for pods backed to a service with externalIPs
    +               installedEgressSNAT := false
    +
                    // Capture externalIPs.
                    for _, externalIP := range svcInfo.externalIPs {
                            // If the "external" IP happens to be an IP that is local to this
    @@ -1017,6 +1020,29 @@ func (proxier *Proxier) syncProxyRules() {
                            // Allow traffic bound for external IPs that happen to be recognized as local IPs to stay local.
                            // This covers cases like GCE load-balancers which get added to the local routing table.
                            writeLine(natRules, append(dstLocalOnlyArgs, "-j", string(svcChain))...)
    +
    +                       // NOTE(lizk1989): Allow pods backed to a service with external IPs, to use first external IP to access external network.
    +                       if !installedEgressSNAT {
    +                               if len(proxier.clusterCIDR) > 0 {
    +                                       endpoints := make([]*endpointsInfo, 0)
    +                                       for _, ep := range proxier.endpointsMap[svcName] {
    +                                               endpoints = append(endpoints, ep)
    +                                       }
    +                                       for _, endpoint := range endpoints {
    +                                               args := []string{
    +                                                       "-m", protocol, "-p", protocol,
    +                                                       "-s", fmt.Sprintf("%s/32", strings.Split(endpoint.ip, ":")[0]),
    +                                                       "!", "-d", proxier.clusterCIDR,
    +                                                       "-j", "SNAT", "--to-source", externalIP,
    +                                               }
    +                                               if _, err := proxier.iptables.EnsureRule(utiliptables.Prepend, utiliptables.TableNAT, utiliptables.ChainPostrouting, args...); err != nil {
    +                                                       glog.Errorf("Failed to ensure egress SNAT rule for externalIPs for Service %s", svcName.String())
    +                                                       return
    +                                               }
    +                                               installedEgressSNAT = true
    +                                       }
    +                               }
    +                       }
                    }

                    // Capture load-balancer ingress.

PS: git diff 对于过长的一行会truncate，此时可以通过命令 *GIT_PAGER='' git diff* 来获得完整的输出。

思路很简单:

  - 在原有代码逐个处理externalIP的过程中，加入添加额外iptables规则的代码
  - 每个Service虽然可能有多个externalIPs，但额外的改动只针对每个Service处理一次
  - 对于每个endpoint添加externalIP的SNAT处理


测试
====

README 中提到 ”build and run from source, see [CONTRIBUTING.adoc]” ，而在 CONTRIBUITING 中则说明了如何编译，即通过命令 *make clean build* 。编译后openshift的可执行文件位置大概为 _output/local/bin/linux/amd64/openshift 。

对于测试，并不需要去替换环境中已有的openshift可执行文件，在通过命令 *systemctl stop origin-node* 后，通过命令来尝试启动服务，如 ./_output/local/bin/linux/amd64/openshift start node --config=/etc/origin/node/node-config.yaml 。


测试结果
--------

在配置了cluser-cidr的基础上，可以观察到新增的iptables规则。

cluster-cidr的配置例如::

    proxyArguments:
      cluster-cidr:
        - 10.128.0.0/18
