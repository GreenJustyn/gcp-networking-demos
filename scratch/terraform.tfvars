project-id  = "mhanline-playpen002"
vpcs = [
    {
        network                 = "vpc-hub"
        delete_default_route    = false
        subnets                 = [
           {
                subnet_name = "hubsub-usc1"
                cidr_block = "10.10.0.0/22"
                region = "us-central1"
            },
            {
                subnet_name = "wooosh"
                cidr_block = "10.122.0.0/22"
                region= "asia-southeast1"
            }
        ]
    },
    {
        network                 = "vpc-isolated"
        subnets                 =  [
           {
                subnet_name = "isolated-usc1"
                cidr_block = "10.20.0.0/22"
                region = "us-central1"
            }
        ]
    },
    {
        network                 = "vpc-onprem"
        delete_default_route    = true
        subnets                 =  [
           {
                subnet_name = "onprem-usc1"
                cidr_block = "10.30.0.0/22"
                region = "us-central1"
            }
        ]
    },
    {
        network                 = "vpc-auto"
        auto_create_subnets     = true
    }
]


fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in-vpc-hub",
        network  = "vpc-hub",
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
        id = "90005",
        name = "ssh-access-vpc-hub",
        network  = "vpc-hub",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1003,
        source_list = [ "iap-forwarders" ],
        sources = [
            "192.168.0.0/16",
            "10.0.0.0/8"
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
        id = "90101",
        name = "health-checks-vpc-hub",
        network  = "vpc-hub",
        description = "health checks for ILB",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1101,
        source_list = [ "health-checkers", "legacy-health-checkers", "private-googleapis" ]
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
        name            = "testclient-pri-vm1"
        project-id      = "mhanline-playpen002"
        subnet          = "hubsub-usc1"
        region          = "us-central1"
        image           = "debian-cloud/debian-11"
        tags            = ["allow-ssh", "allow-rdp"]
        script          = "./debian-11-client.sh.tftpl"
        append-suffix-tag = true
    },
    {
        name            = "testclient-pri-vm2"
        subnet          = "isolated-usc1"
        zone            = "us-central1-a"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-11"
        tags            = ["allow-ssh", "allow-rdp"]
        script          = "./debian-11-client.sh.tftpl"
        append-suffix-tag = true
    }
]