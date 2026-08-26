#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
mv /etc/apt/sources.list /etc/apt/sources.list.old
echo "deb https://packages.cloud.google.com/apt debian-buster-mirror main" > /etc/apt/sources.list
apt-get update
apt-get install apache2 tcpdump -y
echo "HTTP OK" | \
tee /var/www/html/index.html
systemctl restart apache2

cat <<EOF > /etc/skel/.bash_aliases
alias startuplog='sudo journalctl -u google-startup-scripts.service'
EOF