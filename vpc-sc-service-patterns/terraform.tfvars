#Parent_id = Your org number
parent_id = "406355091074"
#List of project IDs to put in  the perimeter. At present it only takes the first one.
protected_project_ids = ["ghjkl-20630"]
unprotected_project_ids = ["qwerty-20630"]
region = "asia-southeast1"
apis = [
  "iam.googleapis.com",
  "compute.googleapis.com",
  "cloudresourcemanager.googleapis.com",
  "dns.googleapis.com",
  "oslogin.googleapis.com",
  "networkservices.googleapis.com",
  "networksecurity.googleapis.com",
  "accesscontextmanager.googleapis.com",
  "discoveryengine.googleapis.com"
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
    "roles/compute.orgSecurityPolicyAdmin",
    "roles/resourcemanager.tagAdmin",
    "roles/storage.admin",
    "roles/dns.admin"
]
vpcs = [
    {
        project-id              = "ghjkl-20630"
        network                 = "vpc-inside"
        delete_default_route    = false
        subnets                 = [
           {
                subnet_name = "inside-ase1"
                cidr_block = "10.229.82.0/24"
                region = "asia-southeast1"
            },
            {
                subnet_name = "vpc-proxy-only"
                cidr_block  = "10.229.84.0/23"
                region      = "asia-southeast1"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            }
        ]
    },
    {
        project-id              = "qwerty-20630"
        network                 = "vpc-outside"
        delete_default_route    = false
        subnets                 = [
           {
                subnet_name = "outside-ase1"
                cidr_block = "10.230.82.0/24"
                region = "asia-southeast1"
            },
            {
                subnet_name = "vpc-proxy-only-out"
                cidr_block  = "10.230.84.0/23"
                region      = "asia-southeast1"
                purpose     = "REGIONAL_MANAGED_PROXY"
                role        = "ACTIVE"
            }
        ]
    }
]
vms = [
    {
        name        = "testvm-inside"
        project     = "ghjkl-20630"
        region      = "asia-southeast1"
        subnet      = "inside-ase1"
        network     = "vpc-inside"
        size        = "e2-micro"
    },
    {
        name        = "testvm-outside"
        project     = "qwerty-20630"
        region      = "asia-southeast1"
        subnet      = "outside-ase1"
        network     = "vpc-outside"
        size        = "e2-micro"
    }
]

virtual_machines = [
    {
        name                = "client-inside"
        project-id          = "ghjkl-20630"
        subnet              = "inside-ase1"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-11"
        tags                = ["allow-ssh", "allow-rdp"]
        append-suffix-tag   = true
    },
    {
        name                = "client-outside"
        project-id          = "qwerty-20630"
        subnet              = "outside-ase1"
        zone                = "asia-southeast1-a"
        machine-type        = "e2-micro"
        image               = "debian-cloud/debian-11"
        tags                = ["allow-ssh", "allow-rdp"]
        append-suffix-tag   = true
    }
]

dns_rp_rules = [
    {
        name        = "googleapis-com-rule"
        dns_name    = "*.googleapis.com."
    },
    {
        name        = "packagamanager-rule"
        dns_name    = "packages.cloud.google.com."
    },
    {
        name        = "dl-google-com-rule"
        dns_name    = "dl.google.com."
    }
]