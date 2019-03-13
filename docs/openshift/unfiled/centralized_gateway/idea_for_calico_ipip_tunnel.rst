***********************************
Calico ipip tunnel 下实现CGW的idea
***********************************

基本思路和在使用openshift-ovs-multitenant插件下的情况类似，即将Pod的egress流量通过隧道转发到当前的CGW 主节点，然后在通过iptables做SNAT，最后转发出去。Ingress的情况简单，略过不提。

https://github.com/lizk1989/netns-topo/tree/master/iptunnel 提供了一个简单的测试，以展示在使用ipip tunnel的情况下，如何通过配置路由策略来实现转发。
