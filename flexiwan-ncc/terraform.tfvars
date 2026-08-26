project-id = "mhanline-playpen002"
vpcs = [
    {
        network    =   "site1-vpc"
        subnets   =  [
           {
                subnet_name = "site1-subnet"
                cidr_block = "10.10.0.0/24"
                region = "us-central1"
            },
            {
                subnet_name = "site1-subnet2"
                cidr_block = "10.10.99.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        network    =   "site2-vpc"
        subnets   =  [
            {
                subnet_name = "site2-subnet"
                cidr_block = "10.20.0.0/24"
                region = "us-east4"
            }
        ]
    },
    {
        network    =   "s1-inside-vpc"
        subnets   =  [
            {
                subnet_name = "s1-inside-subnet"
                cidr_block = "10.10.1.0/24"
                region = "us-central1"
            }
        ]
    },
    {
        network    =   "s2-inside-vpc"
        subnets   =  [
            {
                subnet_name = "s2-inside-subnet"
                cidr_block = "10.20.1.0/24"
                region = "us-east4"
            }
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        name = "site1-cloud",
        network  = "site1-vpc",
        description = "Allow RFC1918 Ingress",
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
            }
        ]
    },
    {
        id = "90002",
        name = "site1-vpn",
        network  = "site1-vpc",
        description = "IPSEC Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
        sources = [
            "0.0.0.0/0"
        ],
        target_tags = [
            "router"
        ],
        rules = [
            {
                protocol = "esp"
            },
            {
                protocol = "udp",
                ports = ["500"]
            },
            {
                protocol = "udp",
                ports = ["4500"]
            }
        ]
    },
    {
        id = "90003",
        name = "site1-iap",
        network  = "site1-vpc",
        description = "IAP SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
        sources = [
            "35.235.240.0/20"
        ],
        rules = [
            {
                protocol = "TCP",
                ports = ["22"]
            }
        ]
    },
    {
        id = "91001",
        name = "site2-cloud",
        network  = "site2-vpc",
        description = "Allow RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1101,
        sources = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12"
        ],
        rules = [
            {
                protocol = "TCP"
            }
        ]
    },
    {
        id = "91002",
        name = "site2-vpn",
        network  = "site2-vpc",
        description = "IPSEC Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1102,
        sources = [
            "0.0.0.0/0"
        ],
        target_tags = [
            "router"
        ]
        rules = [
            {
                protocol = "esp"
            },
            {
                protocol = "udp",
                ports = ["500"]
            },
            {
                protocol = "udp",
                ports = ["4500"]
            }
        ]
    },
    {
        id = "91003",
        name = "site2-iap",
        network  = "site2-vpc",
        description = "IAP SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1103,
        sources = [
            "35.235.240.0/20"
        ],
        rules = [
            {
                protocol = "TCP",
                ports = ["22"]
            }
        ]
    },
    {
        id = "92001",
        name = "s1-inside-internal",
        network  = "s1-inside-vpc",
        description = "Allow RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1101,
        sources = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12"
        ],
        rules = [
            {
                protocol = "TCP"
            }
        ]
    },
    {
        id = "92003",
        name = "s1-inside-iap",
        network  = "s1-inside-vpc",
        description = "IAP SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1203,
        sources = [
            "35.235.240.0/20"
        ],
        rules = [
            {
                protocol = "TCP",
                ports = ["22"]
            }
        ]
    },
    {
        id = "93001",
        name = "s2-inside-internal",
        network  = "s2-inside-vpc",
        description = "Allow RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1301,
        sources = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12"
        ],
        rules = [
            {
                protocol = "TCP"
            }
        ]
    },
    {
        id = "93003",
        name = "s2-inside-iap",
        network  = "s2-inside-vpc",
        description = "IAP SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1303,
        sources = [
            "35.235.240.0/20"
        ],
        rules = [
            {
                protocol = "TCP",
                ports = ["22"]
            }
        ]
    }
]


virtual_machines = [
    {
        name            = "workload1-vm"
        #network         = "site1-vpc"
        subnet          = "workload-subnet1"
        zone            = "us-central1-a"
        external_ip     = "NONE"
        # Types "NONE|EPHEMERAL|EXT_REF"
        #description    = ""
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-10"
        private-ip      = "192.168.235.3"
        startup-script = <<SCRIPT
            #! /bin/bash
            apt-get update
            apt-get install apache2 -y
            service apache2 restart
            echo 'Welcome to Workload VM1 !!' | tee /var/www/html/index.html
        SCRIPT
        #can_ip_forward  = true
    }
]