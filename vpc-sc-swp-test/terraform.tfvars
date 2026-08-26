#Parent_id = Your org number
parent_id = "406355091074"
#List of project IDs to put in   the perimeter. At present it only takes the first one.
protected_project_ids = ["mhanline-playpen002"]
unprotected_project_ids = ["mhanline-playpen001"]
region = "australia-southeast1"
apis = [
  "compute.googleapis.com",
  "dns.googleapis.com",
  "oslogin.googleapis.com",
  "networkservices.googleapis.com",
  "networksecurity.googleapis.com",
  "accesscontextmanager.googleapis.com"
]
restricted_services = [
    "bigquery.googleapis.com",
    "storage.googleapis.com"
]
sa_project_roles = [
    "roles/iam.serviceAccountTokenCreator",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/iam.serviceAccountUser",
    "roles/compute.admin",
    "roles/compute.networkAdmin",
    "roles/certificatemanager.editor",
    "roles/compute.orgSecurityPolicyAdmin",
    "roles/resourcemanager.tagAdmin",
    "roles/privateca.admin"
]
vpcs = [
    {
        project-id              = "mhanline-playpen002"
        network                 = "vpc-inside"
        delete_default_route    = false
        subnets                 = [
           {
                subnet_name = "inside-ase1"
                cidr_block = "10.229.82.0/24"
                region = "australia-southeast1"
            },
            {
                subnet_name = "vpc-proxy-only"
                cidr_block  = "10.229.84.0/23"
                region      = "australia-southeast1"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            }
        ]
    },
    {
        project-id              = "mhanline-playpen001"
        network                 = "vpc-outside"
        delete_default_route    = false
        subnets                 = [
           {
                subnet_name = "outside-ase1"
                cidr_block = "10.230.82.0/24"
                region = "australia-southeast1"
            },
            {
                subnet_name = "vpc-proxy-only-out"
                cidr_block  = "10.230.84.0/23"
                region      = "australia-southeast1"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            }
        ]
    }
]
vms = [
    {
        name        = "testvm-inside"
        project     = "mhanline-playpen002"
        region      = "australia-southeast1"
        subnet      = "inside-ase1"
        network     = "vpc-inside"
        size        = "e2-micro"
    },
    {
        name        = "testvm-outside"
        project     = "mhanline-playpen001"
        region      = "australia-southeast1"
        subnet      = "outside-ase1"
        network     = "vpc-outside"
        size        = "e2-micro"
    }
]

psc_ips = [
    {
        network     = "inside-vpc"
        name        = "psc-inside"
        address     = "10.229.252.101"
    },
    {
        network     = "outside-vpc"
        name        = "psc-outside"
        address     = "10.230.252.101"
    }
]

fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in-int-inside",
        network  = "vpc-inside",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1001,
        project-id = "mhanline-playpen002"
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
        name = "rfc1918-in-int-isolated",
        network  = "vpc-outside",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
        project-id = "mhanline-playpen001"
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
        id = "90004",
        name = "iap-allow-inside",
        network  = "vpc-inside",
        description = "IAP SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1004,
        project-id = "mhanline-playpen002"
        source_list = [ "iap-forwarders" ]
        rules       = [
            {
                protocol    = "TCP",
                ports       = ["22"]
            }
        ]
    },
    {
        id = "90005",
        name = "iap-allow-outside",
        network  = "vpc-outside",
        description = "IAP SSH Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1005,
        project-id = "mhanline-playpen001"
        source_list = [ "iap-forwarders" ]
        rules       = [
            {
                protocol    = "TCP",
                ports       = ["22"]
            }
        ]
    }
]

virtual_machines = [
    {
        name                = "client-inside"
        project-id          = "mhanline-playpen002"
        subnet              = "inside-ase1"
        zone                = "australia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-11"
        tags                = ["allow-ssh", "allow-rdp"]
        append-suffix-tag   = true
    },
    {
        name                = "client-outside"
        project-id          = "mhanline-playpen001"
        subnet              = "outside-ase1"
        zone                = "australia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-11"
        tags                = ["allow-ssh", "allow-rdp"]
        append-suffix-tag   = true
    }
]

dns_rp_rules = [
    {
        name        = "googleapis-com-rule"
        psc-ip      = "psc"
        dns_name    = "*.googleapis.com."
    },
    {
        name        = "packagamanager-rule"
        psc-ip      = "psc"
        dns_name    = "packages.cloud.google.com."
    },
    {
        name        = "dl-google-com-rule"
        psc-ip      = "psc"
        dns_name    = "dl.google.com."
    }
]

peerings = [
    {
        network_a   = "vpc-outside"
        network_b   = "vpc-inside"
        peeringname = "outside-inside"
    }
]