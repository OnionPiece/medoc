******************************************************
Setup local cache servers(containers) for docker build
******************************************************

Gitlab
======

Setup
-----

Refer:

  - [1] https://docs.gitlab.com/omnibus/docker/ , and
  - [2] https://docs.gitlab.com/omnibus/settings/ssl.html#lets-encrypthttpsletsencryptorg-integration .

Image gitlab/gitlab-ce:latest is enough to directly use. Main body of command to run gitlab container can refer [1], but something you may not need, such as:

  - --restart always, the container could be manually started when needed.
  - --publish 443:443 --publish 80:80 --publish 22:22, the main reason not to pushlish container ports to host is to avoid port conflict.

Beside, set the following environment avairable to enable SSL::

    --env GITLAB_OMNIBUS_CONFIG="external_url 'https://<YOUR_CONTAINER_HOSTNAME';"

Import project
--------------

After setup, you can clone projects you need from github, replace origin .git/ with new one you created in gitlab, and push to gitlab.

To use
------

Dockerfile
``````````

To build other images that need projects in the local gitlab container, their Dockerfile need be modified with::

    git config --global http.sslVerify false

to access a source code repo who's "Issuer certificate is invalid."

--add-host
``````````

Use parameter `--add-host` while run `docker build`, to assign local gitlab container IP to replace github.com IP, like::

    docker run --add-host github.com:172.17.0.2

Warning
-------

While building image, you can just choose to get all projects from github.com or from local gitlab container, but not the mixed way.

yum repo & file server
======================

Check https://github.com/OnionPiece/container-localrepo .

Similar to `git clone`, since the server signed certificates by itself, you need one of the following way to skip SSL checking:

  - '-k' for curl
  - `echo "insecure" >> $HOME/.curlrc` for curl
  - '--no-check-certificate' for wget
