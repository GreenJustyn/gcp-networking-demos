# Google Infra VM Module

This module creates a set of VMs from JSON.

# Installation

`git clone ....`

# Usage

## Refer to the module in Terraform

```
module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    project-id  = var.project-id
    vms         = var.virtual_machines
    namesuffix  = random_id.id.hex
}
```

namesuffix refers to a suffix you would like to append to any resources such as the VM name.

# Variable Reference

Example

```
virtual_machines = [
    {
        name            = "testclient-int-vm"
        network         = "site1-vpc"
        subnet          = "vpc-internal-subnet"
        zone            = "asia-southeast1-a"
        external-ipv4   = false
        description     = ""
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-12"
        private-ip      = "192.168.235.3"
        can_ip_forward  = true
        tags            = ["allow-ssh", "allow-something"]
        append-suffix-tag = true
    },
    {
        name            = "testclient-ext-vm"
        subnet          = "vpc-external-subnet"
        zone            = "asia-southeast1-a"
        machine-type    = "e2-micro"
        image           = "debian-cloud/debian-11"
        tags            = ["allow-ssh", "allow-something"]
    }    
]
```

| Name  | Type  | Required | Description |
|---|---|---|---|
| name | String | Yes | Name of the VM. Appends a suffix if one is provided using namesuffix. |
| network | String | No | Name of the VPC network. Matches the network name + suffix if one is provided. Not used if subnet-project-id is specified. |
| subnet | String  | No | Name of the VPC subnet. Matches the network name + suffix if one is provided. |
| subnet-project-id | String | No | Name of the project ID that references the subnet. Not required unless using Shared VPC. Use the host project ID if using Shared VPC. |
| project-id | String | No | Name of the project-ID. Uses the Provider's project-id if omitted. |
| zone | String | No | Compute Engine zone the VM is to be placed. Required if region is null. |
| region | String | No | Compute Engine region. Only used if you don't specify a zone. VM placement will be random |
| machine-type | String | No | Compute Engine machine type. Default "e2-micro" |
| scopes | List | No | Service Account scopes. Default = ["cloud-platform"]. |
| external-ipv4 | Bool | No | External or public IP type. Takes true or false. Default: false.|
| description | String | No | Description of the VM.|
| image | String | Yes | Project/Image name of the Compute Engine image. |
| script | String | No | Filename of a startup script. |
| private-ip | String | No | If you want to specify a private IP, enter it here. Overrides cidrhostnum if both are specified. |
| cidrhostnum | String | No | Specify the host number for the private IP. This value is the number of digits after the host address. E.g. With a CIDR block of 10.1.1.0/24, a value of 100 would assign the IP of 10.1.1.100 to the virtual machine. |
| ip-forwarding | Boolean | No | Whether you want to enable IP forwarding on the VM. Default: false |
| tags | List | No | Network tags to be assigned to the VM. |
| append-suffix-tag | Boolean | No | Whether you want to append the suffix to the network tag. Default: true. |
