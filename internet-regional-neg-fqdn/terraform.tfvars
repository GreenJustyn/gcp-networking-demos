project-id = "mhanline-playpen002"
apis = [
  "compute.googleapis.com",
  "dns.googleapis.com",
  "oslogin.googleapis.com"
]
regions = [ "asia-southeast1" ]
ip_address_internal1 = "10.229.65.199"
ip_address_internal2 = "10.229.66.199"
routes = [
]

vpcs = [
    {
        network                 = "hybrid-test-vpc"
        subnets                 = [
           {
                subnet_name     = "hybrid-test-sub-sin"
                cidr_block      = "10.229.65.0/24"
                region          = "asia-southeast1"
            },
            {
                subnet_name     = "hybrid-test-sub-sin-proxy"
                cidr_block      = "10.229.0.0/22"
                region          = "asia-southeast1"
                purpose         = "REGIONAL_MANAGED_PROXY"
                role            = "ACTIVE"
            }
        ]
    },
    {
        network                 = "producer-vpc"
        subnets                 = [
           {
                subnet_name     = "producer-subsin"
                cidr_block      = "10.202.65.0/24"
                region          = "asia-southeast1"
            }
        ]
    }
]

