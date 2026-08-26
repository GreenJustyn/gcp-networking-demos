#!/bin/bash -x
# Enable IP forwarding:
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/20-iptables.conf
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install tcpdump dnsutils -y
# Read VM network configuration:
MD_NET="http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces"
NIC0_GW="$(curl -s $MD_NET/0/gateway -H "Metadata-Flavor:Google" )"
NIC0_MASK="$(curl -s $MD_NET/0/subnetmask -H "Metadata-Flavor:Google")"
NIC0_ADDR="$(curl -s $MD_NET/0/ip -H "Metadata-Flavor:Google")"
NIC0_ID="$(ip addr show | grep $NIC0_ADDR | awk '{print $NF}')"

iptables -t nat -A POSTROUTING -o $NIC0_ID -j MASQUERADE
GOODLE_DNS1="$(dig +short dns.google | sort | head -n 1)"
GOODLE_DNS2="$(dig +short dns.google | sort | tail -n 1)"
iptables -t nat -A PREROUTING -p tcp -s 35.191.0.0/16 -d $NIC0_ADDR --dport 443 -j DNAT --to $GOODLE_DNS1
iptables -t nat -A PREROUTING -p tcp -s 130.211.0.0/22 -d $NIC0_ADDR --dport 443 -j DNAT --to $GOODLE_DNS2

cat <<EOF > /etc/skel/.bash_aliases
alias startuplog='sudo journalctl -u google-startup-scripts.service'
alias ll='ls -lh'
alias lal='ls -lah'
EOF