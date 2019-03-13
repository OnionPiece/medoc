****************
Tcpdump 抓包基础
****************

我们所处的以linux服务器（以下称为节点）为主的网络环境中，对于大部分的网络问题，用tcpdump抓包都可以做到快速定位问题，或者缩小问题范围。

抓包，需要有基础的网络概念，如二层的MAC和ARP，三层的IP，四层的Port等。对于更复杂的一些情况，可能需要借助查看相关数据包的包头格式，例如tcp packet header format，以及相关协议来“锁定”想要抓取的包。

需要明确的是tcpdump抓到的包是从二层，即数据链路层开始的。你可以在节点上，或虚机，容器，netns里使用tcpdump来“实时地”，从网口上抓包。

tcpdump命令主要由两部分组成，options和expression。但并没有特定的格式，例如以下命令都是可以的::

    # 没有o，没有e
    tcpdump

    # 有o，没有e
    tcpdump -i eth0

    # 没有o，有e
    tcpdump tcp

    # 有o 有e
    tcpdump -i eth0 tcp


options
-------

options只负责在哪（网口），怎么抓（出栈/入栈），以及怎么打印。而expression则相当与filters，例如只抓tcp的包，还是只抓udp的包。

我常用的参数有:

  - -t: 不打印时间戳
  - -n: 一个n代表不做地址转换，即打印IP地址，而不是对应的Hostname；两个n代表不做端口转换，例如打印80，而不是http。
  - -e: 打印MAC地址
  - -i: 指定监听/抓包的网口
  - -x: 以十六进制打印包的内容
  - -A: 以Ascii码打印包的内容，多用于Http, MQ的明文数据包
  - -P: 指定监听/抓包的方向，in代表从网口进来，out代表从网口出去

补充说明:

  - 可以将Options拼接在一起，但带参数的option只能放在拼接的最后一未，例如 -tnnei eth0
  - -P是redhat/cenos的option，而在ubuntu上则是-Q
  - 当不确定要从哪个网卡抓取，则可以指定any，来获取节点上的所有网口的数据包


expression
----------

expression有自己的简单的语法，以及关键字。其中一些与某些编程语言中的行为逻辑一样:

  - and, or, not: 逻辑的与或非
  - &: 位与
  - <<, >>: 位移
  - ==: 相等
  - []: 使用索引（从0开始）来读取数据包中的值，例如ether[0], ip[1:2], tcp[4:3]，分别代表了从读取以太网包，IP包，TCP包的第0, 1-2, 4-6个字节

另外一些则是tcpdump自己的语法糖，如:

  - ether, icmp, arp, ip, tcp, udp: 指定特定协议
  - src, dst: 指定源或目的
  - host，net: 指定IP为单个主机IP

其他一些可以通过man tcpdump来查看，如搜索tcpflags, icmptypes等。


examples
--------

几乎是万金油的用法，可以酌情加入e和n。什么包都抓，无论是做了什么封装，用grep都可以跳过包头的各种细节，直接检查是否有想要的包::

    tcpdump -i any | grep XXX

在eth0上抓取arp或icmp的包，不打印时间戳，打印MAC，不做hostname转化::

    tcpdump -tnei eth0 arp or icmp

在eth0上抓取目标地址是192.168.0.10的包（源IP地址是192.168.0.10的则不会被抓取）::

    tcpdump -tnei eth0 dst host 192.168.0.10

抓取从eth0上发出去的tcp的包::

    tcpdump -i eth0 -P out tcp

在eth0上抓取来自192.168.0.192/26网段，访问3306端口的包::

    tcpdump -tnei eth0 src net 192.168.0.192/26 and dst port 3306

抓取并打印本地所有收到的HTTP的明文数据::

    tcpdump -i any src port 80 -A -P in

在eth0上抓取HTTP的GET包::

    tcpdump -tni eth0 'tcp[((tcp[12:1] & 0xf0) >> 2):4] == 0x47455420'

注:

  - tcp报文中，data offset字段在第13个字节中的，高4位。
  - HTTP的method在整个HTTP包的前四个字节。
  - 'G', 'E', 'T', ' '所对应的ascii码是0x47,0x45,0x54,0x20。
