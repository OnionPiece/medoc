**********************
用iptables模拟网络丢包
**********************

其实应该是用tc netem来模拟的，但是考虑需要对特定的协议，特定IP，特定的端口等来进行模拟，tc的命令会显得比较复杂。

关于tc netem 可以参考:

  - man tc-netem
  - https://serverfault.com/questions/389290/using-tc-to-delay-packets-to-only-a-single-ip-address?utm_medium=organic&utm_source=google_rich_qa&utm_campaign=google_rich_qa
  - https://gist.github.com/digilist/d4b8ecd92b9af7aa0492
  - man tc-u32

假设我们要模拟的环境是在一台远程服务器上，测试的过程中，需要保证SSH顺畅，而需要被模拟的抖动丢包包括ICMP协议和TCP协议。则我们可以通过下面的iptables添加规则来模拟::

    -A INPUT 1 -p icmp -m statistic --mode nth --every 10 --packet 0 -j DROP
    -A INPUT 2 -p tcp -m tcp --dport 22 -j ACCEPT
    -A INPUT 3 -p tcp -m statistic --mode random --probability 0.1 -j DROP

中间那条放行SSH的规则没什么说的，而对于模拟丢包的两条规则，需要说明的是:

  - 它们都是基于统计的丢包，-m statistic
  - 不过第一条是严格的按照每n个包，去丢第i（0<= i <= n-1) 个包的模式去drop，例如每10个包一组，丢第0个包
  - 而第三条是按照概率统计的随机丢包，100个包，可能丢11个，或者9个包
