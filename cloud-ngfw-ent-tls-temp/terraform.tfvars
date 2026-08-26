project-id  = "mhanline-playpen002"
org-id      = "406355091074"
region      = "asia-southeast1"
all_zones   = true
apis = [
  "compute.googleapis.com",
  "networksecurity.googleapis.com",
  "certificatemanager.googleapis.com",
  "networkservices.googleapis.com",
  "privateca.googleapis.com"
]
vpcs = [
    {
        project-id              = "mhanline-playpen002"
        network                 = "fw-vpc"
        subnets                 = [
           {
                subnet_name = "fwase1"
                cidr_block = "10.38.102.0/23"
                region = "asia-southeast1"
            },
            {
                subnet_name = "fwase1-1"
                cidr_block = "10.38.104.0/23"
                region = "asia-southeast1"
            }
        ]
    },
    {
        project-id              = "mhanline-playpen001"
        network                 = "ext-vpc"
        subnets                 = [
           {
                subnet_name = "ext-subnet-ase1"
                cidr_block = "10.40.102.0/23"
                region = "asia-southeast1"
            }
        ]
    }
]
