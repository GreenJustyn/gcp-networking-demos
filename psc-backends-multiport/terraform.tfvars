#Copyright 2024 Google LLC.
#SPDX-License-Identifier: Apache-2.0
project-id-consumer = "mhanline-ncc-02"
project-id-producer = "mhanline-ncc-02"
region  = "asia-southeast1"
apis    = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com"
]
vpcs = [
    {
        network     = "net-consumer"
        project-id  = "mhanline-ncc-02"
        subnets     =  [
           {
                subnet_name = "sub-consumer"
                cidr_block  = "10.221.100.0/23"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-consumer-psc-proxy"
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
        project-id  = "mhanline-ncc-02"
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
                subnet_name = "sub-producer-psc-nat01"
                cidr_block  = "10.221.203.0/26"
                region      = "asia-southeast1"
                purpose     = "PRIVATE_SERVICE_CONNECT"
            },
            {
                subnet_name = "sub-producer-psc-nat02"
                cidr_block  = "10.221.203.64/26"
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
/*
fw_rules = [
    {
        id          = "90001",
        project-ids = "mhanline-playpen002",
        name        = "rfc1918-in-consumer",
        network     = "net-consumer",
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
        name        = "ssh-access-consumer",
        network     = "net-consumer",
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
        log_config = "ENABLED",
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
        name        = "ssh-access-producer",
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
        name        = "rfc1918-in-producer",
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
*/
virtual_machines = [
    {
        name                = "testclient-consumer"
        project-id          = "mhanline-ncc-02"
        subnet              = "sub-consumer"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-12"
        script              = "debian-client.sh.tftpl"
        external-ipv4       = false
    },
    {
        name                = "testclient-producer"
        project-id          = "mhanline-ncc-02"
        subnet              = "sub-producer"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-12"
        script              = "debian-client.sh.tftpl"
        external-ipv4       = false
    }
]
