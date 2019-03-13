***************
从netns访问容器
***************

From https://stackoverflow.com/questions/31265993/docker-networking-namespace-not-visible-in-ip-netns-list

两个方法: 

  - 通过软链接创建一个netns（因为容器的netns通过命令 *ip netns* 是看不到的）::

        pid=$(docker inspect -f '{{.State.Pid}}' ${container_id})
        mkdir -p /var/run/netns/
        ln -sfT /proc/$pid/ns/net /var/run/netns/$container_id

  - 或者通过命令 *nsenter* ::

        docker inspect --format '{{.State.Pid}}' <container_name_or_Id>
        nsenter -t <contanier_pid> -n <command>

亲测有效。

然而实际中的使用场景有哪些，姑且得先打个问号。
