#Parent_id = Your org number
parent_id = "406355091074"
#List of project IDs to put in the perimeter. At present it only takes the first one.
protected_project_ids = ["dev-adapter-393314"]
unprotected_project_ids = ["winter-alliance-357101"]
vpc_sc_perimeters  = {
    perimeter1  = ["dev-adapter-393314"]
    #perimeter2  = ["winter-alliance-357101"]
}
region = "asia-southeast1"
apis = [
  "compute.googleapis.com",
  "dns.googleapis.com",
  "oslogin.googleapis.com",
  "accesscontextmanager.googleapis.com",
  "run.googleapis.com",
  "cloudresourcemanager.googleapis.com",
  "iam.googleapis.com"
]
protected_apis = [
    "bigquery.googleapis.com"
]
sa_project_roles = [
    "roles/iam.serviceAccountTokenCreator",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/iam.serviceAccountUser",
    "roles/compute.admin",
    "roles/compute.networkAdmin",
    "roles/storage.admin"
]
vpcs = [
    {
        project-id              = "dev-adapter-393314"
        network                 = "vpc1-in-perim1"
        subnets                 =  [
           {
                subnet_name = "sub-vpc1-in-perim1"
                cidr_block  = "10.221.100.0/23"
                region      = "asia-southeast1"
            }
        ]
    },
    {
        project-id              = "winter-alliance-357101"
        network                 = "vpc2-outside"
        subnets                 =  [
           {
                subnet_name = "sub-vpc2-outside"
                cidr_block  = "10.222.100.0/23"
                region      = "asia-southeast1"
            }
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in-int-vpc1",
        network  = "vpc1-in-perim1",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1001,
        project-id = "dev-adapter-393314"
        sources = [
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12"
        ],
        rules = [
            {
                protocol = "TCP"
            },
            {
                protocol = "UDP"
            },
            {
                protocol = "ICMP"
            }
        ]
    },
{
        id = "90003",
        name = "ssh-allow",
        network  = "vpc1-in-perim1",
        description = "SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
        project-id = "dev-adapter-393314"
        sources = [
            "0.0.0.0/0"
        ],
        rules = [
            {
                protocol = "TCP",
                ports       = ["22"]
            }
        ]
    }
]
vms = [
    {
        name        = "testvm-inside"
        project     = "dev-adapter-393314"
        region      = "asia-southeast1"
        subnet      = "sub-vpc1-in-perim1"
        network     = "vpc1-in-perim1"
        size        = "e2-micro"
    }
]