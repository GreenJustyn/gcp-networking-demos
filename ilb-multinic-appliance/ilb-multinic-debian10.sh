#!/bin/bash
# Enable IP forwarding:
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/20-iptables.conf
# Read VM network configuration:
md_vm="http://metadata.google.internal/computeMetadata/v1/instance/"
md_net="$md_vm/network-interfaces"
NIC0_GW="$(curl $md_net/0/gateway -H "Metadata-Flavor:Google" )"
NIC0_MASK="$(curl $md_net/0/subnetmask -H "Metadata-Flavor:Google")"
NIC0_ADDR="$(curl $md_net/0/ip -H "Metadata-Flavor:Google")"
NIC0_ID="$(ip addr show | grep $NIC0_ADDR | awk '{print $NF}')"
NIC1_GW="$(curl $md_net/1/gateway -H "Metadata-Flavor:Google")"
NIC1_MASK="$(curl $md_net/1/subnetmask -H "Metadata-Flavor:Google")"
NIC1_ADDR="$(curl $md_net/1/ip -H "Metadata-Flavor:Google")"
NIC1_ID="$(ip addr show | grep $NIC1_ADDR | awk '{print $NF}')"

# Source based policy routing for nic1 for UHC
echo "100 rt-nic1" >> /etc/iproute2/rt_tables
ip rule add pri 32000 from $NIC1_GW/$NIC1_MASK table rt-nic1
sleep 1
ip route add 35.191.0.0/16 via $NIC1_GW dev $NIC1_ID table rt-nic1
ip route add 130.211.0.0/22 via $NIC1_GW dev $NIC1_ID table rt-nic1
# 
apt-get update
apt-get install apache2 tcpdump -y
a2ensite default-ssl
a2enmod ssl
echo "HTTP OK" | \
tee /var/www/html/index.html
systemctl restart apache2