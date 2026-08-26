project-id  = "mhanline-playpen002"
org-id      = "406355091074"
region      = "asia-southeast1"
apis = [
  "compute.googleapis.com",
  "networksecurity.googleapis.com"
]
vpcs = [
    {
        project-id              = "mhanline-playpen002"
        network                 = "fw-vpc"
        delete_default_route    = false
        subnets                 = [
           {
                subnet_name = "fwusc1"
                cidr_block = "10.98.174.0/23"
                region = "asia-southeast1"
            }
        ]
    }
]
all_zones = true