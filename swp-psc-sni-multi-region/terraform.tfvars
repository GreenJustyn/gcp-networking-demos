#Copyright ${YEAR} Google LLC
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

project-id-consumer = "mhanline-playpen001"
project-id-producer = "mhanline-playpen002"

apis = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "oslogin.googleapis.com",
    "certificatemanager.googleapis.com",
    "privateca.googleapis.com",
    "networksecurity.googleapis.com",
    "networkservices.googleapis.com"
]
vms = [
    {
        name        = "producervm-sin"
        region      = "asia-southeast1"
        subnet      = "sub-swp-producer-ase1"
        network     = "net-swp-producer"
    },
    {
        name        = "consumervm-sin"
        region      = "asia-southeast1"
        subnet      = "sub-swp-consumer-ase1"
        network     = "net-swp-consumer"
    }
]

vpcs = [
    {
        network                 = "net-swp-producer"
        project-id              = "mhanline-playpen002"
        delete_default_route    = false
        subnets                 = [
           {
                subnet_name     = "sub-swp-producer-ase1"
                cidr_block      = "10.229.2.0/24"
                region          = "asia-southeast1"
            },
            {
                subnet_name     = "sub-swp-proxy-ase1"
                cidr_block      = "10.229.0.0/23"
                region          = "asia-southeast1"
                purpose         = "REGIONAL_MANAGED_PROXY"
                role            = "ACTIVE"
            },
            {
                subnet_name     = "sub-producer-psc-ase1"
                cidr_block      = "10.229.3.0/24"
                region          = "asia-southeast1"
                purpose         = "PRIVATE_SERVICE_CONNECT"
                role            = "ACTIVE"
            },
            {
                subnet_name     = "sub-swp-producer-usc1"
                cidr_block      = "10.230.2.0/24"
                region          = "us-central1"
            },
            {
                subnet_name     = "sub-swp-proxy-usc1"
                cidr_block      = "10.230.0.0/23"
                region          = "us-central1"
                purpose         = "REGIONAL_MANAGED_PROXY"
                role            = "ACTIVE"
            },
            {
                subnet_name     = "sub-producer-psc-usc1"
                cidr_block      = "10.230.3.0/24"
                region          = "us-central1"
                purpose         = "PRIVATE_SERVICE_CONNECT"
                role            = "ACTIVE"
            }
        ]
    },
    {
        network                 = "net-swp-consumer"
        project-id              = "mhanline-playpen001"
        delete_default_route    = true
        subnets                 = [
           {
                subnet_name     = "sub-swp-consumer-ase1"
                cidr_block      = "10.129.2.0/24"
                region          = "asia-southeast1"
            },
            {
                subnet_name     = "sub-swp-consumer-usc1"
                cidr_block      = "10.130.2.0/24"
                region          = "us-central1"
            }
        ]
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
    },
]

swp_domainname = "swpdemo.internal"

swp_locations   = [
    {
        subnet  = "sub-swp-producer-ase1"
        ip      = ""
    }
]