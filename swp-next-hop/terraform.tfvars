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

project-id = "poetic-bulwark-419102"
apis = [
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
        name            = "vm01-sin"
        region          = "asia-southeast1"
        subnet          = "sub-swp-ase1"
        network         = "net-swp"
        external-ipv4   = false
        tags            = ["swp-asia-southeast1"]
    }
]

vpcs = [
    {
        network                 = "net-swp"
        project-id              = "poetic-bulwark-419102"
        delete_default_route    = false
        subnets                 = [
           {
                subnet_name     = "sub-swp-ase1"
                cidr_block      = "10.229.2.0/24"
                region          = "asia-southeast1"
            },
            {
                subnet_name     = "sub-swp-proxy-ase1"
                cidr_block      = "10.229.0.0/23"
                region          = "asia-southeast1"
                purpose         = "REGIONAL_MANAGED_PROXY"
                role            = "ACTIVE"
            }
        ]
    }
]
