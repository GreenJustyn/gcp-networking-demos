project-id = "mhanline-playpen002"
apis = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com",
    "recaptchaenterprise.googleapis.com"
]
regions = [ "asia-southeast1" ]

routes = [
]

vpcs = [
    {
        network                 = "net-http-lb"
        subnets                 = [
           {
                subnet_name     = "sub-http-lb"
                cidr_block      = "10.229.65.0/24"
                region          = "asia-southeast1"
            }
        ]
    }
]
all_zones = true