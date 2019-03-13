#!/usr/bin/python2.7

import json
import os
import requests

if os.sys.argv[3] != "MASTER":
    os.sys.exit(0)
vip = os.getenv('OPENSHIFT_HA_VIRTUAL_IPS')
k8s_port = os.getenv('KUBERNETES_PORT')
ns = os.getenv('NAMESPACE')
url_base = 'https%s/api/v1/namespaces/%s/' % (k8s_port[3:], ns)
token = open('/var/run/secrets/kubernetes.io/serviceaccount/token').read()
csnat_mac = os.popen("ip l show tun0 | awk '/ether/{print $2}'").read().strip()
csnat_tun_ip = os.popen("ip r get 8.8.8.8 | awk '{print $7}'").read().strip()

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
