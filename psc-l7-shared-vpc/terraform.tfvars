project-id-hp = "mhanline-svpc-hp"
project-id-sp01 = "mhanline-svpc-sp02"
project-id-sp02 = "mhanline-svpc-sp01"
project-id-producer = "mhanline-playpen002"
region  = "asia-southeast1"
apis-hp    = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com"
]
apis-sp     = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com"
]
vpcs = [
    {
        network     = "net-shared"
        project-id  = "mhanline-svpc-hp"
        subnets     =  [
           {
                subnet_name = "sub-shared"
                cidr_block  = "10.221.100.0/23"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-shared-psc-proxy"
                cidr_block  = "10.221.104.0/23"
                region      = "asia-southeast1"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            },
            {
                subnet_name = "sub-consumer-lb"
                cidr_block  = "10.221.102.0/28"
                region      = "asia-southeast1"
            }
        ]
    },
    {
        network     = "net-producer"
        project-id  = "mhanline-playpen002"
        subnets     =  [
           {
                subnet_name = "sub-producer"
                cidr_block  = "10.221.200.0/23"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-producer-lb"
                cidr_block  = "10.221.202.0/28"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-producer-psc-nat"
                cidr_block  = "10.221.203.0/24"
                region      = "asia-southeast1"
                purpose     = "PRIVATE_SERVICE_CONNECT"
            },
            {
                subnet_name = "sub-producer-psc-proxy"
                cidr_block  = "10.221.204.0/23"
                region      = "asia-southeast1"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            }
        ]
    }
]

fw_rules = [
    {
        id          = "90001",
        project-ids = "mhanline-svpc-hp",
        name        = "rfc1918-in-int",
        network     = "net-shared",
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
        project-ids = "mhanline-svpc-hp",
        name        = "ssh-access-int",
        network     = "net-shared",
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
        network  = "net-producer",
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
        name        = "ssh-access-int",
        network     = "net-producer",
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
        name        = "rfc1918-in-int",
        network     = "net-producer",
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
        name                = "testclient-svcproject"
        subnet-project-id   = "mhanline-svpc-hp"
        project-id          = "mhanline-svpc-sp02"
        subnet              = "sub-shared"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-11"
        private-ip          = "10.221.100.100"
        tags                = ["allow-ssh", "allow-rdp"]
        append-suffix-tag   = true
    },
    {
        name                = "testclient-producer"
        project-id          = "mhanline-playpen002"
        subnet              = "sub-producer"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-11"
        private-ip          = "10.221.200.100"
        tags                = ["allow-ssh", "allow-rdp"]
        append-suffix-tag   = true
    }
]
