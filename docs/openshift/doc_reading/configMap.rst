*********
ConfigMap
*********

From https://docs.openshift.com/container-platform/3.5/dev_guide/configmaps.html


Overview
========

The ConfigMap object provides mechanisms to inject containers with configuration data while keeping containers agnostic of OpenShift Enterprise. A ConfigMap can be used to store fine-grained information like individual properties or coarse-grained information like entire configuration files or JSON blobs.

ConfigMap提供了一种机制用来向容器注入配置数据，同时保持容器对于平台的不可知，即服务与配置分离，镜像不依赖与平台。CM可以用来存储键值对，或者整个配置文件，或者JSON块。

The ConfigMap API object holds key-value pairs of configuration data that can be consumed in pods or used to store configuration data for system components such as controllers. ConfigMap is similar to secrets, but designed to more conveniently support working with strings that do not contain sensitive information.

CM存储的键值对可以被用户的容器或者系统组建容器来使用。CM和secrets相似，但更便于存储不含敏感数据。

Configuration data can be consumed in pods in a variety of ways. A ConfigMap can be used to:

  - Populate the value of environment variables.
  - Set command-line arguments in a container.
  - Populate configuration files in a volume.

CM存储的配置数据可以有三种方式被Pod所使用，即环境变量，命令行参数，以及卷文件。

Both users and system components may store configuration data in a ConfigMap.


Creating CM
===========

Use *oc create cm -h* to see creation examples.

相关的操作看命令行的help更直观且容易。 键值对的来源有三种，由键值对构成的文件，包含键值对文件的目录，逐字指定。来源于文件的，如果不指定key，将用文件名做key。

可以多文件，如 *oc create cm --from-file=1.conf --from-file=2.conf ...* 。


Use Cases: Consuming CM in Pods
===============================

Consuming in Environment Variables
----------------------------------

Use pod.spec.containers.env.valueFrom.configMapKeyRef. e.g.::

    spec:
      containers:
        - name: test-container
          env:
            - name: SPECIAL_TYPE_KEY
              valueFrom:
                configMapKeyRef:
                  name: special-config
                  key: special.type

after pod setup, an environment variable named *SPECIAL_TYPE_KEY* will use value from CM *special-config* key *special.type* .


Setting Command-line Arguments
------------------------------

Like *Consuming in Environment Variables* , but refer to them in a container’s command using the $(VAR_NAME) syntax. Like::

    command: [ "/bin/sh", "-c", "echo $(SPECIAL_LEVEL_KEY) $(SPECIAL_TYPE_KEY)" ]


Consuming in Volumes
--------------------

Use:

  - pod.spec.volumes.configMap, to generate a file from key of CM data, with value as file content
  - pod.spec.containers.volumeMounts, to mount volume(the file) to specified path

e.g.::

    containers:
      volumeMounts:
      - mountPath: /test
        name: my-conf
    volumes:
    - configMap:
        defaultMode: 420
        name: my-conf
      name: my-conf

需要volumes.configMap来产生相应的卷文件，然后有volumeMounts来挂在该文件。


Restrictions
============

A ConfigMap must be created before they are consumed in pods. Controllers can be written to tolerate missing configuration data; consult individual components configured via ConfigMap on a case-by-case basis.

ConfigMap objects reside in a project. They can only be referenced by pods in the same project.

The Kubelet only supports use of a ConfigMap for pods it gets from the API server. This includes any pods created using the CLI, or indirectly from a replication controller. It does not include pods created using the OpenShift Enterprise node’s --manifest-url flag, its --config flag, or its REST API (these are not common ways to create pods).
