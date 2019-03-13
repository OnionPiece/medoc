**********************************
Python flask 在 OpenShift 上的试水
**********************************

1. 随便搞了已有的Python项目，通过[智能构建]，产生一个镜像，部署失败。通过 *oc logs POD* 发现::

    WARNING: file 'app.py' not found.
    ERROR: don't know how to run your application.
    Please set either APP_MODULE or APP_FILE environment variables, or create a file 'app.py' to launch your application.


2. 新建一个Python项目，里面有一个 *app.py* ::

    from flask import Flask
    application = Flask(__name__)
    
    @application.route("/")
    def hello():
        return "Hello World!"
    
    if __name__ == "__main__":
        application.run()

以及一个 *requirements.txt* ::

    Flask

重新构建一个新镜像，部署成功。由于flask启动的app，默认监听在5000端口，因此需要在web portal上编辑容器端口到5000。再次通过URL访问失败，报错503。

通过 *tcpdump -tnni vethXXX* 对比发现:

  - 可以访问的服务，与master的Cluster IP有周期性的握手成功
  - 不可访问的服务，与master的Cluster IP无法建立周期性的握手，服务会主动Rst

所用容器没有 *netstat* 命令，且没有权限安全。通过命令 *lsof -i :5000* 发现服务是跑在 *localhost* 上的， *curl POD_IP:5000* 确认如此。

3. 修改 *app.py* ::

    application.run(host='0.0.0.0')

重新构建，部署，修改端口。访问成功。
