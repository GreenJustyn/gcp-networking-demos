#Copyright 2024 Google LLC.
#SPDX-License-Identifier: Apache-2.0
#!/bin/bash
exec 5> startup_script_deb.txt
BASH_XTRACEFD="5"
PS4='$LINENO: '
set -x
# Enable IP forwarding:
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/20-iptables.conf
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install apache2 tcpdump dnsutils -y
# Read VM network configuration:
MD_NET="http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces"
NIC0_GW="$(curl -s $MD_NET/0/gateway -H "Metadata-Flavor:Google" )"
NIC0_MASK="$(curl -s $MD_NET/0/subnetmask -H "Metadata-Flavor:Google")"
NIC0_ADDR="$(curl -s $MD_NET/0/ip -H "Metadata-Flavor:Google")"
NIC0_ID="$(ip addr show | grep $NIC0_ADDR | awk '{print $NF}')"
NIC1_GW="$(curl -s $MD_NET/1/gateway -H "Metadata-Flavor:Google")"
NIC1_MASK="$(curl -s $MD_NET/1/subnetmask -H "Metadata-Flavor:Google")"
NIC1_ADDR="$(curl -s $MD_NET/1/ip -H "Metadata-Flavor:Google")"
NIC1_ID="$(ip addr show | grep $NIC1_ADDR | awk '{print $NF}')"

iptables -t nat -A POSTROUTING -o $NIC0_ID -j MASQUERADE
GOODLE_DNS1="$(dig +short dns.google | sort | head -n 1)"
GOODLE_DNS2="$(dig +short dns.google | sort | tail -n 1)"
iptables -t nat -A PREROUTING -p tcp -s 35.191.0.0/16 -d $NIC0_ADDR --dport 443 -j DNAT --to $GOODLE_DNS1
iptables -t nat -A PREROUTING -p tcp -s 130.211.0.0/22 -d $NIC0_ADDR --dport 443 -j DNAT --to $GOODLE_DNS2

# Source based policy routing for nic1 for UHC
echo "100 rt-nic1" >> /etc/iproute2/rt_tables
ip rule add pri 32000 from $NIC1_GW/$NIC1_MASK table rt-nic1
sleep 1
ip route add 35.191.0.0/16 via $NIC1_GW dev $NIC1_ID table rt-nic1
ip route add 130.211.0.0/22 via $NIC1_GW dev $NIC1_ID table rt-nic1
ip route add 10.0.0.0/8 via $NIC1_GW dev $NIC1_ID table rt-nic1
echo "HTTP OK" | tee /var/www/html/index.html
systemctl restart apache2

cat <<EOF > /etc/skel/.bash_aliases
alias startuplog='sudo journalctl -u google-startup-scripts.service'
alias ll='ls -lF --time-style=long-iso'
EOF