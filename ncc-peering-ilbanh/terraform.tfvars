project-id = "mhanline-playpen002"
region = "australia-southeast1"
apis = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com",
    "networkconnectivity.googleapis.com"
]
vpcs = [
    {
        project-id              = "mhanline-playpen001"
        network                 = "vpc-external"
        delete_default_route    = true
        subnets     =  [
           {
                subnet_name = "vpc-external-subnet"
                cidr_block = "10.229.65.0/24"
                region = "australia-southeast1"
            }
        ]
    },
    {
        network                 = "vpc-internal"
        project-id              = "mhanline-playpen002"
        delete_default_route    = true
        subnets   =  [
            {
                subnet_name = "vpc-internal-subnet"
                cidr_block = "10.229.64.0/24"
                region = "australia-southeast1"
            }
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        project-id = "mhanline-playpen002"
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
        project-id = "mhanline-playpen001"
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
        name = "ssh-access-ext",
        project-id = "mhanline-playpen001"
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
        name = "ssh-access-int",
        project-id = "mhanline-playpen002"
        network  = "vpc-internal",
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
    }
]

virtual_machines = [
    {
        name            = "testclient-int-vm"
        project-id      = "mhanline-playpen002"
        subnet          = "vpc-internal-subnet"
        zone            = "australia-southeast1-a"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-11"
        private-ip      = "10.229.64.25"
        tags            = ["allow-ssh", "allow-rdp"]
        append-suffix-tag = true
    },
    {
        name            = "testclient-ext-vm"
        project-id      = "mhanline-playpen001"
        subnet          = "vpc-external-subnet"
        zone            = "australia-southeast1-a"
        machine-type    = "e2-micro"
        private-ip      = "10.229.65.25"
        image           = "debian-cloud/debian-11"
        tags            = ["allow-ssh", "allow-rdp"]
        append-suffix-tag = true
    }
]