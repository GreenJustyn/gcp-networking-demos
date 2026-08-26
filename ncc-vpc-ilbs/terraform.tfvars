project-id = "mhanline-playpen002"
region = "asia-southeast1"
apis = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "oslogin.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
]
vpcs = [
    {
        project-id              = "mhanline-playpen002"
        network                 = "vpc-primary"
        subnets     =  [
           {
                subnet_name = "sub-primary-asia"
                cidr_block = "10.229.65.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        network                 = "vpc-secondary"
        project-id              = "mhanline-playpen002"
        subnets   =  [
            {
                subnet_name = "sub-secondary-asia"
                cidr_block = "10.229.64.0/24"
                region = "asia-southeast1"
            },
            {
                subnet_name = "sub-secondary-us"
                cidr_block = "10.254.64.0/24"
                region = "us-central1"
            }
        ]
    },
    {
        network                 = "vpc-tertiary"
        project-id              = "mhanline-playpen002"
        subnets   =  [
            {
                subnet_name = "sub-tertiary-asia"
                cidr_block = "10.229.63.0/24"
                region = "asia-southeast1"
            },
            {
                subnet_name = "sub-tertiary-us"
                cidr_block = "10.228.63.0/24"
                region = "us-central1"
                ncc_include_export  = true
            }
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        project-id = "mhanline-playpen002"
        name = "rfc1918-in-primary",
        network  = "vpc-primary",
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
        name = "rfc1918-in-secondary",
        project-id = "mhanline-playpen002"
        network  = "vpc-secondary",
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
        id = "90003",
        project-id = "mhanline-playpen002"
        name = "rfc1918-in-tertiary-asia",
        network  = "vpc-tertiary",
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
        id = "90004",
        name = "ssh-access-primary",
        project-id = "mhanline-playpen002"
        network  = "vpc-primary",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
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
        id = "90005",
        name = "ssh-access-secondary",
        project-id = "mhanline-playpen002"
        network  = "vpc-secondary",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
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
        name = "ssh-access-tertiary",
        project-id = "mhanline-playpen002"
        network  = "vpc-tertiary",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
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
        name            = "testclient-pri-vm"
        project-id      = "mhanline-playpen002"
        subnet          = "sub-primary-asia"
        zone            = "asia-southeast1-a"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-12"
        tags            = ["allow-ssh", "allow-rdp"]
        append-suffix-tag = true
    },
    {
        name            = "testclient-sec-vm1"
        project-id      = "mhanline-playpen002"
        subnet          = "sub-secondary-asia"
        zone            = "asia-southeast1-a"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-12"
        tags            = ["allow-ssh", "allow-rdp"]
        append-suffix-tag = true
    },
    {
        name            = "testclient-sec-vm2"
        project-id      = "mhanline-playpen002"
        subnet          = "sub-secondary-us"
        zone            = "us-central1-a"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-12"
        tags            = ["allow-ssh", "allow-rdp"]
        append-suffix-tag = true
    },
    {
        name            = "testclient-ter-vm"
        project-id      = "mhanline-playpen002"
        subnet          = "sub-tertiary-asia"
        zone            = "asia-southeast1-a"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-11"
        tags            = ["allow-ssh", "allow-rdp"]
        append-suffix-tag = true
    }
]