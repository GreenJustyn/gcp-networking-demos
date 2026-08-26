project-id = "mhanline-playpen002"
apis = [
  "compute.googleapis.com",
  "dns.googleapis.com",
  "oslogin.googleapis.com"
]
regions = [ "australia-southeast1", "australia-southeast2" ]
ip_address_internal1 = "10.229.65.199"
ip_address_internal2 = "10.229.66.199"
routes = [
    {
        name        = "default-syd",
        cidr        = "0.0.0.0/0"
        network     = "vpc-ilb-regional"
        priority    = "800"
        next-hop    = ""
    },
    {
        name  = "default-mel",
        cidr    = "0.0.0.0/0"
        network = "vpc-ilb-regional"
        priority    = "900"
    }
]

vpcs = [
    {
        network                 = "vpc-ilb-regional"
        delete_default_route    = true
        subnets                 = [
           {
                subnet_name = "vpc-ilb-syd"
                cidr_block = "10.229.65.0/24"
                region = "australia-southeast1"
            },
           {
                subnet_name = "vpc-ilb-mel"
                cidr_block = "10.229.66.0/24"
                region = "australia-southeast2"
            }            
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in-vpc-ilb-regional",
        network  = "vpc-ilb-regional",
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
        name = "ssh-access-vpc-ilb-regional",
        network  = "vpc-ilb-regional",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
        sources = [
            "0.0.0.0/0"
        ],
        rules = [
            {
                protocol = "TCP",
                ports = ["22"]
            }
        ],
        target_tags = [
            "allow-ssh"
        ]
    },
    {
        id = "90101",
        name = "health-checks-vpc-ilb-regional",
        network  = "vpc-ilb-regional",
        description = "health checks for ILB",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1101,
        sources = [
            "130.211.0.0/22",
            "35.191.0.0/16"
        ],
        rules = [
            {
                protocol = "TCP",
                ports = ["80", "443"]
            }
        ]
        target_tags = [
            "allow-hc"
        ]
    }
]

psc_ips = [
    {
        network     = "vpc-ilb-regional"
        name        = "psc"
        address     = "10.252.252.101"
    }
]