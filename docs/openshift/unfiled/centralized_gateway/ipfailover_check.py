#!/usr/bin/python2.7

import json
import os
import requests


if not os.path.exists('/etc/keepalived/last_notify'):
    os.sys.exit(0)
with open('/etc/keepalived/last_notify') as f:
    last_notify = json.load(f)

last_notify_ip = last_notify['csnat_tun_ip']
csnat_tun_ip = os.popen("ip r get 8.8.8.8 | awk '{print $7}'").read().strip()
if csnat_tun_ip != last_notify_ip:
    # not master
    os.sys.exit(0)

last_notify_mac = last_notify['csnat_mac']
csnat_mac = os.popen("ip l show tun0 | awk '/ether/{print $2}'").read().strip()
if csnat_mac == last_notify_mac:
    # centralized SNAT gateway MAC is master dev MAC
    os.sys.exit(0)

vip = os.getenv('OPENSHIFT_HA_VIRTUAL_IPS')
k8s_port = os.getenv('KUBERNETES_PORT')
ns = os.getenv('NAMESPACE')
url_base = 'https%s/api/v1/namespaces/%s/' % (k8s_port[3:], ns)
token = open('/var/run/secrets/kubernetes.io/serviceaccount/token').read()
headers = {'Accept': 'application/json',
           'Authorization': 'Bearer %s' % token}
patch_hdrs = {'Accept': 'application/json',
              'Authorization': 'Bearer %s' % token,
              'Content-Type': 'application/strategic-merge-patch+json'}

r = requests.get(url_base + 'services', headers=headers,  verify=False)
svc_names = [d['metadata']['name'] for d in r.json()['items']
             if vip in d['spec'].get('externalIPs', [])]
patch_data = json.dumps({"metadata": {"annotations": {
    "c_snat_mac": csnat_mac, "c_snat_tun_ip": csnat_tun_ip}}})
for svc in svc_names:
    r = requests.patch(url_base + 'services/' + svc, headers=patch_hdrs,
                       data=patch_data, verify=False)
    if r.status_code != 200:
        os.sys.exit(1)
else:
    with open('/etc/keepalived/last_notify', 'w+') as f:
         f.write(json.dumps({
             'csnat_mac': csnat_mac, 'csnat_tun_ip': csnat_tun_ip}))
    os.sys.exit(0)
