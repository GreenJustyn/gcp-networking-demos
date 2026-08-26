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
        network                 = "producer-vpc"
        subnets                 = [
           {
                subnet_name     = "producer-sub-sin"
                cidr_block      = "10.229.65.0/24"
                region          = "asia-southeast1"
            },
            {
                subnet_name     = "producer-sub-sin-proxy"
                cidr_block      = "10.229.0.0/22"
                region          = "asia-southeast1"
                purpose         = "REGIONAL_MANAGED_PROXY"
                role            = "ACTIVE"
            },
            {
                subnet_name = "sub-producer-psc-nat"
                cidr_block  = "10.229.4.0/24"
                region      = "asia-southeast1"
                purpose     = "PRIVATE_SERVICE_CONNECT"
            }
        ]
    },
    {
        network                 = "consumer-vpc"
        subnets                 = [
           {
                subnet_name     = "consumer-sub-sin"
                cidr_block      = "10.19.19.0/24"
                region          = "asia-southeast1"
            }
        ]
    }
]

