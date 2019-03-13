*******************
Advanced Scheduling
*******************

https://docs.okd.io/3.9/admin_guide/scheduling/scheduler-advanced.html

Pod亲和与反亲和，是一个Pod针对一组Pod。Node亲和与反亲和，是一个Pod针对一组节点。Node selectors 虽然也用到了node labels，但是没有required和prefered rules。污点与容忍，节点和Pod利用彼此的labels来协商Pod能否调度到node上。

https://docs.okd.io/3.9/admin_guide/scheduling/pod_affinity.html

Required rules，指定的规则必须满足，才能将Pod部署到node上。Preferred rules，尽量尝试，但不保证满足。如果两类规则同时配置了，则需要先满足required rule，在满足prefered rule，满足后节点才能被考虑调度。

亲和与反亲和，只影响调度，所以在调度完成后，Pod在node上运行起来，对于node label的修改不会影响Pod。

代码片段，以下四个代码片段展示了在DC中配置亲和、反亲和策略，使得同一组Pod调度到同一个或不同的node上:

  - Pod affinity in DC::

      # preferred
      spec:
        template:
          metadata:
            labels:
              eggs: together
          spec:
            affinity:
              podAffinity:
                preferredDuringSchedulingIgnoredDuringExecution:
                - podAffinityTerm:
                    labelSelector:
                      matchExpressions:
                      - key: eggs
                        operator: In
                        values:
                        - together
                    topologyKey: kubernetes.io/hostname
                  weight: 100

      # required
      spec:
        template:
          metadata:
            labels:
              eggs: together
          spec:
            affinity:
              podAffinity:
                requiredDuringSchedulingIgnoredDuringExecution:
                - labelSelector:
                    matchExpressions:
                    - key: eggs
                      operator: In
                      values:
                      - together
                  topologyKey: kubernetes.io/hostname

  - Pod anti-affinity in DC::

      # prefered
      spec:
        template:
          metadata:
            labels:
              eggs: together
          spec:
            affinity:
              podAntiAffinity:
                preferredDuringSchedulingIgnoredDuringExecution:
                - weight: 100
                  podAffinityTerm:
                    labelSelector:
                      matchExpressions:
                      - key: eggs
                        operator: In
                        values:
                        - together
                    topologyKey: kubernetes.io/hostname

      # required
      spec:
        template:
          metadata:
            labels:
              eggs: together
          spec:
            affinity:
              podAntiAffinity:
                requiredDuringSchedulingIgnoredDuringExecution:
                - labelSelector:
                    matchExpressions:
                    - key: eggs
                      operator: In
                      values:
                      - together
                  topologyKey: kubernetes.io/hostname

其中:

  - topologyKey: 亲和与反亲和所选择的节点所应该有的label，通过label的value来判断节点是否是同一个或者同一组，例如kubernetes.io/hostname，或者region。因此这可以间接用来定义亲和与反亲和的节点粒度。例如对于反亲和，有服务器隔离，机柜隔离，机房隔离等。当然如果不存在具有所指定label的节点，Pod是无法被调度的；
  - labelSelector: empty则匹配所有，null则无匹配；
  - operator 一种有四种，即In, NotIn, Exists and DoesNotExist；
  - **matchExpressions 如果有多个，则它们是和的关系；**
  - weight, 1~100，权重累加最高的即最合适的。

此外:

  - 与matchExpressions对应的还有由key-value组成的matchLabels，内容表达上，一个match label相当于一个operator是In的match expression；
  - podAffinityTerm下还有一个参数namespace，用来指明podAffinityTerm.labelSelector将作用的namespace，empty or null则代表当前namespace。

https://docs.okd.io/3.9/admin_guide/scheduling/node_affinity.html

一些概念同Pod affinity，没有node anti affinity。

不同处在于:

  - **nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution 的多个 nodeSelectorTerms 彼此是或的关系；**
  - operator 多了Gt和Lt。

如果同时使用了node affinity和node selector，则需要同时满足，节点才能成为候选节点。

https://docs.okd.io/3.9/admin_guide/scheduling/node_selector.html

Add nodeSelectorLabelBlacklist to the admissionConfig section with the labels that are assigned to the node hosts you want to deny pod placement.

(refer https://github.com/openshift/origin/blob/master/pkg/scheduler/admission/apis/podnodeconstraints/v1/swagger_doc.go)

PodNodeConstraintsConfig is the configuration for the pod node name and node selector constraint plug-in. For accounts, serviceaccounts and groups which lack the "pods/binding" permission, Loading this plugin will prevent setting NodeName on pod specs and will prevent setting NodeSelectors whose labels appear in the blacklist field "NodeSelectorLabelBlacklist".
NodeSelectorLabelBlacklist specifies a list of labels which cannot be set by entities without the "pods/binding" permission.

https://docs.okd.io/3.9/admin_guide/scheduling/taints_tolerations.html

对于有污点(taints)的节点，Pod需要有容忍力(toleration)，才能部署到节点上，或者继续在节点上运行。

toleration(dc.spec.template.spec.tolerations, pod.spec.tolerations)有四要素，即key，value，effect，operator。其中:

  - effort 有NoSchedule(无法调度),PreferNoSchedule(尽量不调度),NoExecute(无法执行，当然也无法调度)；
  - operator 有Equal和Exists。

语义上类似，Pod能(有)否(没有)容忍(toleration)，具有key=value的、effect是EFFECT的污点，或者具有某个key的、effect是EFFECT的污点，就意味着它能否在这样的节点上调度和运行。

当有多个taints与tolerations时，需要综合考虑各个effects。无法满足所有的effects将无法被调度，但是已经运行了，则可能无需满足*Schedule effects。

针对NoExecute污点，Pod可以定义tolerations是可以指定参数tolerationSeconds，来表示容忍时间:

  - 0，<0，则立即被驱逐；
  - >0，则在时间到了后被驱逐；
  - 不设置，则永不被驱逐。

此外，如果Pod mismatch NoExecute污点，但是Pod定义了tolerationSeconds，则Pod将在时间到了后被驱逐。

在master-config.yaml中，可以在admissionConfig下添加DefaultTolerationSeconds来为没有设置tolerations的Pod提供默认值，默认的tolerations将容忍 node.alpha.kubernetes.io/not-ready:NoExecute and node.alpha.kubernetes.io/unreachable:NoExecute taints for five minutes.

（实际测试中，参考 https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/ ，设置为 node.kubernetes.io/unreachable，node.kubernetes.io/not-ready）

与之对应的，master-config.yaml可以进行配置，将节点的not ready和unreachable变为两种自动的污点。

测试了开启配置后，将origin-node.service停止的情况，相应节点上的Pod在5min被迁移。值得开启。

DaemonSet Pod是默认容忍unreachable和not-ready这两种NoExecute污点的，避免DS Pod被驱逐。
