#Parent_id = Your org number
parent_id = "406355091074"
#List of project IDs to put in the perimeter. At present it only takes the first one.
project-ids = ["dev-adapter-393314", "winter-alliance-357101"]
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
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "run.googleapis.com"
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
        network                 = "vpc2-in-perim1"
        subnets                 =  [
           {
                subnet_name = "sub-vpc2-in-perim1"
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
        id = "90002",
        name = "rfc1918-in-int-spoke1",
        network  = "vpc2-in-perim1",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1001,
        project-id = "winter-alliance-357101"
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
    },
    {
        id          = "90004",
        name        = "ssh-allow",
        network     = "vpc2-in-perim1",
        description = "SSH Ingress",
        action      = "allow",
        direction   = "INGRESS",
        log_config  = "DISABLED",
        priority    = 1002,
        project-id  = "winter-alliance-357101"
        sources     = [
            "0.0.0.0/0"
        ],
        rules = [
            {
                protocol    = "TCP",
                ports       = ["22"]
            }
        ]
    }
]

virtual_machines = [
    {
        project-id      = "dev-adapter-393314"
        name            = "testvm-vpc1"
        zone            = "asia-southeast1-b"
        subnet          = "sub-vpc1-in-perim1"
        network         = "vpc1-in-perim1"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-11"
    },
    {
        project-id      = "winter-alliance-357101"
        name            = "testvm-vpc2"
        zone            = "asia-southeast1-b"
        subnet          = "sub-vpc2-in-perim1"
        network         = "vpc2-in-perim1"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-11"
    }
]