project-id = "mhanline-playpen002"
region = "us-central1"
zone1 = "us-central1-a"
zone2 = "us-central1-c"
name = "asdf"
ip_address_internal = "10.229.65.199"
ip_address_external = "10.229.64.199"

vpcs = [
    {
        network    =   "vpc-internal"
        subnets   =  [
           {
                subnet_name = "vpc-internal-subnet"
                cidr_block = "10.229.65.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        network    =   "vpc-external"
        subnets   =  [
            {
                subnet_name = "vpc-external-subnet"
                cidr_block = "10.229.64.0/24"
                region = "asia-southeast1"
            }
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in-int",
        network  = "vpc-internal",
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
        name = "rfc1918-in-ext",
        network  = "vpc-external",
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
        name = "ssh-access",
        network  = "vpc-external",
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
        id = "90004",
        name = "health-checks-ext",
        network  = "vpc-external",
        description = "health checks for ILB",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1004,
        sources = [
            "130.211.0.0/22",
            "35.191.0.0/16"
        ],
        rules = [
            {
                protocol = "TCP",
                ports = ["80"]
            }
        ]
        target_tags = [
            "allow-hc"
        ]
    },
    {
        id = "90005",
        name = "health-checks-int",
        network  = "vpc-internal",
        description = "health checks for ILB",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1005,
        sources = [
            "130.211.0.0/22",
            "35.191.0.0/16"
        ],
        rules = [
            {
                protocol = "TCP",
                ports = ["80"]
            }
        ],
        target_tags = [
            "allow-hc"
        ]
    }
]