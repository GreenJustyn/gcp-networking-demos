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
project-id = "mhanline-playpen002"
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
        name        = "testvm-sin"
        region      = "asia-southeast1"
        subnet      = "sub-swp-demo-ase1"
        network     = "net-swp-demo"
    }
]

vpcs = [
    {
        network                 = "net-swp-demo"
        delete_default_route    = true
        subnets                 = [
           {
                subnet_name     = "sub-swp-demo-ase1"
                cidr_block      = "10.229.2.0/24"
                region          = "asia-southeast1"
            },
            {
                subnet_name     = "sub-swp-demo-proxy-ase1"
                cidr_block      = "10.229.0.0/23"
                region          = "asia-southeast1"
                purpose         = "REGIONAL_MANAGED_PROXY"
                role            = "ACTIVE"
            }
        ]
    }
]

fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in",
        network  = "net-swp-demo",
        description = "RFC1918 Ingress",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1001,
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
        name = "ssh-access-iap",
        network  = "net-swp-demo",
        description = "SSH Ingress from IAP Ranges",
        action = "allow",
        direction = "INGRESS",
        log_config = "DISABLED",
        priority = 1002,
        sources = [
            "35.235.240.0/20"
        ],
        rules = [
            {
                protocol = "TCP",
                ports = ["22"]
            }
        ],
        target_tags = [
            "allow-iap-ssh"
        ]
    }
]

psc_ips = [
    {
        network     = "net-swp-demo"
        name        = "psc"
        address     = "10.252.252.101"
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
        subnet  = "sub-swp-demo-ase1"
        ip      = ""
    }
]