****************
S2I Requirements
****************

From:
  - https://docs.openshift.com/container-platform/3.9/creating_images/s2i.html
  - https://github.com/openshift/source-to-image/blob/master/docs/builder_image.md


Build Process
=============

To do so, S2I creates a **tar** file that contains the sources and scripts, then streams that file into the builder image. Before executing the **assemble** script, S2I untars that file and places its contents into the location specified by the **io.openshift.s2i.destination** label from the builder image, with the default location being the **/tmp** directory.

For this process to happen, your image must supply the **tar** archiving utility (the tar command available in $PATH) and the command line interpreter (the **/bin/sh** command); this allows your image to use the fastest possible build path. If the tar or /bin/sh command is not available, the s2i build process is forced to automatically perform an additional container build to put both the sources and the scripts inside the image, and only then run the usual build.

在download sti scripts后，会检查是否是incremental build，如果是就save-artifacts，即将之前构建产生的artifacts挪窝，否则在新一轮构建中可能会覆盖。


S2I Scripts
===========

可以以任意语言来写，只要script在builder image中是可执行的。如果是非shell脚本，则需要相应的解释器。

s2i脚本的检查/调用顺序是:

  - bc中所指定的（bc.spec.strategy.sourceStrategy.scripts，如"http(s)://path_to_scripts_dir"，或"file\:///path_to_scripts_dir"）
  - 源码中.s2i/bin目录下的
  - 由io.openshift.s2i.scripts-url指定的images中的目录


assemble
--------

assemble将构建应用的artifacts，并将它们放到合适的目录，用于服务启动使用。workflow是:

  - Restore build artifacts。在增量构建时，save-artifacts会将artifacts挪到/tmp（默认）目录下，而当需要复用时，需要把它们挪回来。
  - Place the application source in the desired location. location 应该是有参数可以指定目录的，参考 :ref:`build inputs <build_inputs>` 。
  - Build the application artifacts.
  - Install the artifacts into locations appropriate for them to run.

此外，如果希望assemble的用户不同于将来运行容器的用户，那么可以使用io.openshift.s2i.assemble-user来指定。

exmaple::

    #!/bin/bash
    
    # restore build artifacts
    if [ "$(ls /tmp/s2i/artifacts/ 2>/dev/null)" ]; then
        mv /tmp/s2i/artifacts/* $HOME/.
    fi
    
    # move the application source
    mv /tmp/s2i/src $HOME/src
    
    # build application artifacts
    pushd ${HOME}
    make all
    
    # install the artifacts
    make install
    popd


save-artifacts
--------------

收集上次构建（也就是本次构建开始前的镜像内的现场环境）的artifacts以及dependencies。For example:

  - For Ruby, gems installed by Bundler.
  - For Java, .m2 contents.

These dependencies are gathered into a tar file and streamed to the standard output. 如果不用io.openshift.s2i.destination来指定目录的话，默认就是/tmp，那么所收集的路径下的内容，文件及目录结构等都会原样“复制”到/tmp下。注意下面例子中的注释， **Besides the tar command, all other output to standard out must be surpressed.  Otherwise, the tar stream will be corrupted.**

**Note: it is critical that the save-artifacts script output only include the tar stream output and nothing else.**

example::

    #!/bin/bash
    
    # Besides the tar command, all other output to standard out must 
    # be surpressed.  Otherwise, the tar stream will be corrupted.
    pushd ${HOME} >/dev/null
    if [ -d deps ]; then
        # all deps contents to tar stream
        tar cf - deps
    fi
    popd >/dev/null

