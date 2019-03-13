.. _build_inputs:

************
Build Inputs
************

From https://docs.openshift.com/container-platform/3.9/dev_guide/builds/build_inputs.html

How Build Inputs Work
=====================

几种input的相互关系:

  - Inline Dockerfile definations 产生的Dockerfile将覆盖其他input中所使用的Dockerfile。
  - Binary input 与 Git 互斥
  - Input secrets are useful for when you do not want certain resources or credentials used during a build to be available in the final application image produced by the build, or want to consume a value that is defined in a Secret resource.
  - External artifacts 作为补充，可以将其他几种方式中无法提供的文件进行拉取

Whenever a build is run:

  - A working directory is constructed and all input content is placed in the working directory. For example, the input Git repository is cloned into the working directory, and files specified from input images are copied into the working directory using the target path.
    所有的资源都会被放到工作目录

  - The build process changes directories into the contextDir, if one is defined.
    build过程所在的目录可以由bc.spec.source.contextDir指定，以替代默认的工作目录，例如源代码在某个子目录中。build过程将切换到那个目录中。

  - The inline Dockerfile, if any, is written to the current directory.
  - The content from the current directory is provided to the build process for reference by the Dockerfile, custom builder logic, or assemble script. This means any input content that resides outside the contextDir will be ignored by the build.
    build过程将仅能使用当前目录下的资源，包括用相对路径描述的子目录，但此外的资源将被忽略

官方文档中展示一个例子，其中有趣的地方是，可以通过 bc.spec.source.images.paths 将source images中的绝对路径(sourcePath)下的东西，如文件或者路径本身(包含目录)，拷贝到基于build过程所在目录的相对路径(destinationDir)。这就与incremental build有了相互关联，在上次构建完成后，save-artifacts脚本可以将产生的“缓存”收集到某个目录，而下次增量构建时，可以通过paths将这些“缓存”在reload回来。


Dockerfile Source
=================

The typical use for this field is to provide a Dockerfile to a Docker strategy build.

oc explain bc.spec.source.dockerfile


Image Source
============

If the source path ends in /. then the content of the directory will be copied, but the directory itself will not be created at the destination. 	

This feature is not supported for builds using the Custom Strategy.

官方文档中展示的例子说明了可以引用多个images，及他们的files。


Git Source
==========

A valid ref(bc.spec.source.git.ref) can be a SHA1 tag or a branch name.

If the ref field denotes a pull request, the system will use a git fetch operation and then checkout FETCH_HEAD.

When no ref value is provided, OpenShift Container Platform performs a shallow clone (--depth=1). In this case, only the files associated with the most recent commit on the default branch (typically master) are downloaded. This results in repositories downloading faster, but without the full commit history. To perform a full git clone of the default branch of a specified repository, set ref to the name of the default branch (for example master).


Using a Proxy
-------------

bc.spec.source.git.httpProxy, httpsProxy, noProxy.

Cluster administrators can also configure a global proxy for Git cloning using Ansible.


Source Clone Secrets
--------------------

Build使用的是builder sa，因此builder sa需要有权限使用source clone secrets。相关权限的限制是默认开启的，即需要额外的操作来获取使用secrets的权限，如::

    oc secrets link builder mysecret

但也可以通过在master的配置文件中，将属性serviceAccountConfig.limitSecretReferences设置为false来关闭权限限制。

关于secret的使用，有两种方法，一种是在bc.spec.source.sourceSecret中指定，另一种是利用OpenShift提供的自动添加机制。该机制的工作逻辑是，secret创建时添加annotations，annotations的值作为表达式，按照最长匹配规则，用来匹配具体的source地址。当一个bc所对应的build被触发后，OpenShift检查到没有指定secret时，就会使用这种机制来寻找对应的secret。

annotations的key需要以"build.openshift.io/source-secret-match-uri-"为前缀，如"build.openshift.io/source-secret-match-uri-1"；而value需要按照如下格式生成:

  - a valid scheme (\*://, git://, http://, https:// or ssh://).
  - a host (* or a valid hostname or IP address optionally preceded by \*.).
  - a path (/* or / followed by any characters optionally including * characters).

如https://\*.mycorp.com/\* 。

可以使用的source clone secret包括:

  - .gitconfig File
  - Basic Authentication
  - SSH Key Authentication
  - Trusted Certificate Authorities


SSH Key Authentication
``````````````````````

创建secret::

    oc create secret generic <secret_name> --from-file=ssh-privatekey=<path/to/ssh/private/key> \
        --type=kubernetes.io/ssh-auth

Binary Source
=============

不是很清楚这个要怎么用。。。


Input Secrets
=============

仅用于build，而处于安全原因，在构建好的镜像中，secrets将不可用。bc.spec.source.secrets 包含多组destinationDir和secret，代表secret将被copy到的目录，及所引用的secret对象。


Source-to-Image Strategy
------------------------

destinationDir是相对路径，相对与工作目录。考虑到secret需要被copy到指定目录后，类似git clone的工作才能开始，因此，这里的工作目录，就是build过程切换到contextDir前的目录。如果不指定的话，就是工作目录。当指定时，copy的过程中，目标目录不会被创建，因此指定的目标目录必须存在。

当前，secrets文件都是0666的，并且在assemble脚本执行后，就会被truncated to size zero.


Docker Strategy
---------------

When using a Docker strategy, you can add all defined input secrets into your container image using the ADD and COPY instructions in your Dockerfile.

destinationDir所指定的是相对路径，相对与Dockerfile所在的路径，因此当不指定destinationDir时，即默认Dockerfile所在的目录。

在生成的final application image中，secret可以被删除。但是在用于构建的这一层镜像中还是存在的，因此Dockerfile应该包含删除secret文件的操作。


Custom Strategy
---------------

The input secrets are always mounted into the /var/run/secrets/openshift.io/build directory or your builder can parse the $BUILD environment variable, which includes the full build object.


Using External Artifacts
========================

在s2i的assemble和run脚本，或者Dockerfile中下载并使用包或文件的方式，为了提升灵活性，可以使用环境变量的方式来将包或文件放到变量目录，并以变量名的方式调用。
