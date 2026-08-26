#List of project IDs to put in the perimeter. At present it only takes the first one.
nameprefix = "mh"
project-id = "mhanline-playpen002"
region = "asia-southeast1"
psc-ip  = "10.3.0.5"
apis = [
  "compute.googleapis.com",
  "dns.googleapis.com",
  "oslogin.googleapis.com"
]
vpcs = [
    {
        network                 = "net-psc-apis"
        subnets                 = [
           {
                subnet_name     = "sub-psc-apis"
                cidr_block      = "10.229.82.0/24"
                region          = "asia-southeast1"
                pga             = true
            }
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in",
        network  = "net-psc-apis",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1001,
        sources = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12"
        ],
        rules = [
            {
                protocol = "TCP"
            },
            {
                protocol = "UDP"
            },
            {
                protocol = "ICMP"
            }
        ]
    },
    {
        id = "90005",
        name = "ssh-access-http-lb",
        network  = "net-psc-apis",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
        source_list = [ "iap-forwarders" ],
        rules = [
            {
                protocol = "TCP",
                ports = ["22"]
            }
        ]
    }
]

virtual_machines = [
    {
        name            = "testvm01"
        subnet          = "sub-psc-apis"
        region          = "asia-southeast1"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-12"
        cidrhostnum     = "50"
        script          = "./debian-12-client.sh.tftpl"
    }
]