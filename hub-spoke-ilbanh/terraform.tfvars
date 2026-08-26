project-id = "mhanline-playpen002"
apis = [
  "compute.googleapis.com",
  "dns.googleapis.com",
  "oslogin.googleapis.com"
]
region = "asia-southeast1"
vpn_ips = ["169.254.0.0/30", "169.254.1.0/30", "169.254.0.4/30", "169.254.1.4/30"]

peerings = [
    {
        network_a   = "vpc-hub-int"
        network_b   = "vpc-spoke-a"
        peeringname = "hub-int-spoke-b"
    },
    {
        network_a   = "vpc-hub-int"
        network_b   = "vpc-spoke-b"
        peeringname = "hub-int-spoke-b"
    }
]

vpn_peers = [
    {
        network_a   = "vpc-spoke-a"
        network_b   = "vpc-onprem-a"
    },
    {
        network_a   = "vpc-spoke-b"
        network_b   = "vpc-onprem-b"
    }
]

virtual_machines = [
    {
        name            = "inst-spoke-a"
        subnet          = "spoke-a-subnet"
        region          = "asia-southeast1"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-11"
        #script          = "./debian-11-client.sh.tftpl"
    },
    {
        name            = "inst-spoke-b"
        subnet          = "spoke-b-subnet"
        region          = "asia-southeast1"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-11"
        #script          = "./debian-11-client.sh.tftpl"
    },
    {
        name            = "inst-onprem-a"
        subnet          = "onprem-a-subnet"
        region          = "asia-southeast1"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-11"
        #script          = "./debian-11-client.sh.tftpl"
    },
    {
        name            = "inst-onprem-b"
        subnet          = "onprem-b-subnet"
        region          = "asia-southeast1"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-11"
        #script          = "./debian-11-client.sh.tftpl"
    }
]

vpcs = [
    {
        network                 = "vpc-hub-int"
        delete_default_route    = true
        subnets                 = [
           {
                subnet_name = "hub-int-subnet"
                cidr_block = "10.229.65.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        network                 = "vpc-spoke-a"
        delete_default_route    = true
        subnets                 =  [
           {
                subnet_name = "spoke-a-subnet"
                cidr_block = "10.229.66.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        network                 =   "vpc-spoke-b"
        delete_default_route    = true
        subnets                 =  [
           {
                subnet_name = "spoke-b-subnet"
                cidr_block = "10.229.67.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        network                 =   "vpc-hub-ext"
        subnets   =  [
            {
                subnet_name = "hub-ext-subnet"
                cidr_block = "10.230.65.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        network                 = "vpc-onprem-a"
        delete_default_route    = true
        subnets                 =  [
           {
                subnet_name = "onprem-a-subnet"
                cidr_block = "10.240.66.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        network                 =   "vpc-onprem-b"
        delete_default_route    = true
        subnets                 =  [
           {
                subnet_name = "onprem-b-subnet"
                cidr_block = "10.240.67.0/24"
                region = "asia-southeast1"
            }
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in-int-hub",
        network  = "vpc-hub-int",
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
        id = "90002",
        name = "rfc1918-int-spoke-a",
        network  = "vpc-spoke-a",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
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
        id = "90003",
        name = "rfc1918-int-spoke-b",
        network  = "vpc-spoke-b",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
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
        id = "90004",
        name = "rfc1918-in-int-untrust",
        network  = "vpc-hub-ext",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1004,
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
        name = "ssh-access-hub-ext",
        network  = "vpc-hub-ext",
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
    },
    {
        id = "90006",
        name = "ssh-vpc-hub-int",
        network  = "vpc-hub-int",
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
    },
    {
        id = "90007",
        name = "ssh-spoke-a",
        network  = "vpc-spoke-a",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1007,
        source_list = [ "iap-forwarders" ],
        rules = [
            {
                protocol = "TCP",
                ports = ["22"]
            }
        ]
    },
    {
        id = "90008",
        name = "ssh-spoke-b",
        network  = "vpc-spoke-b",
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
    },
    {
        id = "90101",
        name = "health-checks-vpc-int",
        network  = "vpc-hub-int",
        description = "health checks for ILB",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1101,
        source_list = [ "health-checkers"],
        rules = [
            {
                protocol = "TCP",
                ports = ["80", "443"]
            }
        ]
    },
    {
        id = "90102",
        name = "health-checks-hub-ext",
        network  = "vpc-hub-ext",
        description = "health checks for ILB",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1102,
        source_list = [ "health-checkers"],
        rules = [
            {
                protocol = "TCP",
                ports = ["80"]
            }
        ]
    },
    {
        id = "90103",
        name = "health-checks-spoke-a",
        network  = "vpc-spoke-a",
        description = "health checks for ILB",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1103,
        source_list = [ "health-checkers"],
        rules = [
            {
                protocol = "TCP",
                ports = ["80"]
            }
        ]
    },
    {
        id = "90104",
        name = "health-checks-spoke-b",
        network  = "vpc-spoke-b",
        description = "health checks for ILB",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1104,
        source_list = [ "health-checkers"],
        rules = [
            {
                protocol = "TCP",
                ports = ["80"]
            }
        ]
    },
    {
        id = "90202",
        name = "rfc1918-int-onprem-a",
        network  = "vpc-onprem-a",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
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
        id = "90203",
        name = "rfc1918-int-onprem-b",
        network  = "vpc-onprem-b",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
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
        id = "90107",
        name = "ssh-onprem-a",
        network  = "vpc-onprem-a",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1007,
        source_list = [ "iap-forwarders" ],
        rules = [
            {
                protocol = "TCP",
                ports = ["22"]
            }
        ]
    },
    {
        id = "90108",
        name = "ssh-onprem-b",
        network  = "vpc-onprem-b",
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