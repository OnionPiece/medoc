*******************************
Triggering Builds & Build Hooks
*******************************

From https://docs.openshift.com/container-platform/3.9/dev_guide/builds/triggering_builds.html

From https://docs.openshift.com/container-platform/3.9/dev_guide/builds/build_hooks.html


Webhook Triggers
================

对于基于Git的源代码管理系统，OS当前对webhook只支持push event。对于push event推上来的消息，OS会检查其中是否有bc中所引用的branch，如果满足，则会checkout，继而构建，否则不会出发构建。

使用webhook triggers，需要定义一个包含WebHookSecretKey做键的secret。然后由bc.spec.triggers.gitlab.secretReference来引用，当然对于github, bitbucket, generic也都是适用的。bc.spec.triggers.gitlab.secret is Deprecated: use SecretReference instead.


Image Change Triggers
=====================

如果用于构建的依赖镜像发生了改变，那么也可以触发新的build。bc.spec.triggers.imageChange.from。例如当依赖的官方镜像修复了某个bug，或者build依赖的是某个ImageStreamTag所指向的build出来的image，第二种情况的可能场景如，若干个项目，是从某个具体的项目fork出来并发生演变了的。

如果monitor的镜像是bc.spec.strategy中from所指向的镜像，则bc.spec.triggers.imageChange.from需要为空，即{}。否则对于任意monitor的镜像，需要用imageChange.from来指明。这也可以理解，例如当前的构建依赖了某个镜像中的某个包，而不是直接将那个镜像用来做构建的基础镜像，那么就不会在strategy中只想那个镜像。



