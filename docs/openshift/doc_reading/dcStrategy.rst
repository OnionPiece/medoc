*******************
Deployment Strategy
*******************

From:
  - https://docs.openshift.com/container-platform/3.9/dev_guide/deployments/deployment_strategies.html
  - https://docs.openshift.com/container-platform/3.9/dev_guide/deployments/advanced_deployment_strategies.html

Blue-Green Deployment
=====================

Blue-green deployments involve running two versions of an application at the same time and moving traffic from the in-production version (the green version) to the newer version (the blue version). You can use a rolling strategy or switch services in a route.

绿版是当前运行的版本，蓝版是即将升级的版本，二者同时运行，升降级的方式主要是切流量(？)。用rolling strategy的话，就逐个升级了，看不到其中哪里会有测试蓝版的切入点，除非蓝版已经在其他地方测试过了。但如果是那样的话，"running two versions of an app at the same time"的意义是什么。

用路由的话，两个路由，两个入口，两个版本可以同时运行，切流量的时候只要改一下路由即可。


A/B Deployment
==============

The A/B deployment strategy lets you try a new version of the application in a limited way in the production environment. You can specify that the production version gets most of the user requests while a limited fraction of requests go to the new version. The user sets up a route with multiple services. Each service handles a version of the application. 

同样是同时运行的两个版本，但是是同一个入口，请求按概率(?)被分发到不同的服务版本。

The versions need **N-1 compatibility** to properly work together.

Each service is assigned a weight and the portion of requests to each service is the service_weight divided by the sum_of_weights. The weight for each service is distributed to the service’s endpoints so that the sum of the endpoint weights is the service weight.

通过负载均衡的权重来进行设置流量进入不同版本服务的百分比，endpoints权重之和是它们的service的权重。

**The route can have up to four services.** The weight for the service can be between 0 and 256. When the weight is 0, no new requests go to the service, however existing connections remain active. When the service weight is not 0, each endpoint has a minimum weight of 1. Because of this, a service with a lot of endpoints can end up with higher weight than desired. In this case, reduce the number of pods to get the desired load balance weight.

路由最多负载四个services。权重为0时，不再接受新的请求，但仍会处理已有链接。由于haproxy配置文件里的server对应的是Pod，因此一个service下有更多的Pod将会获得比预期多的权重。

When using alternateBackends also use the roundrobin load balancing strategy to ensure requests are distributed as expected to the services based on weight. roundrobin can be set for a route using a route annotation, or for the router in general using an environment variable.

当采用A/B发布时，负载均衡的策略最好改为roundrobin，否则会失去A/B的意义。


N-1 Compatibility
=================

Applications that have new code and old code running at the same time must be careful to ensure that data written by the new code can be read and handled (or gracefully ignored) by the old version of the code. This is sometimes called schema evolution and is a complex problem.

向前兼容？

One way to validate N-1 compatibility is to use an A/B deployment. Run the old code and new code at the same time in a controlled way in a test environment, and verify that traffic that flows to the new deployment does not cause failures in the old deployment.


Graceful Termination
====================

OpenShift Container Platform and Kubernetes give application instances time to shut down before removing them from load balancing rotations. However, applications must ensure they cleanly terminate user connections as well before they exit.

在server从haproxy的配置中摘除前，Pod里的app应确保终止了链接，自然也包含不再接受新的请求。

On shutdown, OpenShift Container Platform will send a TERM signal to the processes in the container. Application code, on receiving SIGTERM, should stop accepting new connections. This will ensure that load balancers route traffic to other active instances. The application code should then wait until all open connections are closed (or gracefully terminate individual connections at the next opportunity) before exiting.

shutdown的时候会先发送 **TERM** 信号。应用应该停止接受新的连接，这应该也包括 **用于健康检查的链接** ，之后等待已有链接结束或者gracefully teminate。

After the graceful termination period expires, a process that has not exited will be sent the KILL signal, which immediately ends the process. The terminationGracePeriodSeconds attribute of a pod or pod template controls the graceful termination period (default 30 seconds) and may be customized per application as necessary.

terminationGracePeriodSeconds（默认30s）所指定的之间超时后，将会发送KILL信号。


What Are Deployment Strategies?
===============================

The Rolling strategy is the default strategy used if no strategy is specified on a deployment configuration.

A deployment strategy uses readiness checks to determine if a new pod is ready for use. If a readiness check fails, the deployment configuration will retry to run the pod until it times out. The default timeout is 10m, a value set in TimeoutSeconds in dc.spec.strategy.*params.

再次强调了readiness check的重要性（ **就是readiness probe** ），如果新版本pod的readiness check失败了，那么dc会继续运行Pod直到dc.spec.strategy.*params指定timeout（默认10s）。（超时后认为升级失败，见于下文）


Rolling Strategy
================

A new version (the canary) is tested before all of the old instances are replaced. If the readiness check never succeeds, the canary instance is removed and the deployment configuration will be automatically rolled back.

如果readiness check无法成功（应该包括超时），那么dc将回滚。

When to Use a Rolling Deployment:

  - When you want to take no downtime during an application update.
  - When your application supports having old code and new code running at the same time.

A rolling deployment means you to have both old and new versions of your code running at the same time. This typically requires that your application handle N-1 compatibility.

因为新旧版本的Pod同时运行，即它们很可能面对同样的请求，读写同样的数据记录，因此需要具备向前兼容。

代码片段::

    strategy:
      type: Rolling
      rollingParams:
        updatePeriodSeconds: 1 
        intervalSeconds: 1 
        timeoutSeconds: 120 
        maxSurge: "20%" 
        maxUnavailable: "10%" 
        pre: {} 
        post: {}

其中:

  - updatePeriodSeconds: 升级单个Pod的间隔，默认1s
  - intervalSeconds: 开始升级后，拉取deployments状态的时间间隔，默认1s（目前不知道这个有什么用）
  - timeoutSeconds: 默认600s，开始升级后无法成功时，等待进入回滚的超时时间
  - maxSurge: 默认25%，也可以是个绝对值，如2，会基于升级前Pod的总数，按照该值的定义，scale up新版本的Pod
  - maxUnavailable: 默认25%，也可以是绝对值，会基于升级前Pod的总数，按照该值的定义，scale down新版本的Pod
  - pre and post: 见于下文中的Lifecycle Hooks

*oc explain dc.spec.strategy.rollingParams* 中有如下描述:

  - maxSurge:

    Example: when this is set to 30%, the new RC can be scaled up by 30% immediately when the rolling update starts. Once old pods have been killed, new RC can be scaled up further, ensuring that total number of pods running at any time during the update is atmost 130% of original pods.

  - maxUnavailable:

    Example: when this is set to 30%, the old RC can be scaled down by 30% immediately when the rolling update starts. Once new pods are ready, old RC can be scaled down further, followed by scaling up the new RC, ensuring that at least 70% of original number of pods are available at all times during the update.

实际测试中发现，当副本数是4时，采用默认参数的rolling会在deployments的log里有::

    Scaling up pyflask-5 from 0 to 4, scaling down pyflask-4 from 4 to 0 (keep 3 pods available, don't exceed 5 pods)
    Scaling pyflask-5 up to 1
    Scaling pyflask-4 down to 3
    ...

而如果调整了maxSurge为0,而maxUnavailable为10%时，则有::	

    Scaling up pyflask-6 from 0 to 4, scaling down pyflask-5 from 4 to 0 (keep 3 pods available, don't exceed 4 pods)
    Scaling pyflask-5 down to 3
    Scaling pyflask-6 up to 1
    ...

而如果调整了maxSurge为33%,而maxUnavailable为0时，则有::

    Scaling up pyflask-7 from 0 to 4, scaling down pyflask-6 from 4 to 0 (keep 4 pods available, don't exceed 6 pods)
    Scaling pyflask-7 up to 2
    Scaling pyflask-6 down to 2
    ...

所以总结来说，rolling期间保持ready的Pod数量为: replicas * (1 - maxUnavailable) <= X <= ceil(replicas * (1 + maxSurge))。然后，会在这个范围值内，优先尝试scaling up，然后再scaling down。其次，当maxSurge和maxUnavailable同时为33%时，是keep 3, don't exceed 6，并且每次scaling down的个数是1，与maxUnavailable看起来无关。

The Rolling strategy will:

  - Execute any pre lifecycle hook.
  - Scale up the new replication controller based on the surge count.
  - Scale down the old replication controller based on the max unavailable count.
  - Repeat this scaling until the new replication controller has reached the desired replica count and the old replication controller has been scaled to zero.
  - Execute any post lifecycle hook.

When scaling down, the Rolling strategy waits for pods to become ready so it can decide whether further scaling would affect availability. If scaled up pods never become ready, the deployment process will eventually time out and result in a deployment failure.

感觉存在逻辑问题的地方是，从描述上看，scale down旧的Pod与等待readiness check通过似乎是并行的。难道不应该是readiness check通过后，才scale down吗？


Recreate Strategy
=================

代码片读::

    strategy:
      type: Recreate
      recreateParams: 
        pre: {} 
        mid: {}
        post: {}

recreateParams are optional. pre, mid, and post are lifecycle hooks.

The Recreate strategy will:

  - Execute any pre lifecycle hook.
  - Scale down the previous deployment to zero.
  - Execute any mid lifecycle hook.
  - Scale up the new deployment.
  - Execute any post lifecycle hook.

During scale up, if the replica count of the deployment is greater than one, the first replica of the deployment will be validated for readiness before fully scaling up the deployment. If the validation of the first replica fails, the deployment will be considered a failure.

利用其中一个副本（第一个）来测试新版本是否ready。

When to Use a Recreate Deployment:

  - When you must run migrations or other data transformations before your new code starts.
  - When you do not support having new and old versions of your application code running at the same time.
  - When you want to use a RWO volume, which is not supported being shared between multiple replicas.

A recreate deployment incurs downtime because, for a brief period, no instances of your application are running. However, your old code and new code do not run at the same time.

因为新旧代码无法同时跑，所以旧的Pod离场前不会有新的Pod登场，所以一定会有一个时间段是无法提供服务的。


Lifecycle Hooks
===============

**Pod-based lifecycle hooks execute hook code in a new pod derived from the template in a deployment configuration.**

代码片段::

    pre:
      failurePolicy: Abort
      execNewPod: {} 
    
execNewPod is a pod-based lifecycle hook.

failurePolicy包括:

  - Abort: The deployment process will be considered a failure if the hook fails.
  - Retry: The hook execution should be retried until it succeeds.
  - Ignore: Any hook failure should be ignored and the deployment should proceed.

当前仅支持pod-based hooks，即运行在pod内的执行检测代码的hook。

代码片段::

    strategy:
      type: Rolling
      rollingParams:
        pre:
          failurePolicy: Abort
          execNewPod:
            containerName: helloworld 
            command: [ "/usr/bin/command", "arg1", "arg2" ] 
            env: 
              - name: CUSTOM_VAR1
                value: custom_value1
            volumes:
              - data 

其中:

  - containerName指向spec.template.spec.containers[*].name，
  - command将会覆盖引用的容器镜像原有的ENTRYPOINT
  - hook pod将会使用env指定的环境变量，以及继承volumes指定的来自dc的卷中的数据
