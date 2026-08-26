project-id = "mhanline-playpen001"
apis = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com"
]
regions = [ "asia-southeast1" ]

routes = [
]

vpcs = [
    {
        network                 = "net-vpc"
        #delete_default_route    = true
        subnets                 = [
           {
                subnet_name     = "sub-vpc-sin"
                cidr_block      = "10.229.65.0/24"
                region          = "asia-southeast1"
            }
        ]
    }
]

psc_ips = [
    {
        network     = "net-vpc"
        name        = "psc"
        address     = "10.252.252.101"
    }
]

virtual_machines = [
    {
        name            = "testvm-sin01"
        project-id      = "mhanline-playpen001"
        subnet          = "sub-vpc-sin"
        region          = "asia-southeast1"
        image           = "debian-cloud/debian-12"
        scopes          = ["compute-ro", "storage-ro"]
        tags            = ["allow-ssh"]
        script          = "./debian-client.sh.tftpl"
    },
    {
        name            = "testvm-sin02"
        project-id      = "mhanline-playpen001"
        subnet          = "sub-vpc-sin"
        region          = "asia-southeast1"
        image           = "debian-cloud/debian-12"
        scopes          = ["compute-ro", "storage-ro"]
        tags            = ["allow-ssh"]
        script          = "./debian-client.sh.tftpl"
    }
]