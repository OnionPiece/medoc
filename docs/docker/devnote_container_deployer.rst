**************************
Devnote container deployer
**************************

这是一篇闲散的开发笔记。在我的一个项目里，我通过容器起了一个etcd-cluster，因为某些原因，早先生成的证书在我本地环境发生变化的情况下，无法再服务于etcd-cluster，导致etcd-cluster无法启动。

按照之前的方法及脚本可以重新生成证书，从而使得etcd-cluster能够正常启动。从“好事者”的角度来看，这种因为环境因素，导致测试环境无法搭建起来的情况，其实是可以通过容器来解决的，这样的话，为什么不可以通过容器写一个部署器，来将环境整体搭建起来呢。这包括生成证书，build镜像，以及运行容器。

关于证书生成，参考 https://github.com/kelseyhightower/etcd-production-setup ，但需要稍作修改，修改后 https://github.com/OnionPiece/scripts/blob/master/generate_etcd_cluster_ca_files.sh .

关于docker API，对于golang，可以借助 github.com/docker/docker/client。可能API本文本身并没有太多的example，因此需要借助查看项目的测试代码，以及在github上搜索他人的用例来进行借鉴。这里没有太大的问题，比较困难的地方是在公司网络糟糕的状况下，docker build的时候go get速度非常慢。

其实不只是docker/client，以及像etcd这样的稍大的项目，在go get/git clone的时候都会很耗时。既然如此，何不考虑搭建一个gitlab作为github的本地代理。之后在docker build的时候，通过指定--add-host参数，来将发向github.com的请求转发到本地的gitlab。

不过这样做有两个问题:

  - 无法使用go get，只能先通过git clone \***.git，然后在go install;
  - gitlab可以通过自签证书的方式来enable SSL，但是这样的证书在client端是不认的，因此需要client端自己设置git config --global http.sslVerify false;

这两点都需要修改Dockerfile。但是对于不使用本地代理的情况，git clone暂可接受，而设置git的sslVerify就不合理了。因此，相对较好的方式，是在部署器中，在提取出项目原有的Dockerfile后，通过条件判断是否在加入新字段的方式下生成新的Dockerfile，并用新的Dockerfile来完成镜像的构建。

除了git，同样耗时的任务还有curl和yum install，这两个都可以通过本地搭建一个文件下载服务来进行解决。并且我们不需要构建一个完整的yum repo，只需要通过以下命令获取我们需要的包::

    yum install --downloadonly --downloaddir=. XXX

以我浅薄的知识来看，搭建yum repo似乎只是比一般的http下载服务多了一个createrepo命令，因此我们可以通过一个容器来同时提供yum repo和一般文件的下载。

和git的情况类似，curl的时候也会遇到证书的问题，可以通过在$HOME/.curlrc中写入insecure的方式来避免对Dockerfile中curl命令逐条加-k参数的修改。
