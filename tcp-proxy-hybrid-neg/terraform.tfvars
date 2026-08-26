project-id = "mhanline-playpen002"
apis = [
  "compute.googleapis.com",
  "dns.googleapis.com",
  "oslogin.googleapis.com"
]
regions = [ "asia-southeast1" ]
ip_address_internal1 = "10.229.65.199"
ip_address_internal2 = "10.229.66.199"
routes = [
]

vpcs = [
    {
        network                 = "tcp-proxy-hybrid-consumer"
        subnets                 = [
           {
                subnet_name     = "consumer-sub-sin"
                cidr_block      = "10.229.65.0/24"
                region          = "asia-southeast1"
            },
            {
                subnet_name     = "consumer-sub-sin-proxy"
                cidr_block      = "10.229.0.0/22"
                region          = "asia-southeast1"
                purpose         = "REGIONAL_MANAGED_PROXY"
                role            = "ACTIVE"
            }
        ]
    },
    {
        network                 = "tcp-proxy-hybrid-producer"
        subnets                 = [
           {
                subnet_name = "producer-sub-sin"
                cidr_block = "10.229.95.0/24"
                region = "asia-southeast1"
            },
           {
                subnet_name = "producer-sub-sin-pupi"
                cidr_block = "21.0.0.0/22"
                region = "asia-southeast1"
            }   
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in-consumer",
        network  = "tcp-proxy-hybrid-consumer",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1001,
        sources = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12",
            "21.0.0.0/8"
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
        id = "90002",
        name = "rfc1918-in-producer",
        network  = "tcp-proxy-hybrid-producer",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
        sources = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12",
            "21.0.0.0/8"
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
        name = "ssh-access-producer",
        network  = "tcp-proxy-hybrid-producer",
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
        id = "90006",
        name = "ssh-access-consumer",
        network  = "tcp-proxy-hybrid-consumer",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1004,
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
        name = "health-checks-vpc-consumer",
        network  = "tcp-proxy-hybrid-consumer",
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
    },
    {
        id = "90102",
        name = "health-checks-vpc-produccer",
        network  = "tcp-proxy-hybrid-producer",
        description = "health checks for ILB",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1102,
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
    }
]

psc_ips = [
    {
        network     = "vpc-ilb-regional"
        name        = "psc"
        address     = "10.252.252.101"
    }
]