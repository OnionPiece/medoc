****************************
Try python incremental build
****************************

Ref:
  - https://docs.openshift.com/container-platform/3.9/using_images/s2i_images/customizing_s2i_images.html
  - https://docs.openshift.com/container-platform/3.9/dev_guide/builds/build_strategies.html


Try incremental build
=====================

第一个链接提供的信息:

  - 查看镜像是否内置了s2i脚本的方式
  - 自定义脚本调用内置脚本的方法

第二个链接提供的信息:

  - 主要是如何配置Incremental Builds

测试使用平台已经提供的openshift/python:2.7镜像，测试需要基于已经完成的一次构建，对应的bc在下文中叫做pyflask。

第一次尝试incremental build时没有使用s2i的脚本，直接修改bc::

    sourceStrategy:
      from:
        kind: ImageStreamTag
        name: pyflask:latest
      incremental: true

然后用命令触发新的build `oc start-build pyflask` ，构建失败，查看logs `oc logs pyflask-2-build`::

    Pulling image "harbor.example.com/test/pyflask:20180610134909" ...
    /usr/bin/container-entrypoint: line 2: /usr/libexec/s2i/save-artifacts: No such file or directory
    WARNING: Clean build will be performed because of error saving previous build artifacts
    ---> Installing application source ...
    mv: cannot move ‘/tmp/src/.git’ to ‘./.git’: File exists
    error: build error: non-zero (13) exit code from harbor.example.com/test/pyflask@sha256:94f25be9b9e20cfff045e961d09724128e46f213e7aaf5ab5f64537bb7ca1456

其中的报错，save-artifacts 忽略，因为当前我使用的git项目中没有提供。出问题的地方主要是 "mv: cannot move ‘/tmp/src/.git’ to ‘./.git’: File exists"。

通过如下命令可以拉取所引用的is，用以发现 ./.git 确实是已经存在的::

    // latest当前实际指向tag 20180610134909
    docker pull harbor.example.com/test/pyflask:20180610134909
    docker run -it harbor.example.com/test/pyflask:20180610134909 bash
    (app-root) ls -a .

并且可以在该容器内查看到/usr/libexec/s2i 下的内容，即镜像内置的脚本。

接下来，可以添加assemble脚本到git 项目中::

    ls -l .s2i/bin/
    > total 4
    > -rw-rw-r-- 1 zongkai zongkai 469 Jun 10 14:11 assemble

    cat .s2i/bin/assemble 
    > #!/bin/bash
    > echo "Before assembling"
    > rm -rf .git
    > rm -rf .s2i
    > 
    > /usr/libexec/s2i/assemble
    > rc=$?
    > 
    > if [ $rc -eq 0 ]; then
    >     echo "After successful assembling"
    > else
    >     echo "After failed assembling"
    > fi
    > 
    > exit $rc

注意，assemble脚本中除了"rm -rf .git"，还添加了"rm -rf .s2i"，因为.s2i目录也是会被move的，也就是说git项目中所有的目录都会被move，那么在增量build的时候，都会有因为"File exists"而出错的风险。

git push后，重新构建，`oc start-build pyflask`，这次就成功了。并且oc logs可以发现::

    Pulling image "harbor.example.com/test/pyflask:20180610134909" ...
    /usr/bin/container-entrypoint: line 2: /usr/libexec/s2i/save-artifacts: No such file or directory
    WARNING: Clean build will be performed because of error saving previous build artifacts
    Before assembling
    ---> Installing application source ...
    ---> Installing dependencies ...
    Requirement already satisfied (use --upgrade to upgrade): Flask in /opt/app-root/lib/python2.7/site-packages (from -r requirements.txt (line 1))
    Requirement already satisfied (use --upgrade to upgrade): netifaces in /opt/app-root/lib/python2.7/site-packages (from -r requirements.txt (line 2))
    Requirement already satisfied (use --upgrade to upgrade): itsdangerous>=0.24 in /opt/app-root/lib/python2.7/site-packages (from Flask->-r requirements.txt (line 1))
    Requirement already satisfied (use --upgrade to upgrade): Werkzeug>=0.14 in /opt/app-root/lib/python2.7/site-packages (from Flask->-r requirements.txt (line 1))
    Requirement already satisfied (use --upgrade to upgrade): Jinja2>=2.10 in /opt/app-root/lib/python2.7/site-packages (from Flask->-r requirements.txt (line 1))
    Requirement already satisfied (use --upgrade to upgrade): click>=5.1 in /opt/app-root/lib/python2.7/site-packages (from Flask->-r requirements.txt (line 1))
    Requirement already satisfied (use --upgrade to upgrade): MarkupSafe>=0.23 in /opt/app-root/lib/python2.7/site-packages (from Jinja2>=2.10->Flask->-r requirements.txt (line 1))
    After successful assembling
    Pushing image harbor.example.com/test/pyflask:20180610134909 ...
    Pushed 5/11 layers, 45% complete
    Pushed 6/11 layers, 55% complete
    Pushed 7/11 layers, 64% complete
    Pushed 8/11 layers, 73% complete
    Pushed 9/11 layers, 82% complete
    Pushed 10/11 layers, 91% complete
    Pushed 11/11 layers, 100% complete
    Push successful

注意“Requirement already satisfied”，说明已经已经安装过的依赖这次没有再次安装，即增量构建生效了。


Use private pypi
================

python build虽然可以在environment中指定PIP_INDEX_URL，但不提供与trusted-host对应的参数，因此对于某些私有源场景下可能并不好使。此时可以在assemble中通过命令指定index-url和trusted-host来从私有源下载依赖。


With Harbor registry
====================

实际环境中，可能不会使用OpenShift内置的docker registry，而会用Harbor来做镜像仓库。那么这种情况下，对于bc的配置需要做进一步的调整，不然会拉不到之前构建好的s2i镜像，e.g. ::

  output:
    to:
      kind: DockerImage
      name: harbor.example.com/test/pyflask:20180705132658

其中比较蛋疼的地方是image的tag，需要每次在start-build前修改tag，不然新构建出来的image在推到harbor后，会导致较早的具有相同tag的image的tag变为unknown。


Tips
====

修改bc会导致从增量构建回复到一般构建时无法第一时间查找到原有的构建方式，以及相应的基础镜像。对此，可以在bc.metadata.annotations下添加自定义的字段来做相应记录。这样，也便于自动化或产品化。
