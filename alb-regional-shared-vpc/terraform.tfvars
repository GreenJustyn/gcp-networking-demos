project-id-hp = "mhanline-svpc-hp"
project-id-sp01 = "mhanline-svpc-sp01"
project-id-sp02 = "mhanline-svpc-sp02"
region  = "asia-southeast1"
apis    = [
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
        id          = "90002",
        project-ids = "mhanline-svpc-hp",
        name        = "ssh-access-int",
        network     = "net-shared",
        description = "SSH Ingress",
        action      = "allow",
        direction   = "INGRESS",
        log_config  = "DISABLED",
        priority    = 1002,
        sources     = [
            "0.0.0.0/0"
        ],
        rules       = [
            {
                protocol    = "TCP",
                ports       = ["22"]
            }
        ]
    },
    {
        id = "90003",
        project-ids = "mhanline-svpc-hp"
        name = "health-checks",
        network  = "net-shared",
        description = "health checks for GCLB",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
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

virtual_machines = [
    {
        name                = "testclient-svcproject"
        subnet-project-id   = "mhanline-svpc-hp"
        project-id          = "mhanline-svpc-sp01"
        subnet              = "sub-shared"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-11"
        private-ip          = "10.221.100.100"
        tags                = ["allow-ssh", "allow-rdp"]
        append-suffix-tag   = true
    }
]
