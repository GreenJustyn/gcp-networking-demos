project-id = "mhanline-playpen001"
regions = [ "asia-southeast1" ]
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
                subnet_name = "sub-lb"
                cidr_block  = "10.221.102.0/28"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-producer-psc-nat"
                cidr_block  = "10.221.203.0/24"
                region      = "asia-southeast1"
                purpose     = "PRIVATE_SERVICE_CONNECT"
            }
        ]
    },
    {
        network     = "psc-consumer"
        subnets     =  [
           {
                subnet_name = "sub-consumer"
                cidr_block  = "10.230.100.0/23"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-consumer-lb"
                cidr_block  = "10.230.102.0/28"
                region      = "asia-southeast1"
            }
        ]
    }
]

virtual_machines = [
    {
        name                = "testclient"
        subnet              = "sub-lbtest"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-11"
        private-ip          = "10.221.100.100"
        tags                = ["allow-ssh"]
        append-suffix-tag   = true
    },
    {
        name                = "testclient-cons"
        subnet              = "sub-consumer"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-12"
        append-suffix-tag   = true
    }
]

all_zones = true
