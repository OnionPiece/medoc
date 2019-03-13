*****************************
Integrating External Services
*****************************

From https://docs.openshift.com/container-platform/3.9/dev_guide/integrating_external_services.html

相关的操作很简单，但是具体为什么要这样的做，就是个问题了。因为看起来，多一个Service的过度，似乎只是为了让容器平台内的服务和外部服务进一步解耦，和egress流量的访问控制也没太大关系。

Defining a Service for an External Database
===========================================

You can define a service either by providing an IP address and endpoints, or by providing a Fully qualified domain name (FQDN).

Using an IP address
```````````````````

This is similar to creating an internal service; the difference is in the service’s Selector field. Internal OpenShift Container Platform services use the Selector field to associate pods with services using labels. The EndpointsController system component synchronizes the endpoints for services that specify selectors with the pods that match the selector. The service proxy and OpenShift Container Platform router load-balance requests to the service amongst the service’s endpoints. Services that represent an external resource do not require associated pods. Instead, leave the Selector field unset. This represents the external service, making the EndpointsController ignore the service and allows you to specify endpoints manually.

Service通过selector field来将能匹配到label的pod作为endpoints。而用于表征external service时，selector必须为空，即: selector: {}。

Create the required endpoints for the service. This gives the service proxy and router the location to send traffic directed to the service.

有svc同名的ep，ep.subsets.addresses.ip 和 ep.subsets.ports.port 分别指向外部服务的IP和端口。


Using an External Domain Name
`````````````````````````````

Using external domain names make it easier to manage an external service linkage, because you do not have to worry about the external service’s IP addresses changing. ExternalName services do not have selectors, or any defined ports or endpoints, therefore, you can use an ExternalName service to direct traffic to an external service. Using an external domain name service tells the system that the DNS name in the externalName field is the location of the resource that backs the service. When a DNS request is made against the Kubernetes DNS server, it returns the externalName in a CNAME record telling the client to look up the returned name to get the IP address.

svc.spec.type为ExternalName，svc.spec.selector为{}的服务将不会有ports或者endpoints，因此不需要关注外部服务IP的变化。而为了将访问导向外部服务，需要在svc.spec.externalName中指定外部服务的CNAME，这样在k8s的DNS会在pod请求svc的内部的域名时，返回对应的CNAME。
