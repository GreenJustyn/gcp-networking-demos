#Copyright 2025 Google LLC.
#SPDX-License-Identifier: Apache-2.0
project-id-consumer = "mhanline-playpen001"
project-id-producer = "mhanline-playpen002"
regions  = [ "us-central1", "us-east4" ]
apis    = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com",
    "run.googleapis.com"
]
vpcs = [
    {
        network     = "net-consumer"
        project-id  = "mhanline-playpen001"
        subnets     =  [
           {
                subnet_name = "sub-consumer-usc1"
                cidr_block  = "10.221.100.0/23"
                region      = "us-central1"
            },
            {
                subnet_name = "sub-consumer-usc1-proxy"
                cidr_block  = "10.221.104.0/23"
                region      = "us-central1"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            },
            {
                subnet_name = "sub-consumer-use4"
                cidr_block  = "10.221.200.0/28"
                region      = "us-east4"
            },
            {
                subnet_name = "sub-consumer-use4-proxy"
                cidr_block  = "10.221.204.0/23"
                region      = "us-east4"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            }
        ]
    },
    {
        network     = "net-producer"
        project-id  = "mhanline-playpen002"
        subnets     =  [
           {
                subnet_name = "sub-producer-usc1"
                cidr_block  = "10.121.100.0/23"
                region      = "us-central1"
            },
            {
                subnet_name = "sub-producer-usc1-proxy"
                cidr_block  = "10.121.104.0/23"
                region      = "us-central1"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            },
            {
                subnet_name = "sub-producer-usc1-nat"
                cidr_block  = "10.121.108.0/23"
                region      = "us-central1"
                purpose     = "PRIVATE_SERVICE_CONNECT"
            },
            {
                subnet_name = "sub-producer-usc1-extproxy"
                cidr_block  = "10.121.112.0/23"
                region      = "us-central1"
                purpose     = "GLOBAL_MANAGED_PROXY"
                role        = "ACTIVE"
            },
            {
                subnet_name = "sub-producer-use4"
                cidr_block  = "10.121.200.0/23"
                region      = "us-east4"
            },
            {
                subnet_name = "sub-producer-use4-proxy"
                cidr_block  = "10.121.204.0/23"
                region      = "us-east4"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            },
            {
                subnet_name = "sub-producer-use4-nat"
                cidr_block  = "10.121.208.0/23"
                region      = "us-east4"
                purpose     = "PRIVATE_SERVICE_CONNECT"
            },
            {
                subnet_name = "sub-producer-use4-globalproxy"
                cidr_block  = "10.121.212.0/23"
                region      = "us-east4"
                purpose     = "GLOBAL_MANAGED_PROXY"
                role        = "ACTIVE"
            }
        ]
    }
]

virtual_machines = [
    {
        name                = "testclient-consumer-usc1"
        project-id          = "mhanline-playpen001"
        subnet              = "sub-consumer-usc1"
        zone                = "us-central1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-12"
        script = "debian.sh.tftpl"
    },
    {
        name                = "testclient-producer-usc1"
        project-id          = "mhanline-playpen002"
        subnet              = "sub-producer-usc1"
        zone                = "us-central1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-12"
        script = "debian.sh.tftpl"
    },
    {
        name                = "testclient-consumer-use4"
        project-id          = "mhanline-playpen001"
        subnet              = "sub-consumer-use4"
        zone                = "us-east4-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-12"
        script = "debian.sh.tftpl"
    },
    {
        name                = "testclient-producer-use4"
        project-id          = "mhanline-playpen002"
        subnet              = "sub-producer-use4"
        zone                = "us-east4-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-12"
        script = "debian.sh.tftpl"
    }
]
