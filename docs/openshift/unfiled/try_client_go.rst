*************
Try client-go
*************

背景
====

这只是一个简单的开发笔记，记录一下使用kubernetes/client-go的一点经历。

最初，并不打算使用kubernetes/client-go。但因为在为origin 3.9版本写一个辅助程序时，遇到了点问题，所以不得不学习使用client-go。这个辅助程序是用来解决已删除的容器很难在Elasticsearch中进行日志追溯的问题，期初是通过监听etcd的event，来获取已删除的Pod关联信息。监听到的event kv.Key中能提取出namespace和pod name，而能够提取service信息的event kv.Value却是经过编码的，无法直接使用。

一种思路是学习K8S的代码，了解其encode和decode的方式和过程，然后自己仿照着写decode。但这样难度较大，于是在同事的建议下，学习使用client-go。

所写的辅助程序只针对origin 3.9，对于origin 3.11及之后的版本，相关的数据记录可以通过Prometheus获取。

glide
=====

在kubernetes/client-go的INSTALL.md中，提供了4种安装方式，其中go get方式需要自己解决依赖，而Godep的github主页里却写着“Please use dep or another tool instead.”，再来看Dep，Not supported yet。所以当前来说能用的方式就只有glide了。

虽然INSTALL.md中提到"it's best to avoid Glide's many subcommands"，但个人感觉使用glide create来自行判断依赖关系，自动填写glide.yaml可能更适合项目之初。不过这样就需要项目目录内得先有code，得有import了。不过问题不大，可以使用client-go中的example，in-cluster-client-configuration。

关于 in-cluster-client-configuration
------------------------------------

origin release-3.9，对应k8s 1.9，而对应的client-go是release-6.0，参考使用 https://github.com/kubernetes/client-go/blob/release-6.0/examples/in-cluster-client-configuration/main.go 。

下载main.go后，run `glide init` , 就完成了依赖解析，然后 run `glide up` 完成依赖下载。

虽然是叫做in-cluster，但实际上在测试阶段，不必非得跑在容器里。在开发本可以连通集群的情况下，将pod里的token, ca.crt拷贝到本地对应位置，也是可以将main.go跑起来的。除了准备文件外，运行前，需要定义环境变量KUBERNETES_SERVICE_HOST和KUBERNETES_SERVICE_PORT(8443 for origin)。

出于某种原因，使用ca.crt无法直接将main.go跑起来，但是可以在config(https://github.com/kubernetes/client-go/blob/release-6.0/examples/in-cluster-client-configuration/main.go#L32) 获取后将其修改为Insecure，以及置空CAFile来作为workaround。例如::

        // workaround for "curl -k"
        config.TLSClientConfig.CAFile = ""
        config.TLSClientConfig.Insecure = true

之后，参考API对Pods进行Watch。而获取到的object可以参考https://github.com/kubernetes/client-go/blob/release-6.0/tools/record/event.go#L233 来获取event Object所对应的Pod数据。

etcd
====

获取到的数据，考虑持久化，可以选择存在etcd里。在添加完etcd的库import后，无法直接通过 `glide create` 等方式将etcd加到glide.yaml后，需要首先删除已有的glide.yaml。之后运行命令 `glide up -v` 可能会报错::

        [INFO]	Removing nested vendor and Godeps/_workspace directories...
        [INFO]	Removing: /path/to/your/project/vendor/github.com/coreos/etcd/vendor
        panic: runtime error: invalid memory address or nil pointer dereference
        [signal SIGSEGV: segmentation violation code=0x1 addr=0x30 pc=0x6fdc82]

经观察，glide update的时候，并不会直接将依赖下载到项目目录下的vendor里，而是会先下载到~/.glide/cache中。所以如果cache中github.com/coreos/etcd里就没有vendor，那么remove它会出错可能就有解释了。结果事实确实是那样。使用 `glide up` 不带参数--strip-vendor 或者 -v就可以避免这个问题了。

proxy
=====

glide在拉取如golang.org/x/net, golang.org/x/text等依赖时经常会超时报错，典型的GFW问题。这是可以选择配置全局代理环境变量https_proxy和http_proxy来解决，如::

        export https_proxy=socks5://127.0.0.1:1080
        export http_proxy=socks5://127.0.0.1:1080
