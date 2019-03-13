*************************
Allocating Node Resources
*************************

https://docs.okd.io/3.9/admin_guide/allocating_node_resources.html

https://docs.okd.io/3.9/admin_guide/out_of_resource_handling.html

https://docs.okd.io/3.9/admin_guide/overcommit.html

https://docs.okd.io/3.9/admin_guide/limits.html

Configuring Nodes for Allocated Resources
=========================================

在/etc/origin/node/node-config.yaml可以配置保留资源，e.g. ::

    kubeletArguments:
      kube-reserved:
        - "cpu=200m,memory=512Mi"
      system-reserved:
        - "cpu=200m,memory=512Mi"

节点能提供的分配的资源满足以下公式::

    [Allocatable] = [Node Capacity] - [kube-reserved] - [system-reserved] - [Hard-Eviction-Thresholds]

Hard-Eviction-Thresholds 在后面将被介绍。

Handling Out of Resource Errors
===============================

If swap memory is enabled for a node, that node cannot detect that it is under MemoryPressure. **To take advantage of memory based evictions, operators must disable swap.**

Configuring Eviction Policies
-----------------------------

When detecting disk pressure, the node supports the nodefs and imagefs file system partitions.

The nodefs, or rootfs, is the file system that the node uses for local disk volumes, daemon logs, emptyDir, and so on (for example, the file system that provides /). The rootfs contains openshift.local.volumes, by default /var/lib/origin/openshift.local.volumes.

The imagefs is the file system that the container runtime uses for storing images and individual container-writable layers. Eviction thresholds are at 85% full for imagefs.

有两种类型的驱逐策略，针对三种资源探测可以配置，e.g.:

  - 硬驱逐::

      kubeletArguments:
        eviction-hard:
        - memory.available<500Mi
        - nodefs.available<500Mi
        - nodefs.inodesFree<100Mi
        - imagefs.available<100Mi
        - imagefs.inodesFree<100Mi

  - 软驱逐::

      kubeletArguments:
        eviction-soft:
        - memory.available<500Mi
        - nodefs.available<500Mi
        - nodefs.inodesFree<100Mi
        - imagefs.available<100Mi
        - imagefs.inodesFree<100Mi
        eviction-soft-grace-period:
        - memory.available=1m30s
        - nodefs.available=1m30s
        - nodefs.inodesFree=1m30s
        - imagefs.available=1m30s
        - imagefs.inodesFree=1m30s

像memory.available，nodefs.inodesFree这些属于detect signals。百分比值会根据系统的总资源值进行计算。硬驱逐会在资源到达阈值后立即进行驱逐，而软驱逐会有一个grace period，之后才开始驱逐Pod。软硬驱逐可以同时使用， **We recommended setting the soft eviction threshold lower than the hard eviction threshold,** ，但时间可以自行设置。此外， **The system reservation should also cover the soft eviction threshold.** ，即system-reserved的实际值 = 预想值 + 软驱逐阈值。举个例子::

    capacity = 100
    kube-reversed + system-reversed = 5
    hard-eviction = 5
    soft-eviction < 10

    # case #1: system-reversed不包含soft eviction
    allocatable = capacity - kube-reserved - system-reversed - hard-eviction = 90
    all-pod-requests + kube-reversed - system-reserved <= 90
    all-pod-requests = 90 - 5 = 85 < allocatable

    # case #2: system-reversed包含soft eviction
    allocatable = 80
    all-pod-requests + kube-reversed - system-reserved <= 90
    all-pod-requests = 90 - 5 = 85 > allocatable

OKD以10s为周期监控nodefs和imagefs，如果使用"dedicated file system"，节点可能无法监控。(什么是"dedicated file system")。此外，节点以 node-status-update-frequency 指定的值(默认10s)为周期向Master报告自己的状态(应该会包含conditions)，以10s为周期评估和监控驱逐阈值。可见修改报告周期的意义不大。

对于软驱逐，在与资源相关的grace period超时前，节点不会通过驱逐Pod来回收对应的资源，因此如果缺少对应的资源驱逐等待周期配置，节点将启动失败。管理员可以设置eviction-max-pod-grace-period来定义一个用于驱逐Pod时用于终止Pod的等待时间，节点会对比eviction-max-pod-grace-period与pod.Spec.TerminationGracePeriodSeconds中的较小值来当做终止Pod的等待周期。如果没有设置eviction-max-pod-grace-period，则节点会立即kill Pod。

对于软驱逐，eviction-soft定义了阈值，eviction-soft-grace-period定义了驱逐Pod前的grace period（即等待周期），而eviction-max-pod-grace-period定义了开始驱逐Pod时用于终止Pod的等待周期。

Controlling Node Condition Oscillation
--------------------------------------

在软驱逐场景中，节点的资源压力评估可能会出现振荡。可以通过设置::

    kubeletArguments:
      eviction-pressure-transition-period="5m"

来控制节点退出资源压力状态前的等待时间。如果在等待期间，资源没有再次超过阈值，则退出压力状态。

Reclaiming Node-level Resources
-------------------------------

如果在eviction-pressure-transition-period后，仍处于压力状态，那么节点就会开始回收资源，并且在资源驱逐指标降下来之前，是不会接受调度的。如果是nodefs文件系统到达了驱逐阈值，那么节点会释放dead pods/containers，并且对于没有Imagefs的场景，节点还会清理unused images；对于有imagefs的场景，unused images只会在Imagefs到达驱逐阈值后才会被清理。

Understanding Pod Eviction
--------------------------

如果在软驱逐等待时间超时后，仍处于压力状态，那么节点会开始驱逐Pod，直到对应的资源降到驱逐阈值以下。

对于节点上运行的Pod，节点会以QoS和requests对资源的需求量作为对Pod排序的主次依据。QoS的优先级按照Guaranteed > Burstable > BestEffort的排序，最优先驱逐BE的。对于同一QoS优先级，节点优先驱逐消费磁盘资源最多的Pod，例如磁盘压力场景。

如果节点在回收资源前，发生了OOM事件，则会先调用OOM Killer来处理。OOM会kill oom_score分数高的Pod，简单来时即按照QoS的优先级来kill。而Burstable的Pod，会优先删除memory requests多的。

Understanding the Pod Scheduler and OOR Conditions
--------------------------------------------------

在调度Pod时，调度器会检查node的conditions，如果发现有MemoryPressure，则调度器不会调度BestEffort的Pod到节点上；而如果发现有DiskPressure，则调度器不会把任何的Pod调度到节点上。

DaemonSets and Out of Resource Handling
---------------------------------------

In general, DaemonSets should not create BestEffort pods to avoid being identified as a candidate pod for eviction. Instead DaemonSets should ideally launch Guaranteed pods.

Overcommitting
==============

Requests and Limits
-------------------

容器在缺省requests时，如果定义了limits, limits将会称为requests的默认值。

Limit的强制性是与资源类型相关的。如果容器没有设置requests和limits，那么就会被调度到一个没有资源保证的节点上，将被分配到最低等的QoS，但仍然可以尝试尽量多的获取资源。

Compute Resources
-----------------

**If multiple containers are attempting to use excess CPU, CPU time is distributed based on the amount of CPU requested by each container.** For example, if one container requested 500m of CPU time and another container requested 250m of CPU time, then any extra CPU time available on the node is distributed among the containers in a 2:1 ratio.

CPU requests are enforced using the CFS shares support in the Linux kernel. By default, CPU limits are enforced using the CFS quota support in the Linux kernel over a 100ms measuring interval.

如果一个容器使用了比requests要少的内存，那么只有当系统任务或守护进程需要比设定的保留资源多的资源时，这样的容器会被kill掉。任何时候容器会因为OOM(limit)，而被Kill。

Quality of Service Classes
--------------------------

For each compute resource, a container is divided into one of three QoS classes with decreasing order of priority:

   ============= ============ =============
     Priority     Class Name   Description
   ============= ============ =============
    1 (highest)   Guaranteed   0 < requests and requests == limits
    2             Burstable    0 < requests and requests < limits
    3 (lowest)    BestEffort   requests is null and limist is null
   ============= ============ =============

node会kill容器，当:

  - 容器超过了limits指定的内存；
  - 或者系统处于低内存场景，则node会按照优先级由低到高逐级的kill容器。

同一个容器的CPU和memory可以有不同的QoS。

Configuring Masters for Overcommitment
--------------------------------------

管理可以通过配置来override 容器的requests和limits的比例，以达到控制节点上容器密度的目的。并且可以与项目的LimitRange关联发挥作用，毕竟如下面的配置，只定义了比例，而没有给出默认、最大、最小的CPU和memory值::

    admissionConfig:
      pluginConfig:
        ClusterResourceOverride:
          configuration:
            apiVersion: v1
            kind: ClusterResourceOverrideConfig
            memoryRequestToLimitPercent: 25
            cpuRequestToLimitPercent: 25
            limitCPUToMemoryPercent: 200

\*RequestToLimitPercent的值为1~100，limitCPUToMemoryPercent的值为正数。

因为是override requests到limits的百分比，所以容器需要定义limits。为此，可以创建LimitRange来保证项目有默认的limits。

需要注意的是，即使是在override后，容器的limits和requests也要满足LimitRange定义的范围。例如LR定义了最小的CPU为1，一个容器定义了limit为1，而override后requests为0.2，小于最小值1,这将导致容器被禁止调度。

当然可以为一个项目添加annotation来disable override::

    quota.openshift.io/cluster-resource-override-enabled: "false"

Configuring Nodes for Overcommitment
------------------------------------

可以在节点的node-config.yaml中配置experimental-qos-reserved来保证Guaranteed所requested的memory不会被低QoS的Pod所侵占，e.g.::

    kubeletArguments:
      experimental-qos-reserved:
      - 'memory=50%'

百分比表示受保护不会被侵占的比例，从0%~100%。但什么是"memory requested by a higher QoS class."？

Setting Limit Ranges
====================

同一个项目内，所有资源的创建和requests修改都会和LimitRange进行评估，如果资源超出了，那么就相关修改都会被拒绝。如果资源没有设置limits或者requests，而LimitRange有相应的默认值，则会使用默认值。

容器的LimitRange可以定义的值:

  - min: Min <= container.resources.requests <= container.resources.limits
  - max: container.resources.limits <= Max
  - maxLimitRequestRatio: MaxLimitRequestRatio <= container.resources.limits/container.resources.requests (MaxLimitRequestRatio 似乎叫 MaxRequestLimitRatio 更好理解一些)
  - default: default container.resources.limit
  - defaultRequest: default container.resources.requests

Pod，类似容器，但没有两个default。

关于image, istag, pv的这就不说明了。
