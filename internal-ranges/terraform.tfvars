project-id = "mhanline-playpen002"
region = "asia-southeast1"
all_zones = false
apis = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "oslogin.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
]
vpcs = [
    {
        project-id              = "mhanline-playpen002"
        network                 = "vpc-primary"
        subnets     =  [
           {
                subnet_name = "sub-primary-asia"
                cidr_block = "10.229.65.0/24"
                region = "asia-southeast1"
            }
        ]
    },
    {
        network                 = "vpc-secondary"
        project-id              = "mhanline-playpen002"
        subnets   =  [
            {
                subnet_name = "sub-secondary-asia"
                cidr_block = "10.229.64.0/24"
                region = "asia-southeast1"
            },
            {
                subnet_name = "sub-secondary-us"
                cidr_block = "10.254.64.0/24"
                region = "us-central1"
            }
        ]
    }
]
