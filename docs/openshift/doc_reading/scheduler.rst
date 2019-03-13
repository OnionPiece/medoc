******************
Default Scheduling
******************

From https://docs.okd.io/3.9/admin_guide/scheduling/scheduler.html

From https://github.com/openshift/origin/blob/master/vendor/k8s.io/kubernetes/pkg/scheduler/algorithm/predicates/predicates.go

From https://github.com/openshift/origin/blob/master/vendor/k8s.io/kubernetes/pkg/scheduler/algorithm/priorities/node_affinity.go

scheduler的逻辑，也就是选择node的逻辑，会:

  - 先用一组前置条件predicates来对nodes进行过滤；
  - 在用一组带权重的优先级筛选器priorities来对nodes进行打分，评判优先级；
  - 最后根据优先级选择出节点进行部署，如果最高优先级的节点有多个，就从中random出一个。

如果要对scheduler进行自定义，那么需要修改 /etc/origin/master/scheduler.json 然后重启 origin-master-api 和 origin-master-controllers。

Available Predicates
====================

一些predicates可以通过提供参数进行自定义，多个predicates可以组合起来提供额外的节点过滤。

Predicates分为:

  - 静态predicates，即不接受参数，如:

    - NoVolumeZoneConflict: 检查zone内能否满足Pod对卷的请求；
    - MatchInterPodAffinity: 亲和与反亲和性检查，判断调度能否满足pod affinity或者anti-affinity (refer InterPodAffinityMatches in predicates.go)；
    - NoDiskConflict: 检查Pod所请求的卷是否可用；
    - PodToleratesNodeTaints: 污点与容忍性检查；
    - CheckNodeMemoryPressure: 节点内存压力检查 (refer CheckNodeMemoryPressurePredicate in predicates.go)；
    - (以上这些属于默认的predicates)
    - CheckNodeDiskPressure: 检查Pod能否忍受有磁盘压力的node (refer CheckNodeDiskPressurePredicate in predicates.go);
    - CheckVolumeBinding: 检查node上的PV能否满足Pod对PVC，bound or unbound，对非亲和性的要求，该predicates需要在非default predicates中启用；
    - CheckNodeCondition: 检查Pod能否忍受具有out of disk, network unavailable, or not ready conditions的node;
    - PodToleratesNodeNoExecuteTaints: 检查Pod能否容忍NoExecute的node;
    - CheckNodeLabelPresence: 参考下面的ServiceAffinity；
    - checkServiceAffinity: 参考下面的labelsPresence；

  - 常规predicates包含两类，非挑剔的(non-critical)和必要的(essential)。非挑剔的predicates针对非挑剔的Pod，需要这类Pod通过检查，而必要的predicates需要所有的Pod都通过检查，（那什么是非挑剔的Pod？），默认的调度器包含了常规的predicates；

    - PodFitsResources，非挑剔的predicates，node申明它们所提供的资源（CPU, memory, GPU, EphemeralStorage)，然后由Pod来根据requests来遴选 (refer PodFitsResources in predicates.go)；
    - (以下几种都是essential的)
    - PodFitsHostPorts: Pod申明的hostPorts node是否能够提供；
    - HostName: Pod申明的hostName node是否能够满足；
    - MatchNodeSelector: 检查nodeSeletor是否满足；

  - 可配置的predicates:

    - ServiceAffinity: 基于Pods上运行的Service去调度，同一Service的Pods调度到同一个或者相互关联的nodes上可能带来更好的性能；

      优先按照Pods所定义的nodeSelector去调度，如果没有定义nodeSelector，则以第一个“落地”的Pod为基础，以ServiceAffinity去筛选。

      不同层次的labels可以一起发挥作用，例如利用labels去限定region，zone，rack。

      (Refer checkServiceAffinity in predicates.go)

    - labelsPresence: 根据参数presence指定的状态true of false，来检查node上的labels有或没有时，Pod能否调度到上面。参数labels指定的多个label都需要同事存在(true)或不存在(false)才能满足Pod调度。

      (Refer CheckNodeLabelPresence in predicates.go)

代码片段::

    "predicates":[
          {
             "name":"<name>",
             "argument":{
                "serviceAffinity":{
                   "labels":[
                      "<label>"
                   ]
                }
             }
          },
          {
             "name":"RackPreferred",
             "argument":{
                "labelsPresence":{
                   "labels":[
                      "rack",
                      "region"
                     ],
                   "presence": true
                }
             }
          },
       ],


Available Priorities
====================

默认的priorities，除了NodePreferAvoidPodsPriority的weight是10000外，其他的都是1:

  - NodePreferAvoidPodsPriority会忽略由controller负责，而非副本控制器负责的pod。
  - SelectorSpreadPriority 侧重于将从属于同一个Service，RC，RS，Stateful Sets的一个新的Pod调度到负载更少的“同胞”Pods的节点上去。
  - InterPodAffinityPriority 会将自己的权重加到Pod affinity的 weightedPodAffinityTerm权重之和上。
  - LeastRequestedPriority 青睐于将Pod调度到被requests的资源更少的节点。 对应的，也有MostRequestedPriority。
  - BalancedResourceAllocation 青睐的节点是CPU和memory已被请求的资源是均衡的。
  - NodeAffinityPriority 会在 preferredSchedulingTerm 的基础上再次给node打分。
  - TaintTolerationPriority 青睐拥有更少的PreferNoSchedule 污点的节点。
  - ImageLocalityPriority 青睐已经有容器所需镜像的节点。
  - ServiceSpreadingPriority 类似SelectorSpreadPriority。
