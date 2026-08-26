#! /bin/bash
# Enable IP forwarding:
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/20-iptables.conf
# Read VM network configuration:
md_vm="http://169.254.169.254/computeMetadata/v1/instance/"
md_net="$md_vm/network-interfaces"
nic0_gw="$(curl $md_net/0/gateway -H "Metadata-Flavor:Google" )"
nic0_mask="$(curl $md_net/0/subnetmask -H "Metadata-Flavor:Google")"
nic0_addr="$(curl $md_net/0/ip -H "Metadata-Flavor:Google")"
nic1_gw="$(curl $md_net/1/gateway -H "Metadata-Flavor:Google")"
nic1_mask="$(curl $md_net/1/subnetmask -H "Metadata-Flavor:Google")"
nic1_addr="$(curl $md_net/1/ip -H "Metadata-Flavor:Google")"
nic2_gw="$(curl $md_net/2/gateway -H "Metadata-Flavor:Google")"
nic2_mask="$(curl $md_net/2/subnetmask -H "Metadata-Flavor:Google")"
nic2_addr="$(curl $md_net/2/ip -H "Metadata-Flavor:Google")"
# Source based policy routing for nic1
echo "100 rt-nic1" >> /etc/iproute2/rt_tables
ip rule add pri 32000 from $nic1_gw/$nic1_mask table rt-nic1
sleep 1
ip route add 35.191.0.0/16 via $nic1_gw dev eth1 table rt-nic1 
ip route add 130.211.0.0/22 via $nic1_gw dev eth1 table rt-nic1
# Start iptables:
iptables -t nat -F
iptables -t nat -A POSTROUTING \
-s $nic0_gw/$nic0_mask \
-d $nic1_gw/$nic1_mask \
-o eth1 \
-j SNAT \
--to-source $nic1_addr
iptables -t nat -A POSTROUTING \
-s $nic1_gw/$nic1_mask \
-d $nic0_gw/$nic0_mask \
-o eth0 \
-j SNAT \
--to-source $nic0_addr
iptables-save
# Use a web server to pass the health check for this example.
# You should use a more complete test in production.
apt-get update
apt-get install apache2 -y
a2ensite default-ssl
a2enmod ssl
echo "Example web page to pass health check" | \
tee /var/www/html/index.html
systemctl restart apache2