***************************
Build OVS 2.4 on CentOS 6.2
***************************

I tried to build OVS 2.5 on CentOS 6.2, but always failed to run ovs-vswitchd
with error "Generic Netlink family 'ovs_datapath' does not exist" in log.
So I turn to have a try on OVS 2.4, and it can be built and run on CentOS 6.2.

For ovs_datapath error, it may per https://patchwork.ozlabs.org/patch/590069/


Packaging OVS 2.4
=================

Per http://docs.openvswitch.org/en/latest/intro/install/rhel/

1. yum install rpm-build ...
2. mkdir -p ~/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
3. echo '%_topdir /root/rpmbuild' > ~/.rpmmacros
4. cp openvswitch-2.4.0.tar.gz ~/rpmbuild/SOURCES/
5. rpmbuild -bb --without check openvswitch-2.4.0/rhel/openvswitch.spec
6. rpmbuild -bb openvswitch-2.4.0/rhel/openvswitch-kmod-rhel6.spec
