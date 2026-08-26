apis = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com",
    "networkconnectivity.googleapis.com"
]
ip_address_internal = "10.229.65.199"
ip_address_external = "10.229.64.199"
routes = [
    {
        name  = "default-0000",
        cidr    = "0.0.0.0/0"
        network = "vpc-trust"
        priority    = "800"
    }
]

peerings = [
    {
        network_a   = "vpc-hub"
        network_b   = "vpc-spoke-1"
        peeringname = "hub-spoke1"
    },
    {
        network_a   = "vpc-hub"
        network_b   = "vpc-spoke-2"
        peeringname = "hub-spoke2"
    },
]


vms = [
    {
        project-id  = "mhanline-ncc-01"
        name        = "testvm-hub"
        region      = "asia-southeast1"
        subnet      = "vpc-hub-subnet"
        network     = "vpc-hub"
        size        = "e2-micro"
    },
    {
        project-id  = "mhanline-ncc-01"
        name        = "testvm-spoke-1"
        region      = "asia-southeast1"
        subnet      = "vpc-spoke-1-subnet"
        network     = "vpc-spoke-1"
        size        = "e2-micro"
    },
    {
        project-id  = "mhanline-ncc-01"
        name        = "testvm-spoke-2"
        region      = "asia-southeast1"
        subnet      = "vpc-spoke-2-subnet"
        network     = "vpc-spoke-2"
        size        = "e2-micro"
    },
    {
        project-id  = "mhanline-ncc-01"
        name        = "testvm-spoke-3"
        region      = "asia-southeast1"
        subnet      = "vpc-spoke-3-subnet"
        network     = "vpc-spoke-3"
        size        = "e2-micro"
    }
]

vpcs = [
    {
        project-id              = "mhanline-ncc-01"
        network                 = "vpc-hub"
        delete_default_route    = true
        subnets                 = [
           {
                subnet_name = "vpc-hub-subnet"
                cidr_block = "10.229.65.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        project-id              = "mhanline-ncc-01"
        network                 = "vpc-spoke-1"
        delete_default_route    = true
        subnets                 =  [
           {
                subnet_name = "vpc-spoke-1-subnet"
                cidr_block = "10.229.66.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        project-id              = "mhanline-ncc-01"
        network                 = "vpc-spoke-2"
        delete_default_route    = true
        subnets                 =  [
           {
                subnet_name = "vpc-spoke-2-subnet"
                cidr_block = "10.229.67.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        project-id              = "mhanline-ncc-01"
        network                 = "vpc-spoke-3"
        subnets   =  [
            {
                subnet_name = "vpc-spoke-3-subnet"
                cidr_block = "10.229.64.0/24"
                region = "asia-southeast1"
            }
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in-int-trust",
        network  = "vpc-hub",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1001,
        project-id = "mhanline-ncc-01"
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
        name = "rfc1918-in-int-spoke1",
        network  = "vpc-spoke-1",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
        project-id = "mhanline-ncc-01"
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
        name = "rfc1918-in-int-spoke2",
        network  = "vpc-spoke-2",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
        project-id = "mhanline-ncc-01"
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
        name = "rfc1918-in-int-spoke-3",
        network  = "vpc-spoke-3",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1004,
        project-id = "mhanline-ncc-01"
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
        name = "ssh-access-hub",
        network  = "vpc-hub",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
        project-id = "mhanline-ncc-01"
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
        name = "ssh-access-spoke-1",
        network  = "vpc-spoke-1",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
        project-id = "mhanline-ncc-01"
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
        id = "90007",
        name = "ssh-access-spoke-22",
        network  = "vpc-spoke-2",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1007,
        project-id = "mhanline-ncc-01"
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
        id = "90008",
        name = "ssh-access-spoke-3",
        network  = "vpc-spoke-3",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
        project-id = "mhanline-ncc-01"
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
    }
]
