***********
Ubuntu snap
***********

proxy
=====

(run as root)

snap get system

# using polipo to listen on 8123
snap set system proxy.http="http://localhost:8123"
snap set system proxy.https="http://localhost:8123"

apps
====

(run as root)

snap install electronic-wechat
snap install remarkable
snap install code --classic
