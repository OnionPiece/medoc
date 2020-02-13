********************
Ubuntu上创建Swap分区
********************

无论是我自己的老本，还是VPS，内存都比较不够。

1. swapoff -a 先停掉现有的swap，如果有的话但仍然不够用的话。

2. dd if=/dev/zero of=/swapfile bs=1M count=1024 酌情创建swapfile，vps创建了1G的，本上创建了16G的用来多跑虚机。

3. mkswap /swapfile

4. 修改/etc/fstab，加入/swapfile，使得重启后能挂载起来:

::
	/swapfile none swap sw 0 0

5. swapon /swapfile

6. 设置swap使用策略，修改/proc/sys/vm/swappiness，当空闲物理内存少于指定百分比时使用swap

::
	echo 20 >/proc/sys/vm/swappiness
