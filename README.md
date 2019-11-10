# `systemd-nspawn` Bootstrap

## Make a list of hosts (32 here, you might pick fewer):

    export CHEESE_HOSTS="swiss menonita cheddar pepperjack gouda manchego paneer feta mozzarella brie provolone ricotta havarti edam mascarpone blue kalari halloumi luneberg saga lappi myzithra greve labneh oka cotija colby jack limburger sardo chevre roquefort"

## SSH Trust

### Steps
(Perform in /home/mdye/projects/ops-bootstrap)

* Make an `SSH_ASKPASS script` and a domain CA key

      echo "guarddatcheeze" | ./SSH-keys-and-certs/bin/generate-askpass
      SSH-keys-and-certs/bin/generate-ca cheeseforce.org

* Generate and sign some host keys

      echo $CHEESE_HOSTS | sed 's, ,\n,g' | time xargs -i -n1 -P0 SSH-keys-and-certs/bin/generate-and-sign-host cheeseforce.org {}

* Generate and sign user SSH key (this uses askpass created earlier). We use 'admin' as principal since that's the name of the user account in our nspawn containers:

      SSH-keys-and-certs/bin/sign-user cheeseforce.org admin --new

* View the content of the SSH user certificate:

      ssh-keygen -L -f /home/mdye/projects/nspawn-bootstrap/SSH-keys-and-certs/generated/cheeseforce.org-admin-key-cert.pub

## `systemd-nspawn` Containers

### Preconditions

#### Bridge setup

The following assumes you have `privbridge` as your external interface:

    sudo su -
    ip link add conhole type bridge

    echo "1" > /proc/sys/net/ipv4/ip_forward

    ip addr add 172.31.0.254/20 dev conhole

    iptables -I INPUT 1 -m conntrack --ctstate NEW -i conhole -j ACCEPT
    iptables -t nat -A POSTROUTING -s 172.31.0.0/20 -o privbridge -j MASQUERADE
    iptables -A FORWARD -i privbridge -o conhole -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i conhole -o privbridge -j ACCEPT
    iptables -A FORWARD -i conhole -o conhole -j ACCEPT

    dnsmasq --interface=conhole --listen-address=172.31.0.254 \
      --bind-interfaces --bogus-priv \
      --domain-needed --domain=cheeseforce.org \
      --dhcp-range=172.31.9.0,172.31.11.253 -q -d &

    ip link set dev conhole up


#### Resolver Delegation

For maximum convenience when accessing an nspawn container via SSH, set up your system's resolver to use dnsmasq. I use `systemd-resolved` so overriding my host's DNS server involves the following content in `/etc/systemd/resolved.conf`:

    [Resolve]
    DNS=172.31.0.254
    FallbackDNS=9.9.9.9
    ...

I then restart the daemon with `systemctl restart systemd-resolved`. If I forget to revert these settings and shut down dnsmasq, my system still resolves external names, just slowly. This is a hacky and temporary solution; when using permanent containers I attach them to a proper Linux bridge or use MACVLAN and a dedicated DHCP server w/ DNS coordination.

It's possible to work around some of this resolution and DHCP / DNS nonsense by executing dnsmasq with a DHCP hook:

      --dhcp-script=./SSH-keys-and-certs/bin/ssh-config-hostname-hook
      ...

This hook will replace `Hostname ..` entries in the generated SSH config with IPs after they're assigned by dnsmasq. This still interferes with SSH trust as configured in this system, but sidesteps DNS monkeying.

### Steps
(Perform in /home/mdye/projects/ops-bootstrap)

(N.B. There are some optimizations here we're not taking: 1) we install packages post-base-imaging which duplicates effort; 2) we don't start nspawn containers with cow FS layers. Both of these could be pursued if desired)

* (optional) In the host system, install ubuntu-keyring with some trusted out-of-band mechanism. For arch linux:

      sudo pacman -Sy community/ubuntu-keyring

* Make a container base image (sudo is for the fs mounting):


      sudo bash -c "(export TEMPDIR=/home/mdye/tmp; \
        rm -Rf ./container-bootstrap/machines/*; \
        ./container-bootstrap/build -y -o ./container-bootstrap/machines \
        -g base -p cheese |& tee /tmp/base.out)"

* Make a bunch of container filesystems. Note that this is an i/o heavy operation and is nicely replaced by starting nspawn containers with '-x' in some cases:

      echo $CHEESE_HOSTS | sed 's, ,\n,g' | time xargs -n1 -P0 -i sudo bash -c \
        '(export TEMPDIR=/home/mdye/tmp; \
          ./container-bootstrap/build -f {}.cheeseforce.org -y \
          -o ./container-bootstrap/machines -b ./container-bootstrap/machines/base \
          -p cheese -s ./SSH-keys-and-certs/generated \
          |& tee ./container-bootstrap/machines/{}-prov.out; \
          echo "finished {}")'

      find ./container-bootstrap/machines/* -maxdepth 0 -type d

* Start containers (one per terminal, 'menonita' for example):

      sudo systemd-nspawn --network-bridge=conhole -b -D ./container-bootstrap/machines/menonita.cheeseforce.org

      sudo systemd-nspawn --network-bridge=conhole --quiet --register=yes --boot --directory ./container-bootstrap/machines/menonita.cheeseforce.org &

* Start a bunch:

      echo $CHEESE_HOSTS  | sed 's, ,\n,g' | xargs -n1 -P0 -i sudo sh -c \
        "systemd-nspawn --network-bridge=conhole --quiet --register=yes \
          --boot --directory ./container-bootstrap/machines/{}.cheeseforce.org & disown %1"

* Get a console on one cheese host:

      sudo machinectl login menonita.cheeseforce.org

* Use the generated SSH config to SSH to a machine and jump about:

      ssh -F ./SSH-keys-and-certs/generated/ssh-config menonita
      ssh -F ./SSH-keys-and-certs/generated/ssh-config -J menonita,sardo,saga swiss

* Use `su` to become superuser (with root's password):

      ssh -F ./SSH-keys-and-certs/generated/ssh-config cheddar
      su -
      (enter text: 'cheese')

* (optional) Because of principal in `/root/.ssh/authorized_principals`, ssh to root@<machine> is possible too:

      ssh -F ./SSH-keys-and-certs/generated/ssh-config root@gouda

## Miscellaneous Content

#### SSH trust quick facts

1. `/etc/ssh/ssh_known_hosts` used for trusting user hosts
   (`/etc/ssh/sshd_config` of destination host must contain entry like `"HostCertificate /etc/ssh/ssh_host_ed25519_key-pepperjack.cheeseforce.org-cert.pub"`)

1. `/etc/ssh/ca_keys` used for trusting signed user keys; (principal in `$HOME/.ssh/authorized_principals` must match incoming username *even if same same*)
   (`/etc/ssh/sshd_config` of destination host must contain entry like `"TrustedUserCAKeys /etc/ssh/ca_keys"`)

### Useful Commands

* Stop all nspawn containers:

      machinectl list --no-pager --no-legend | awk '{print $1}' | xargs -n1 -i sudo machinectl terminate {}

* Reset SSH state (**dangerous**):

      find ./SSH-keys-and-certs/generated -type f -print0 | xargs -0 -i sh -c 'sudo chattr -i {} && rm {}'

* Erase container state:

      sudo rm -Rf ./container-bootstrap/machines/*.*
      sudo rm -Rf ./container-bootstrap/machines/base

* List containers:

      machinectl list

* List process tree for a container:

      machinectl --full

* Create a known hosts file for cheeseforce.org and SSH from the host system to one of the cheese systems (note that we do a lot of this automatically in then SSH setup scripts):

      cat > SSH-keys-and-certs/generated/cheeseforce.org-known-hosts<<EOF
      @cert-authority * $(cat SSH-keys-and-certs/generated/cheeseforce.org-ca.pub)
      EOF

      ssh -o 'UserKnownHostsFile=./SSH-keys-and-certs/generated/cheeseforce.org-known-hosts' \
        -o CertificateFile=./SSH-keys-and-certs/generated/id_rsa-admin-key-cert.pub \
        -o IdentityFile=./SSH-keys-and-certs/generated/id_rsa-admin-key \
        -o KbdInteractiveAuthentication=no \
        -o PreferredAuthentications=gssapi-with-mic,gssapi-keyex,hostbased,publickey \
        -o PasswordAuthentication=no \
        -o User=root -o ConnectTimeout=10 $(host mozzarella.cheeseforce.org 172.31.0.254)
