# OpenShift CLI 导读版

## 前言

本篇内容作为导读，不会详尽的介绍OpenShift  CLI所有 的命令、参数等，毕竟授人以鱼不如授人以渔。所以相对的，本篇会围绕一些能够快速上手OpenShift CLI的切入点进行讲解。

## help & -\-help

OpenShift CLI的客户端是 **oc**，搭建好的OpenShift集群在Master，Node节点上会安装oc，当然管理员也可以在自己的电脑上安装oc客户端来进行管理，而无需SSH登录到OpenShift集群。

oc有着足够充分的命令行文档，因此在任何时候，对任何命令或参数有疑问时，都可以通过-\-help或者help来寻求帮助。获取命令行帮助文档是不需要登录的。

help和-\-help，二者效果相同，却别在于-\-help是个参数，而help是oc的一个命令，这就影响了它们的位置:

    oc help <command>
    oc <command> --help  # --help参数只能放在最后

直接对oc进行help可以得到oc的命令列表，每个命令都会有个简短的描述:

    oc help
    oc --help

## login

使用OpenShift CLI的第一步是登录这个集群，只有login后，你才能管理这个集群。

登录时使用如下命令:

    oc login -u admin https://<YOUR_MASTER_IP>:8443

admin: 我们推荐只有平台管理员才能登录后台，并通过CLI来管理平台。

YOUR_MASTER_IP:

  - 从Master节点login时，可以不指定；
  - 如果Master节点的8443端口通过集群外部的负载均衡进行暴露时，那么从任意位置，都可以通过指定外部负载均衡的IP来登录；
  - 如果Master节点的8443端口没有通过集群外部的负载均衡进行暴露，那么从任意位置，都需要指定任一Master节点的IP来登录。

以上所提到的任意位置，包括管理员在自己电脑上安装了OpenShift CLI的情况。

## project & projects

登录后，CLI会显示出当前用户所允许访问的命名空间/项目。如果只有一个命名空间，那么将会直接使用这个命名空间；而如果有多个，那么在所展示的命名空间列表中，将以星号来标记当前所使用的命名空间。下例所示，当前登录后将使用kube-public这个命名空间。:

    Login successful.

    You have access to the following projects and can switch between them with 'oc project <projectname>':

      caasportal
      default
    * kube-public
      kube-system
      ...
同时，从这里的输出中，也可以看到切换命名空间的命令，即 *oc project <projectname\>* 。例如，可以通过如下命令来切换到default命名空间:

    oc project default

而在其他时候，可以使用如下命令来查看当前所在命名空间，或者所有可以访问的命名空间:

    # 检查当前所在的命名空间/项目
    oc project

    # 一览所有可以访问的命名空间:
    oc projects

OpenShift通过命名空间来隔离资源，因此在后台进行管理时，需要明确当前的命名空间，否则会出现一些诸如想要查找的资源在当前命名空间找不到的、以及在错误的命名空间创建资源的情况。

当然，除了命令 *oc project <projectname\>* ，还可以通过-n参数来在一个命令中进行临时的切换，但这种效果仅仅限于所执行的命令，而不会影响到当前的环境上下文。例如，当我们在kube-public命名空间下，想要查看default命名空间下的Pod资源时，可以执行:

    oc -n default get pod

## get，describe

在进入到所要管理的命名空间后，就可以通过命令来查看、创建、修改、删除资源了。这里面最高频的操作可能就是查看了，对应oc的get命令和describe命令。

get命令可以用来查看一个或多个同类型的资源，该命令的默认输出不会展示过多细节，因此有时候你可能需要通过参数-o，指定wide或者yaml/json来或许更多细节:

    # 获取当前命名空间下所有的Pod，输出一个列表
    oc get pods
    # 获取当前命名空间下所有的Pod，同时展示出它们的IP以及所在的宿主节点
    oc get pods -o wide
    # 仅查看当前命名空间下的名为test-123的Pod
    oc get pod test-123
    # 查看看当前命名空间下的名为test-123的Pod，将该Pod的所有信息以YAML格式输出
    oc get po test-123 -o yaml

上面的命令中，pods/pod/po是Pod这种资源类型的名字与别名，oc并不区分资源类型的单复数形式。

descirbe命令可以用来查看资源的细节，但它与get命令不同，可以理解为：

  - get命令是在针对一个数据表进行查询；
  - 而describe命令则是在内部逻辑关联的基础上，join了多个表进行的查询。

因此:

  - get命令会展示出指定资源类型的全部信息，但仅限于该资源；
  - 而describe命令虽然会显示出关联到的其他资源信息但不会展示资源的全部信息，包括describe指定的资源。

describe命令是无法加-o参数的，毕竟它已经在关联逻辑的作用下格式好的输出。此外，describe会关联资源的一些事件及错误信息，因此当一个服务（包括DeploymentConfig，Pod等）创建失败时，可以通过describe命令查看出错细节。

对于跨命名空间的查询，除了前面所说的-n参数，还可以使用--all-namespaces参数，例如:

    # 查看集群中所有的pods，显示它们的IP和所在宿主节点
    oc get pod -o wide --all-namespaces

## explain

关于资源的创建和修改，最友善的方式不是在命令行中执行，而是在页面上去执行。

由于不同资源在创建时所需要指定参数和配置的复杂程度不同，oc针对所有资源所提供创建命令支持程度也是参差不齐的。但始终我们都可以使用 *oc create -f YAML-FILE/JSON-FILE* 来创建资源。而无论是yaml文件还是json文件都涉及到对OpenShift资源和资源属性的了解。

同理，当我们使用命令 *oc edit RESOURCE-TYPE RESOURE* 来修改资源时，我们也需要清楚该资源的属性。

除了查看官方文档外，oc的命令行文档也对资源的属性信息的讲解提供了一定的支持，即通过explain命令，如：

    # 解释pod资源的所有属性
    oc describe pod
    # 解释pod配置细则中相关的属性
    oc describe pod.spec
    # 解释pod的细则containers属性
    oc describe pod.spec.containers

describe会按照格式：资源.属性.子属性.子属性的子属性 ... 这样的层级关系去逐级展示相关的文档说明。

## export

我们可以借助explain命令对OpenShift资源获得相关的了解，但即使如此，从0开始编写一个资源的YAML文件用于创建也是很难的。这也包括了页面上提供的template，或者服务编排的功能。

oc提供了export命令来为这种棘手的问题提供支持。你可以使用export命令从一个已经创建的资源提取出它的yaml文件（当然也可以是json文件），该文件中包含了所指定资源的所有配置和参数的，因此在修改名字和label等元数据后，是可以拿来创建相同资源的。

命令举例:

    # 导出指定deploymentConfig
    oc export dc myApp
    # 导出满足指定label，app为myApp的deploymentConfig, service, route资源
    oc export dc,svc,route -l app=myApp > myApp.yml

在获得yaml文件后，我们通常需要对该文件进行一些修改，包括名字，label，以及删除status，才能进一步用于后续的使用。

## status，logs, rsh

在介绍describe命令时，我们提到它可以查看资源创建时的一些错误细节信息。除此之外，我们还可以用status和logs两个命令从其他角度查看到资源的错误状态及原因。

status命令用来查看当前命名空间下的概览信息，包括所创建的资源。同时，当某些资源创建出错时，它也会从OpenShift可以理解的角度提示出一些修改的方法。这里所谓的OpenShift可以理解的角度，包括某个应用需要特殊权限等平台层面的东西，而不包括应用代码里的问题。

而想要查看应用代码本省出错的一些信息，则需要借助logs命令，它可以打印出Pod的日志以便相关人员进行排查。因为K8S/OpenShift要求容器里的应用需要运行在foreground，因此所有的出错细节都会在输出到标准输出后，被OpenShift的日志系统所接受，因此也就可以通过logs命令查看到。

这两个命令常见的用法如下:

    oc status -v
    oc logs -f POD-NAME

除了上述命令，有些情况下，我们可能还需要登录到Pod/容器内部去查看里面的一些细节，此时，就需要使用rsh命令，当然它也像SSH一样支持运行远程命令，但这需要所执行的命令是被容器所支持的:

    # “SSH”登录到容器中
    oc rsh POD
    # 指定命令在容器中执行
    oc rsh POD cat /etc/app/app.conf

## adm

不同与之前的命令，adm是一个面向平台的命令，它包含了更多的子命令用来维护平台，维护集群本身，从名字上可以看出它完全是面向管理员的。也因此，本问将不会展开对该命令的讲解，只是针对其中一些点进行简单描述，用于建立印象。

policy。所有关于权限，如RBAC，如SCC（Security Container Context）的管理都会使用到policy子命令。一些可能的情况包括，为某个应用授权，使得它的容器可以:

  - 以root用户运行；
  - 获得查看集群相关信息的权利。

manage-node，顾名思义，用于管理集群的节点，包括开启与关闭节点的调度（以接受Pod部署到节点），从节点上疏散（迁移）Pod，列出选定节点上的所用Pod。

drain。类似于manage-node，但是它会先关闭节点的调度，然后再开始驱逐节点上的Pod。

taint。向节点添加“污点”，“污点”可以理解为节点向Pod暴露出的某种标签，这种标签可以让Pod更有选择性的去调度和部署。例如，我们可以向节点添加dedicated的标签，来表明这个节点将被弃用，那么无法忍受这种污点的Pod将可以避免调度到这个节点上。

pod-network。借助这个命令，我们可以管理命名空间的网络隔离性，例如和其他命名空间打通，或者接触打通以恢复隔离，或者变为全局可访问的。

值得说明的是，adm的子命令中并不含列出集群中所有节点的命令，因为node，即节点在某种程度上也是集群的一种资源。对此，我们可以使用命令 *oc get node* 来查看集群中的所有节点。
