******************************
Nginx bidirection certifaction
******************************


Why need this
-------------

It will spend some time and several paragraphs to describe why we need HTTPS,
which I'm not good at. So I just list some points to help people who has no
experience and knowledge on web stuff like me:

* HTTP is not security encouraged, since it transmits plain text. So it's
  possible for attacker to get your username, password and other things on a
  website when you access it.
* HTTPS is short for HTTP over TLS/SSL, which means after SSL connection is
  established, all data transmission are encrypted, and security encouraged.
* Even on server side, with SSL encrpyted, we still cannot ensure it's safe
  for communication between clients and websites. Since SSL only work for an
  enstablished connection, but not stage before handshake. How can we trust
  a website, confirm it is the one whom it declares to be, but not a spoofing
  one. To solve this, we need some trusted authority organizations to make an
  arbitrament to tell us identification of a website. And that's what
  Certification Authority(CA) does. CA send signed certification to sites, to
  prove they are themselves. Once we visit a website with HTTPS enabled, our
  web client will check its certification and tell us the site can be trusted
  or not(which means it's a fake one built by middleman, or it doesn't have a
  signed certification from CA).

And what for clent side authentication? For most cases, no need. But when your
site is only accessable for few invited users, and you think authentication via
password is not safe enough, you can try this.


My scenario
-----------

We have a inner wiki system(Web) on a private network, it can access Internet
(egress) but not the opposite way(ingress), and it's not on VPN service list.
So I can access it from home. And my target is that I can access it from home,
and keep safe, and only my team members can access it, not others.


Things before doing nginx configuration
---------------------------------------

FYI, the instance on cloud I built runs Ubuntu 16.04 LTS as OS, so some details
may be different if you're using another OS or release.

Before building bidirection certifaction, the following things need to be done:


The sshd configuration
``````````````````````

We may need login the cloud instance via SSH, to install/config softwares and
do some other maintaining works. So it makes sense to give cloud instance
security enhanced SSH. To make it, we need make sshd use publickey, password,
and keyboard-interactive(PAM with **google-authenticator**) as
**AuthenticationMethods**. The sshd will use these methods to do authentication
checking one by one, and the authentication checking will be passed only when
all methods passed, and will fail no matter which one fails.

* configure /etc/ssh/sshd_config, the following configurations will be
  need::

    ChallengeResponseAuthentication yes
    UsePAM yes
    AuthenticationMethods publickey,keyboard-interactive
    PubkeyAuthentication yes
    AllowUsers Alice Bob ... last-user

* configure /etc/pam.d/sshd::

    # Standard Un*x authentication.
    @include common-auth

    auth required pam_google_authenticator.so

  I guess the above common-auth stands for publickey and password, but not so
  sure.

* (optional) For maintaining reason, we may need let wiki mechine access the
  cloud instance without password and google-authentication.

  In /etc/ssh/sshd_config::

    Match User inner-wiki
        AuthenticationMethods publickey
        PasswordAuthentication no

* install google-authenticator::

    sudo apt install libpam-google-authenticator

  After generate secret key via ``google-authenticator`` command, as an
  optional way, you can use ``oathtool`` command to get your dynamically
  generated secret, like::

    oathtool --totp -b YOUR_SECRET


SSH port forwarding
```````````````````

Build SSH port forwarding(SSH Tunnel) for wiki(webserver), and make sure the
cloud instance can access wiki via localhost forwarded port.

The following simple example tries to build an SSH tunnel from inner webserver
to cloud instance, and let cloud instance can access webserver 80 port via its
8080 port on localhost::

    ssh -NC -o ExitOnForwardFailure=yes -R localhost:8080:localhost:80 USER@REMOTE &

You can use ``man ssh`` and ``man ssh_config`` to inquire the above options,
-N, -C, and -o with ExitOnForwardFailure.

* configure nginx for forwarding to the forwarded port on last step


Generate private CA
```````````````````

Since our website(instance on cloud) is only for private purpose, and only
invited users can access it, so a private CA is enough.

* Modify */etc/ssl/openssl.cnf*. Most default configurations are good
  enough to use, so we only need modify necessary ones here:

  * in [CA_default] section::

      [ CA_default ]

      dir             = /etc/ssl/CA           # Where everything is kept
      ...

  * in [req_distinguished_name] section::

      [req_distinguished_name]
      ...
      countryName_default             = YOUR_COUNTRY_NAME
      ...
      stateOrProvinceName_default     = YOUR_STATE_OR_PROVINCE_NAME
      ...
      localityName_default            = YOUR_LOCALITY_NAME
      ...
      0.organizationName_default      = YOUR_ORGANIZATION_NAME
      ...
      organizationalUnitName_default  = YOUR_ORGANIZATION_UNIT_NAME
      ...
      commonName_default              = YOUR_SERVER_FQDN_OR_NAME

  Per https://stackoverflow.com/questions/27891193/error-opening-ca-private-key-on-ubuntu?rq=1,
  absolute paths should be used for *dir* under CA_default section, on Ubuntu.

  If you have another path prefer to, you can replace path */etc/ssl/CA* with
  it. Folder CA may not exists under */etc/ssl*, we need *mkdir* it and
  *chmod 700* for it.

  It's recommonded to set the above default names, since they are required to
  generate certification files for both server and client, and we don't want to
  input twice, and introduce any error caused by typo mistake.

* Per some options in CA_default section in *openssl.cnf*, such as
  new_certs_dir, database, we will need create some folders and files under our
  CA path::

    cd /etc/ssl/CA/
    touch index.txt
    echo 01 > serial
    mkdir private newcerts

* Generate RSA private key for root certifications::

    cd /etc/ssl/CA/
    openssl genrsa -out private/cakey.pem 2048
    # for security reason, it's recommend to modify cakey.pem file priviledge
    chmod 600 private/cakey.pem

  You can use command ``openssl genrsa --help`` to check the above arguments.

* Generate CA request. To generate a CA root certification, we need generate a
  CA request first::

    cd /etc/ssl/CA/
    openssl req -new -days 365 -key private/cakey.pem -out careq.csr
    # per https://ubuntuforums.org/showthread.php?t=1883758, cacert.pem should
    # created
    openssl req -new -x509 -nodes -sha1 -days 365 -key private/cakey.pem -out cacert.pem

  You can use command ``man req`` to check the above arguments.

  With running this command, you will be asked to fill some information, such
  as "Country Name", "Locality Name". And since we have modified the defaults
  values as shown above, so you can just press enter key to skip filling.

* Do self-sign on the request we get in last step, to generate a CA root
  certification::

    cd /etc/ssl/CA/
    openssl ca -selfsign -in careq.csr -out cacert.crt

    # once sigature is complete, it will output like:
    Signature ok
    Certificate Details:
      ...
    Certificate is to be certified until SOME_FUTURN_TIME (365 days)
    Sign the certificate? [y/n]:y
      ...
    1 out of 1 certificate requests certified, commit? [y/n]y
    Write out database with 1 new entries
    Data Base Updated

  Now we get our private CA root certification, the cacert.crt file. And we
  no longer need careq.csr, you can just delete it.

  And optionally, the above two steps can be combined into one command::

    openssl req -new -x509 -key private/cakey.pem -out cacert.crt


Generate user certification
```````````````````````````

Let's generate private key and certification files for two users, nginx
and nginx client.

Similar to above steps to generate private CA root certification::

    cd /etc/ssl/CA
    # to distinguish nginx files from CA server
    mkdir nginx
    openssl genrsa -out nginx/nginx.key 2048
    openssl req -new -days 365 -key nginx/nginx.key -out nginx/nginx.req
    openssl ca -in nginx/nginx.req -out nginx/nginx.crt

    cd /etc/ssl/CA
    # to distinguish client files from CA server
    mkdir client
    openssl genrsa -out client/client.key 2048
    openssl req -new -days 365 -key client/client.key -out client/client.req
    openssl ca -in client/client.req -out client/client.crt

For step generating client CA request, to fill the asked information, you
may like to use default values. That's OK, but at least one of the following
fields should be different from one used by our root CA certification:

- Country Name
- State or Province Name
- Locality Name
- Organization Name
- Organizational Unit Name
- Common Name
- Email Address



Configure Nginx
---------------

Suppose you have nginx installed already, and you have server configured like::

    server {
        listen *:80;
        server_name mywiki.mydomain.io;
        client_max_body_size 100M;
        location / {
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Server $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_pass http://localhost:8080/;
            client_max_body_size 100M;
        }
    }


Enable HTTPS in nginx
`````````````````````

To enable HTTPS(SSL) in nginx, you can choose putting the following options
into a server config section, or in a server config file(if it has multiple
servers)::

    ssl on;
    ssl_certificate  /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key   /etc/nginx/ssl/nginx.key;

The first way will only work for a single server, and the later one will work
for all servers in the file.

The path /etc/nginx/ssl need be created if not exist, and for files nginx.crt
and nginx.key, you can copy ones we generated before.

It's recommended to make nginx service reload, to check whether https works.


Enable client certification
```````````````````````````

For client certification, similar to above step, you will need insert the
following options::

    ssl_client_certificate  /etc/nginx/ssl/client.crt;
    ssl_verify_client on;


Generate browser importable certification
`````````````````````````````````````````

To test with web browser, we will need generate a importable file for browser
to use::

    openssl pkcs12 -export -clcerts -in client.crt -inkey client.key -out client.p12

For Firefox, after importing certification, you may need restart Firefox.
For Chrome and IE, tests failed.
