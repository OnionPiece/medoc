*************************
ubuntu shadowsocks server
*************************

VPS SSH Security Enhance
========================

0. Use `ssh-keygen` to generate ssh keys.

1. Edit .ssh/authorized_keys, adding id_rsa.pub into it.

2. To use PAM google authenticator, package libpam-google-authenticator need to be installed::

    apt install libpam-google-authenticator

3. Edit /etc/ssh/sshd_config with following changes::

    ChallengeResponseAuthentication yes
    UsePAM yes
    AuthenticationMethods publickey,keyboard-interactive
    PubkeyAuthentication yes

   For ssh, checking order will be public-key, password, and google authentication password.

4. Edit /etc/pam.d/sshd with::

    # Standard Un*x authentication.
    @include common-auth

    auth required pam_google_authenticator.so

5. Set up time-based (TOTP) verification, run `google-authenticator`, then for each prompts::

    Do you want authentication tokens to be time-based (y/n)  // y
    
    Do you want me to update your "/root/.google_authenticator" file (y/n)  // y
    
    Do you want to disallow multiple uses of the same authentication
    ...
    your chances to notice or even prevent man-in-the-middle attacks (y/n)  // y
    
    By default, tokens are good for 30 seconds and in order to compensate for
    ...
    size of 1:30min to about 4min. Do you want to do so (y/n)  // n
    
    If the computer that you are logging into isn't hardened against brute-force
    ...
    Do you want to enable rate-limiting (y/n)  // y

  Remember to scan the QR code with your phone, and records the secret key, verification code and emergency scratch codes.

6. Restart sshd service.


Install and configure shadowsocks service
=========================================

0. Install via apt::

    apt install shadowsocks

1. Edit /etc/shadowsocks/config.json, like::

    {
        "server":"0.0.0.0",
        "server_port":54321,
        "password":"Your_password_here",
        "timeout":300,
        "method":"aes-256-cfb",
        "fast_open": true,
        "workers": 1
    }

2. Restart shadowsocks service.


Configure shadowsocks client
============================

0. Follow https://github.com/shadowsocks/shadowsocks/tree/master to insatll.

1. Configure your sslocal config like::

    {
        "server":"VPS_IP",
        "server_port":the_server_port_above,
        "local_port":1080,
        "password":"the_password_above",
        "timeout":300,
        "method":"aes-256-cfb"
    }

2. Use sslocal command to start your local shadowsocks client.
