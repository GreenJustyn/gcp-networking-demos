# Google Infra VPC Module

This module creates a set of VPCs from JSON.

# Usage

## Refer to the module in Terraform

module "google-infra-vpc" {
  source      = "../modules/google-infra-vpc"
  vpcs        = var.vpcs
  namesuffix  = local.suffix_nodash
}

namesuffix refers to a suffix you would like to append to any resources such as the VM name. Default is null.

# Variable Reference

Example

```
vpcs = [
    {
        project-id              = "mhanline-playpen002"
        network                 = "vpc-hub"
        delete_default_route    = false
        subnets                 = [
           {
                subnet_name = "hubsub-usc1"
                cidr_block = "10.10.0.0/22"
                region = "us-central1"
            },
            {
                subnet_name = "asia-se1-subnet"
                cidr_block = "10.122.0.0/22"
                region= "asia-southeast1"
            }
        ]
    },
    {
        project-id              = "mhanline-playpen002"
        network                 = "vpc-isolated"
        subnets                 =  [
           {
                subnet_name = "isolated-usc1"
                cidr_block = "10.20.0.0/22"
                region = "us-central1"
            }
        ]
    },
    {
        project-id              = "mhanline-playpen002"
        network                 = "vpc-onprem"
        delete_default_route    = true
        subnets                 =  [
           {
                subnet_name = "onprem-usc1"
                cidr_block = "10.30.0.0/22"
                region = "us-central1"
            }
        ]
    }
]
```

| Name  | Type  | Required | Description |
|---|---|---|---|
| network | String | Yes | Name of the VPC network that the firewall rule applies to. |
| delete_default_route | bool | No | Delete the 0.0.0.0/0 to default-internet-gateway on VPC creation. Default: false |
| auto_create_subnets | bool | No | Create auto-mode subnets (1 for each region). Default: false|
| project-id | String | No | Project ID. |
| subnets | list | No | Specify subnet_name, cidr_block, region to create a regional subnet |
| subnets.subnet_name | string | Yes | Specify subnet_name, cidr_block, region to create a regional subnet |
| subnets.cidr_block | string | Yes | Specify subnet_name, cidr_block, region to create a regional subnet |
| subnets.region | string | Yes | Specify subnet_name, cidr_block, region to create a regional subnet |
| subnets.purpose | String | No | Purpose field. Types supported: PRIVATE, REGIONAL_MANAGED_PROXY, GLOBAL_MANAGED_PROXY, PRIVATE_SERVICE_CONNECT or PRIVATE_NAT |
| subnets.role | String | No | Role field. Only used if purpose is REGIONAL_MANAGED_PROXY. Possible values: ACTIVE or BACKUP |
| append-suffix-tag | Boolean | No | Whether you want to append the suffix to the network tag. Default: false. |
