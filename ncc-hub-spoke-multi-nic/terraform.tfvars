project-id = "mhanline-playpen002"
region = "us-central1"
regions = [ "us-central1", "us-west1" ]
cr_base_asn = 64515
apis = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com",
    "networkconnectivity.googleapis.com"
]
vpn_ips = ["169.254.0.0/30", "169.254.1.0/30", "169.254.2.0/30", "169.254.3.0/30"]
vpcs = [
    {
        network    =   "vpc-internal"
        subnets   =  [
           {
                subnet_name = "vpc-internal-subnet"
                cidr_block = "10.229.65.0/24"
                region = "us-central1"
            },
           {
                subnet_name = "vpc-internal-subnet-usw"
                cidr_block = "10.230.65.0/24"
                region = "us-west1"
            }
        ]
    },
    {
        network    =   "vpc-external"
        subnets   =  [
            {
                subnet_name = "vpc-external-subnet"
                cidr_block = "10.229.66.0/24"
                region = "us-central1"
            },
            {
                subnet_name = "vpc-external-subnet-usw"
                cidr_block = "10.230.66.0/24"
                region = "us-west1"
            }
        ]
    },
    {
        network    =   "vpc-remote"
        subnets   =  [
            {
                subnet_name = "vpc-remote-subnet"
                cidr_block = "10.229.67.0/24"
                region = "us-central1"
            },
            {
                subnet_name = "vpc-remote-subnet-usw"
                cidr_block = "10.230.67.0/24"
                region = "us-west1"
            }
        ]
    },
    {
        network    =   "vpc-peered"
        subnets   =  [
            {
                subnet_name = "vpc-peered-subnet"
                cidr_block = "10.229.64.0/24"
                region = "us-central1"
            },
            {
                subnet_name = "vpc-peered-subnet-usw"
                cidr_block = "10.230.64.0/24"
                region = "us-west1"
            },
            {
                subnet_name = "vpc-peered-subnet-usc1-pupi"
                cidr_block = "11.229.64.0/24"
                region = "us-central1"
            }
        ]
    }
]

peerings = [
    {
        network_a   = "vpc-peered"
        network_b   = "vpc-internal"
        peeringname = "peering"
    }
]

virtual_machines = [
    {
        name            = "testclient-int-vm-usc1"
        subnet          = "vpc-internal-subnet"
        region          = "us-central1"
    },
    {
        name            = "testclient-ext-vm-usc1"
        subnet          = "vpc-external-subnet"
        region          = "us-central1"
    },
    {
        name            = "testclient-remote-vm-usc1"
        subnet          = "vpc-remote-subnet"
        region          = "us-central1"
    },
    {
        name            = "testclient-peered-vm-usc1"
        subnet          = "vpc-peered-subnet-usc1-pupi"
        region          = "us-central1"
    },
    {
        name            = "testclient-int-vm-usw1"
        subnet          = "vpc-internal-subnet-usw"
        region          = "us-west1"
    },
    {
        name            = "testclient-ext-vm-usw1"
        subnet          = "vpc-external-subnet-usw"
        region          = "us-west1"
    },
    {
        name            = "testclient-remote-vm-usw1"
        subnet          = "vpc-remote-subnet-usw"
        region          = "us-west1"
    },
    {
        name            = "testclient-peered-vm-usw1"
        subnet          = "vpc-peered-subnet-usw"
        region          = "us-west1"
    }
]