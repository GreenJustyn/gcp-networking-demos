project-id-consumer = "mhanline-playpen002"
project-id-producer = "mhanline-playpen002"
region  = "asia-southeast1"
apis    = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com"
]
vpcs = [
    {
        network     = "net-a"
        project-id  = "mhanline-playpen002"
        subnets     =  [
           {
                subnet_name = "sub-a"
                cidr_block  = "10.221.100.0/23"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-a-lb"
                cidr_block  = "10.221.102.0/28"
                region      = "asia-southeast1"
            }
        ]
    },
    {
        network     = "net-b"
        project-id  = "mhanline-playpen002"
        subnets     =  [
           {
                subnet_name = "sub-b"
                cidr_block  = "10.221.200.0/23"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-b-lb"
                cidr_block  = "10.221.202.0/28"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-b-psc-nat"
                cidr_block  = "10.221.203.0/24"
                region      = "asia-southeast1"
                purpose     = "PRIVATE_SERVICE_CONNECT"
            }
        ]
    }
]

fw_rules = [
    {
        id          = "90001",
        project-ids = "mhanline-playpen002",
        name        = "rfc1918-in-a",
        network     = "net-a",
        description = "RFC1918 Ingress",
        action      = "allow",
        direction   = "INGRESS",
        log_config  = "DISABLED",
        priority    = 1001,
        sources     = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12"
        ],
        rules       = [
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
        id          = "90004",
        project-ids = "mhanline-playpen002",
        name        = "ssh-access-int-a",
        network     = "net-a",
        description = "SSH Ingress",
        action      = "allow",
        direction   = "INGRESS",
        log_config  = "DISABLED",
        priority    = 1004,
        sources     = [
            "0.0.0.0/0"
        ],
        rules       = [
            {
                protocol    = "TCP",
                ports       = ["22"]
            }
        ],
        target_tags = [
            "allow-ssh"
        ]
    },
    {
        id = "90101",
        project-ids = "mhanline-playpen002"
        name = "health-checks",
        network  = "net-a",
        description = "health checks for GCLB",
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
        id          = "90009",
        project-ids = "mhanline-playpen002",
        name        = "ssh-access-int-b",
        network     = "net-b",
        description = "SSH Ingress",
        action      = "allow",
        direction   = "INGRESS",
        log_config  = "DISABLED",
        priority    = 1004,
        sources     = [
            "0.0.0.0/0"
        ],
        rules       = [
            {
                protocol    = "TCP",
                ports       = ["22"]
            }
        ],
        target_tags = [
            "allow-ssh"
        ]
    },
    {
        id          = "90011",
        project-ids = "mhanline-playpen002",
        name        = "rfc1918-in-b",
        network     = "net-b",
        description = "RFC1918 Ingress",
        action      = "allow",
        direction   = "INGRESS",
        log_config  = "DISABLED",
        priority    = 1011,
        sources     = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12"
        ],
        rules       = [
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
    }
]

virtual_machines = [
    {
        name                = "testclient-producer"
        project-id          = "mhanline-playpen002"
        subnet              = "sub-b"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-11"
        private-ip          = "10.221.200.100"
        tags                = ["allow-ssh", "allow-rdp"]
        append-suffix-tag   = true
    }
]
