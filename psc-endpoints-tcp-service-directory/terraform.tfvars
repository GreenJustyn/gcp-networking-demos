#Copyright 2025 Google LLC.
#SPDX-License-Identifier: Apache-2.0
project-id-consumer01 = "mhanline-playpen001"
project-id-consumer02 = "mhanline-playpen002"
project-id-producer = "mhanline-cdn01"
region  = "asia-southeast1"
apis    = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com"
]
vpcs = [
    {
        network     = "net-consumer01"
        project-id  = "mhanline-playpen001"
        subnets     =  [
           {
                subnet_name = "sub-consumer01"
                cidr_block  = "10.121.100.0/23"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-consume01-psc-proxy"
                cidr_block  = "10.121.104.0/23"
                region      = "asia-southeast1"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            },
            {
                subnet_name = "sub-consumer01-lb"
                cidr_block  = "10.121.102.0/28"
                region      = "asia-southeast1"
            }
        ]
    },
    {
        network     = "net-consumer02"
        project-id  = "mhanline-playpen002"
        subnets     =  [
           {
                subnet_name = "sub-consumer02"
                cidr_block  = "10.221.100.0/23"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-consumer02-psc-proxy"
                cidr_block  = "10.221.104.0/23"
                region      = "asia-southeast1"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            },
            {
                subnet_name = "sub-consumer02-lb"
                cidr_block  = "10.221.102.0/28"
                region      = "asia-southeast1"
            }
        ]
    },
    {
        network     = "net-producer"
        project-id  = "mhanline-cdn01"
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
virtual_machines = [
    {
        name                = "testclient-consumer01"
        project-id          = "mhanline-playpen001"
        subnet              = "sub-consumer01"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-12"
        script              = "debian-client.sh.tftpl"
        external-ipv4       = false
    },
    {
        name                = "testclient-consumer02"
        project-id          = "mhanline-playpen002"
        subnet              = "sub-consumer02"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-12"
        script              = "debian-client.sh.tftpl"
        external-ipv4       = false
    },
    {
        name                = "testclient-producer"
        project-id          = "mhanline-cdn01"
        subnet              = "sub-producer"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-12"
        script              = "debian-client.sh.tftpl"
        external-ipv4       = false
    }
]
