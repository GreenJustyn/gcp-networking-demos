project-id  = "mhanline-playpen002"
org-id      = "406355091074"
region      = "us-central1"
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
        delete_default_route    = false
        subnets                 = [
           {
                subnet_name = "fwusc1"
                cidr_block = "10.38.102.0/23"
                region = "us-central1"
            }
        ]
    }
]
