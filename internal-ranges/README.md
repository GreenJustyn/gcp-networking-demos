
The following describes the topology:

# Installation

- Edit variables.tf set the `project-id` variable to your project.

```
terraform init
terraform plan
terraform apply
```

# Usage

Note: All resources will have a random ID appended to them. This is so you can deploy to the same project multiple times.

# Variable Reference

| Name  | Type  | Required | Description |
|---|---|---|---|
| project-id | String | Yes | Project ID to deploy into |
| region | String | Yes | Google Cloud region to deploy into |
| apis | List | Yes | List of Google APIs to enable |
| vpcs | Tuple | Yes | Used for the google-infra-vpc module. Specifies the VPC, subnet names/blocks/regions |
| fw_rules | Tuple | Yes | Used for the google-infra-firewall module. Specifies what VPC firewall rules to deploy |
| virtual_machines | Tuple | Yes | Used for the google-infra-vms module. Creates the test VMs. See the module's README for more details. |

# License

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)