**************
Health Checker
**************


Readiness Probe
===============

A readiness probe checks if the container is ready to handle requests. A failed readiness probe means that a container should not receive any traffic from a proxy, even if it's running.


TCP Socket
----------

dc.spec.template.spec.containers.readinessProbe::

    failureThreshold: 3      // default 3, min 1
    initialDelaySeconds: 3   // delay after containers has started
    periodSeconds: 10        // default 10, min i1
    successThreshold: 1      // consecutive successes for the probe to be
                             // considered successful, must 1 for liveness,
                             // defautl and min are 1
    tcpSocket:
      port: 5000
    timeoutSeconds: 2        // probe timeout will be considered as failed

Setup a python flask container with::

    from flask import Flask
    application = Flask(__name__)

    @application.route("/")
    def hello():
        return "Hello World!"

    if __name__ == "__main__":
        application.run(host='0.0.0.0')   # default listen on 5000

On web console, set *Port* to 5000, *Initial Delay* to 3(seconds) and *Timeout* to 2(seconds).

After adding readiness probe, new deployment created, which cause new pod created. Since everything is OK, probe found new created pod works, a few later, the old pod is terminated.

No chaning to router pod haproxy configures.

Modify health-checker port to wrong number, new pod get deployed, but not ready, and "Receiving Traffic" is false. The old pod not get deleted, and keep running, svc is still only online. **Since both router pod haproxy configures and iptables rules on node still route service to the old working pod**.

Modify health-checker port to corrent one, the failed one is terminated. After new created one is ready, the old running one is terminated.

Modify svc target port, new dc, pod created. New dc inherits old probe. "Receiving Traffic" is true, but svc is offline.

*tcpdump* on vethXXX found, probe will shake hands and *fin* with pod from node where pod resides on, via tun0 IP. This is different from router pod health check.

*tcpdump* on *any* confirm the probe check is from node hosting pod.


HTTP GET
--------

Beside the above 3 parameters, *path* is also needed, default is *\/* .

It's sending *HTTP GET* now. 

readinessProbe now is::

    failureThreshold: 3
    httpGet:
      path: /
      port: 5000
      scheme: HTTP
    initialDelaySeconds: 3
    periodSeconds: 10
    successThreshold: 1
    timeoutSeconds: 2

Modify flask app with::

    ready_cnt = 0

    @application.route("/ready")
    def ready():
        global ready_cnt
        ready_cnt += 1
        if (ready_cnt / 5) % 2 != 0:
            return "Ready!"
        return "Not ready", 503

Pod will be switch between ready and not ready periodically, *oc get pod* will show that. The same to **"Receiving Traffic", thus, node iptables and router pod haproxy will add or remove configurations for pod when ready or not ready**.


HTTP GET Use HTTPS
------------------

The above *scheme* now is *HTTPS* . I only changed health check, with turn on *Use HTTPS* , and left pod running HTTP service. A new pod is creating, but is not ready to *Receiving Traffic* , so the old pod is not get deleted.


Container Command
-----------------

Enter the command to run inside the container. The command is considered successful if its exit code is 0. Drag and drop to reorder arguments. 

I added a command *ps -ef | grep python* , and readinessProbe now is::

    exec:
      command:
      - ps -ef | grep python
    failureThreshold: 3
    initialDelaySeconds: 3
    periodSeconds: 10
    successThreshold: 1
    timeoutSeconds: 1

Failed, new created pod wont up.

I tried *docker exec -it CONTAINER "ps -ef | grep python"* failed with "no such file or directory".

Later I checked https://github.com/chef-cookbooks/docker/issues/377#issuecomment-133052184 and https://stackoverflow.com/questions/27158840/docker-executable-file-not-found-in-path?answertab=votes#tab-top , then tried *docker exec -it CONTAINER "sh" "-c" "ps -ef | grep python"* , it works.

On web console, adding *sh* , *-c* , *ps -ef | grep python* as three commands in order, it works, new pod get created and up.

readinessProbe now is::

    exec:
      command:
      - sh
      - -c
      - ps -ef | grep python
    failureThreshold: 3
    initialDelaySeconds: 3
    periodSeconds: 10
    successThreshold: 1
    timeoutSeconds: 1


Liveness Probe
==============

A liveness probe checks if the container is still running. If the liveness probe fails, the container is killed. 

Similar to readiness probe, but when probe failed, pod will be restarted. But it won't impact "Receiving Traffic".
