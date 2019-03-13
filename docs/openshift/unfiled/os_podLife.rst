****************************
OpenShift blog: A Pod's Life
****************************

From:

  - [1] https://blog.openshift.com/kubernetes-pods-life/
  - [2] https://kubernetes.io/docs/concepts/workloads/pods/pod/
  - [3] https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/#hook-details

[1]
Pending: The API Server has created a pod resource and stored it in etcd, but the pod has not been scheduled yet, nor have container images been pulled from the registry.

A good way to get an idea of what exactly has happened is to execute kubectl describe pod/$PODNAME and look at the Events.

[2]
When a user requests deletion of a pod the system records the intended grace period before the pod is allowed to be forcefully killed, and a TERM signal is sent to the main process in each container. Once the grace period has expired the KILL signal is sent to those processes and the pod is then deleted from the API server. If the Kubelet or the container manager is restarted while waiting for processes to terminate, the termination will be retried with the full grace period.

If the pod has defined a preStop hook, it is invoked inside of the pod. If the preStop hook is still running after the grace period expires, step 2 is then invoked with a small (2 second) extended grace period.

[3]
There are two hooks that are exposed to Containers:

  - PostStart: This hook executes immediately after a container is created. However, there is no guarantee that the hook will execute before the container ENTRYPOINT. No parameters are passed to the handler.
  - PreStop: This hook is called immediately before a container is terminated. It is blocking, meaning it is synchronous, so it must complete before the call to delete the container can be sent. No parameters are passed to the handler.

also check *oc explain pod.spec.containers.lifecycle* .

我觉得或许这两个hooks可以用于服务的注册与注销。


Pod phase
=========

The phase is not intended to be a comprehensive rollup of observations of Container or Pod state, nor is it intended to be a comprehensive state machine.

phase既不打算成为容器状态观察结果的综合归纳，也不打算成为综合状态机。只是一个阶段描述。

Here are the possible values for phase:

  - Pending: The Pod has been accepted by the Kubernetes system, but one or more of the Container images has not been created. This includes time before being scheduled as well as time spent downloading images over the network, which could take a while.
  - Running: The Pod has been bound to a node, and all of the Containers have been created. At least one Container is still running, or is in the process of starting or restarting.
  - Succeeded: All Containers in the Pod have terminated in success, and will not be restarted.
  - Failed: All Containers in the Pod have terminated, and at least one Container has terminated in failure. That is, the Container either exited with non-zero status or was terminated by the system.
  - Unknown: For some reason the state of the Pod could not be obtained, typically due to an error in communicating with the host of the Pod

Pending似乎主要与镜像获取有关？


Container probes
================

readinessProbe: If the readiness probe fails, the endpoints controller removes the Pod’s IP address from the endpoints of all Services that match the Pod.

我没有直接观察过endpoints，不过就相应的Router Pod HAProxy的观察结果来看，当Pod的readiness probe不是success的时候，Pod的IP会从HAproxy的backend中摘除。


When should you use liveness or readiness probes?
=================================================

If you want your Container to be able to take itself down for maintenance, you can specify a readiness probe that checks an endpoint specific to readiness that is different from the liveness probe.

自维护性是区别与服务是ready的另一种场景。

Note that if you just want to be able to drain requests when the Pod is deleted, you do not necessarily need a readiness probe; on deletion, the Pod automatically puts itself into an unready state regardless of whether the readiness probe exists. The Pod remains in the unready state while it waits for the Containers in the Pod to stop.

删除的时候，Pod会自动进入unready状态，无论是否有probe。


Pod lifetime
============

Pods with a phase of Succeeded or Failed for more than some duration (determined by the master) will expire and be automatically destroyed.

Use a DaemonSet for Pods that need to run one per machine, because they provide a machine-specific system service.

三类controller, Job，ReplicationController/ReplicaSet/Deployment，DaemonSet 分别面向单次任务，用户的服务类任务，系统级的服务任务。

If a node dies or is disconnected from the rest of the cluster, Kubernetes applies a policy for setting the phase of all Pods on the lost node to Failed.


Example states
==============

Pod is running and has one Container. Container runs out of memory.

  - Container terminates in failure.
  - Log OOM event.
  - If restartPolicy is:

    - Always: Restart Container; Pod phase stays Running.
    - OnFailure: Restart Container; Pod phase stays Running.
    - Never: Log failure event; Pod phase becomes Failed.

Pod is running, and a disk dies.

  - Kill all Containers.
  - Log appropriate event.
  - Pod phase becomes Failed.
  - If running under a controller, Pod is recreated elsewhere.

Pod is running, and its node is segmented out.

  - Node controller waits for timeout.
  - Node controller sets Pod phase to Failed.
  - If running under a controller, Pod is recreated elsewhere.


Not finished yet.
