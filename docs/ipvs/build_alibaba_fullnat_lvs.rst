*************************
Build Alibaba fullnat lvs
*************************

Prepare for rpmbuild
====================

Ref: https://wiki.centos.org/HowTos/I_need_the_Kernel_Source.

1. mkdir -p /root/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
2. echo "%_topdir /root/rpmbuild" > ~/.rpmmacros
3. yum install gcc perl-ExtUtils-Embed.x86_64 xmlto asciidoc elfutils-libelf-devel binutils-devel newt-devel python-devel hmaccalc patchutils rpm-build rng-tools


Get kernel.spec
===============

Ref: http://kb.linuxvirtualserver.org/wiki/IPVS_FULLNAT_and_SYNPROXY.

4. wget ftp://ftp.redhat.com/pub/redhat/linux/enterprise/6Server/en/os/SRPMS/kernel-2.6.32-220.23.1.el6.src.rpm
5. rpm -ivh /root/kernel-2.6.32-220.23.1.el6.src.rpm


Get patched kernel archive file
===============================

Ref: https://ieevee.com/tech/2015/12/09/fullnat-2.html

6. wget http://kb.linuxvirtualserver.org/images/b/b7/Linux-2.6.32-220.23.1.el6.x86_64.lvs.src.tar.gz
7. tar xvf /root/Linux-2.6.32-220.23.1.el6.x86_64.lvs.src.tar.gz  // => /root/linux-2.6.32-220.23.1.el6.x86_64.lvs
8. mv /root/linux-2.6.32-220.23.1.el6.x86_64.lvs/ /root/linux-2.6.32-220.23.1.el6
9. rm -rf /root/linux-2.6.32-220.23.1.el6/configs
10. tar -cvjSf linux-2.6.32-220.23.1.el6.tar.bz2 /root/linux-2.6.32-220.23.1.el6
11. mv /root/linux-2.6.32-220.23.1.el6.tar.bz2 /root/rpmbuild/SOURCES/linux-2.6.32-220.23.1.el6.tar.bz2


Build kernel
============

Ref: https://wiki.centos.org/HowTos/Custom_Kernel

12-a. rpmbuild -bb --target=`uname -m` /root/rpmbuild/SPECS/kernel.spec --without debug --without debuginfo --with firmware --without kabichk
12-b. rngd -r /dev/urandom
(In a VM with 2 cores, 4G mems, rpmbuild will take more than 40 mins to build.)


Build lvs-tools
===============

Ref: http://kb.linuxvirtualserver.org/wiki/IPVS_FULLNAT_and_SYNPROXY

13. yum install openssl-devel popt-devel libnl-devel
14. rpm -i /root/rpmbuild/RPMS/x86_64/kernel-devel-2.6.32-220.23.1.el6.x86_64.rpm
15. wget http://kb.linuxvirtualserver.org/images/a/a5/Lvs-fullnat-synproxy.tar.gz
16. tar zxf /root/Lvs-fullnat-synproxy.tar.gz  // => /root/lvs-fullnat-synproxy
17. tar zxf /root/lvs-fullnat-synproxy/lvs-tools.tar.gz  // => /root/lvs-fullnat-synproxy/tools
18. cd /root/lvs-fullnat-synproxy/tools/
19. Edit ipvsadm/Makefile, append "-lnl" to LIBS like::

      LIBS		= $(POPT_LIB) -lnl

20. cd rpm  // the lvs-tools.spec file uses relative path to enter keepalived and ipvsadm directory
21. Edit lvs-tools.spec with:

  1. adding "%define _unpackaged_files_terminate_build 0"
  2. replace::

      ./configure --with-kernel-dir="/lib/modules/`uname -r`/build"

    with::

      ./configure --with-kernel-dir=/root/linux-2.6.32-220.23.1.el6/

    if linux-2.6.32-220.23.1.el6 is under /root/.

22. rpmbuild -ba lvs-tools.spec
