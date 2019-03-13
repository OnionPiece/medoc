*********************
Admission Controllers
*********************

https://docs.okd.io/3.9/architecture/additional_concepts/admission_controllers.html

Overview
========

admissionConfig.pluginConfig in /etc/origin/master/master-config.yaml.

Admission control plug-ins intercept requests to the master API prior to persistence of a resource, but after the request is authenticated and authorized.

Each admission control plug-in is run in sequence before a request is accepted into the cluster. If any plug-in in the sequence rejects the request, the entire request is rejected immediately, and an error is returned to the end-user.

Admission control plug-ins may modify the incoming object in some cases to apply system configured defaults. In addition, admission control plug-ins may modify related resources as part of request processing to do things such as incrementing quota usage.

录入控制器，在数据正式“落盘”前，对数据拦截并处理，例如修改数据本身或者其他管理数据，如资源用量计数+1。在控制链中的各个插件会逐个对请求进行处理，如果一个插件拒绝了请求，那么请求将被立即被控制器拒绝并返回。

Customizable Admission Plug-ins
===============================

以下是管理员可以配置的一些插件。

Limiting Number of Self-Provisioned Projects Per User
-----------------------------------------------------

https://docs.okd.io/3.9/admin_guide/managing_projects.html#limit-projects-per-user

能控制满足不同selector的用户能够创建多少个projects。 admissionConfig.pluginConfig.ProjectRequestLimit in /etc/origin/master/master-config.yaml.

其他在 https://docs.okd.io/3.9/admin_guide/managing_projects.html 中的内容包括:

Self-provisioning Projects
``````````````````````````

即对于用户可以自行创建项目的管理，可以配置一个template（projectConfig.projectRequestTemplate）来用于用户创建项目时填写Name，Admin User等信息，也可以在取消用户自行创建项目的权利后通过配置projectConfig.projectRequestMessage 来告诉用户一些反馈信息（比如联系管理员去创建）。

Using Node Selectors
````````````````````

管理员可以配置projectConfig.defaultNodeSelector 来为集群中的所有项目提供默认的nodeSelector；同样地，对于某个项目，管理员也可以以添加annotations（"openshift.io/node-selector"）的方式来向项目添加默认的nodeSelector。例如先设置cluster-wide的nodeSelector来匹配一组通用服务器，在对特殊项目配置project-wide的nodeSelector来访问更多的服务器，而不仅限于通用服务器。cluster-wide的目标是all projects。

用户在自己创建Pod是仍然可以配置nodeSelector，如果与project-wide或者cluster-wide的nodeSelector不存在key冲突的情况，则所有的select条件都会被使用到，即选择出的node满足所有的条件；而冲突时，pod将无法被调度。

Configuring Global Build Defaults and Overrides
-----------------------------------------------

https://docs.okd.io/3.9/install_config/build_defaults_overrides.html

bc.spec.nodeSelector，与BuildDefaults和BuildOverride，与projectConfig.defaultNodeSelector的工作逻辑:

  - 优先级 bc.spec.nodeSelector > project default selector > BuildDefault > defaultNodeSelector;
  - BuildOverride将会以AND的逻辑，和其他的selector一起进行组织。

BuildDefault中可以设置git代理，imageLabels，annotations，nodeSelector，resources。

BuildOverride可以设置forePull，imageLabels，annotations，nodeSelector, tolerations(for taint)。

Controlling Pod Placement
-------------------------

https://docs.okd.io/3.9/admin_guide/scheduling/pod_placement.html

Constraining Pod Placement Using Node Name 没有看懂怎么搞的，以及要限制什么。

Constraining Pod Placement Using a Node Selector。Refer https://github.com/openshift/origin/blob/master/pkg/scheduler/admission/apis/podnodeconstraints/v1/swagger_doc.go , PodNodeConstraintsConfig is the configuration for the pod node name and node selector constraint plug-in. For accounts, serviceaccounts and groups which lack the "pods/binding" permission, Loading this plugin will prevent setting NodeName on pod specs and will prevent setting NodeSelectors whose labels appear in the blacklist field "NodeSelectorLabelBlacklist". NodeSelectorLabelBlacklist specifies a list of labels which cannot be set by entities without the "pods/binding" permission.

Control Pod Placement to Projects。管理员可以在PodNodeSelector.configuration.podNodeSelectorPluginConfig下为namespace创建labels的白名单，之后在创建namespace时，需要通过添加annotations scheduler.alpha.kubernetes.io/node-selector来指定namespace将使用哪些白名单中提供的labels。在项目内使用nodeSelector时，Pod.spec的nodeSelector将与白名单的nodeSelector merge，merge的结果将作为最终用于调度的nodeSelector，merge将以Pod.spec中的为主。

三种nodeSelector的组合举例
==========================

不包括与build相关的部分。

假设，我们有:

  - 两个region；
  - 每个region各有开发，测试，生产三组服务器；
  - 每组服务器又各分为高配和普配两种；

那么管理员可以通过:

  - 配置PodNodeConstraints.configuration.nodeSelectorLabelBlacklist来罗列所有细节，进行黑名单保护，保留region等需要暴露出来的labels；
  - 设置annotaions scheduler.alpha.kubernetes.io/node-selector来控制用于开发、测试、生产的项目的pod只能调度到对应的服务器组；
  - 配置projectConfig.defaultNodeSelector 来将普通用户的pod调度到普配服务器上，而将配置了annotations openshift.io/node-selector的用户的pod调度到高配服务器上。
