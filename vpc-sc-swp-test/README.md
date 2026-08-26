 # VPC-SC with Secure Web Proxy

Creates a VPC-SC perimeter with 1 or more projects inside the perimeter and 1 or mnore projects outside the perimeter.

A service account is created dynamically that is used to provision infrastructure. It is exempted from the VPC-SC perimeter through an ingress rule (created in Terraform also), so that the account doesn't get denied when managing infrastructure inside the perimeter.

# Installation

`git clone ....`

# Usage

## Refer to the module in Terraform

```

```


# Variable Reference


| Name  | Type  | Required | Description |
|---|---|---|---|
| parent_id | Number | Yes | The organization ID or folder ID required for the VPC-SC configuration |
| protected_project_ids | list(String) | Yes | List of project-IDs to protect within the VPC-SC perimeter |
| unprotected_project_ids | list(String)  | Yes | List of project-IDs which are outside the perimeter |
| region | String | Yes | Region to deploy infrastructure in |
| apis | List(string) | Yes | List of APIs to enable on the projects |
| restricted_services | List | Yes | APIs to protect within the VPC-sc Perimeter |
| sa_project_roles | List | Yes | IAM roles to assign to the VPC-SC service account that deploys the infrastructure |
| vpcs | Map | Yes | Map of key/values for the VPC network and subnet configuration |
| psc_ips | Map | Yes | PSC for GoogleAPIs IP addresses. |
| fw_rules | Mao | Yes | Map of key/value pairs for the VPC firewall rule configuration. |
| virtual_machines | Map | Yes | Map of key/values for the Compute Engine VMS to deploy |