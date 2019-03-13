**************
Some clippings
**************

What Are Containers?
====================

https://docs.okd.io/3.9/security/index.html

Containers package an application and all its dependencies into a single image that can be promoted from development, to test, to production, without change.

Containers provide consistency across environments and multiple deployment targets: physical servers, virtual machines (VMs), and private or public cloud.

Some of the benefits of using containers include:

    ===========================================================    =====================================================
    INFRASTRUCTURE                                                 APPLICATIONS
    ===========================================================    =====================================================
    Sandboxed application processes on a shared Linux OS kernel    Package my application and all of its dependencies
    Simpler, lighter, and denser than virtual machines             Deploy to any environment in seconds and enable CI/CD
    Portable across different environments                         Easily access and share containerized components
    ===========================================================    =====================================================

Why Use the PROXY Protocol?
===========================

https://docs.okd.io/3.9/install_config/router/proxy_protocol.html

However, if the connection is encrypted, intermediaries cannot modify the "Forwarded" header. In this case, the HTTP header will not accurately communicate the original source address when the request is forwarded.

To solve this problem, some load balancers encapsulate HTTP requests using the PROXY protocol as an alternative to simply forwarding HTTP. Encapsulation enables the load balancer to add information to the request without modifying the forwarded request itself. In particular, this means that the load balancer can communicate the source address even when forwarding an encrypted connection.

The HAProxy router can be configured to accept the PROXY protocol and decapsulate the HTTP request. Because the router terminates encryption for edge and re-encrypt routes, the router can then update the "Forwarded" HTTP header (and related HTTP headers) in the request, appending any source address that is communicated using the PROXY protocol.

The PROXY protocol and HTTP are incompatible and cannot be mixed. If you use a load balancer in front of the router, both must use either the PROXY protocol or HTTP. Configuring one to use one protocol and the other to use the other protocol will cause routing to fail.

