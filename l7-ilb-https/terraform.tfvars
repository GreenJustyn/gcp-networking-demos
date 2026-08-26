project-id = "mhanline-playpen001"
region  = "asia-southeast1"
apis    = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com"
]
vpcs = [
    {
        network     = "net-lbtest"
        subnets     =  [
           {
                subnet_name = "sub-lbtest"
                cidr_block  = "10.221.100.0/23"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-lbtest-proxy"
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
        name        = "rfc1918-in-int",
        network     = "net-lbtest",
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
        name        = "ssh-access-int",
        network     = "net-lbtest",
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
        name = "health-checks",
        network  = "net-lbtest",
        description = "health checks for LB",
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

virtual_machines = [
    {
        name                = "testclient"
        subnet              = "sub-lbtest"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-12"
        cidrhostnum         = 150
        tags                = ["allow-ssh"]
        append-suffix-tag   = true
    }
]
