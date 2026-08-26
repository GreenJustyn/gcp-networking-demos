project-id = "mhanline-caap1"
region  = "asia-southeast1"
apis    = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com",
    "run.googleapis.com",
    "vpcaccess.googleapis.com"
]
vpcs = [
    {
        network     = "net-cloudrun"
        subnets     =  [
           {
                subnet_name = "sub-cloudrun"
                cidr_block  = "10.221.100.0/23"
                region      = "asia-southeast1"
            },
            {
                subnet_name = "sub-cloudrun-proxy"
                cidr_block  = "10.221.104.0/23"
                region      = "asia-southeast1"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            }
        ]
    }
]

ip_allow_list = ["192.0.2.0/24"]