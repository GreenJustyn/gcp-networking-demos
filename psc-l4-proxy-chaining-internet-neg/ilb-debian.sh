#Copyright 2025 Google LLC.
#SPDX-License-Identifier: Apache-2.0
#!/bin/bash
exec 5> startup_script_deb.txt
BASH_XTRACEFD="5"
PS4='$LINENO: '
set -x

if test -f /startup-script-finished.txt; then   exit 1; fi

cat <<EOF > /etc/skel/.bash_aliases
alias startuplog='sudo journalctl -u google-startup-scripts.service'
alias ll='ls -lh'
alias lal='ls -lah'
EOF
cat /etc/skel/.bash_aliases >> /root/.bashrc
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install tcpdump dnsutils apache2 -y
MD_VM="http://169.254.169.254/computeMetadata/v1/instance/"
VM_HOSTNAME="$(curl $MD_VM/name -H "Metadata-Flavor:Google" )"
VM_NETWORK="$(curl $MD_VM/network-interfaces/0/network -H "Metadata-Flavor:Google" | cut -d/ -f4)"
VM_ZONE="$(curl $MD_VM/zone -H "Metadata-Flavor:Google" | cut -d/ -f4)"
echo "Page on $VM_HOSTNAME in network $VM_NETWORK zone $VM_ZONE" | \
tee /var/www/html/index.html
systemctl restart apache2
touch /startup-script-finished.txt