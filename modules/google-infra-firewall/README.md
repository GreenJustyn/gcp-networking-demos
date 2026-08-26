# Google Infra Firewall Module

This module creates a set of firewall rules from JSON.

# Installation

`git clone ....`

# Usage

## Refer to the module in Terraform

```
module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    fw_rules    = var.fw_rules
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}
```

namesuffix refers to a suffix you would like to append to any resources such as the VM name. Default is null.

# Variable Reference

Example

```
fw_rules = [
    {
        id = "90001",
        name = "rfc1918-in",
        network  = "net-test",
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
        id = "90004",
        name = "iap-allow",
        network  = "net-test",
        description = "RFC1918 Ingress",
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
    }
]
```

| Name  | Type  | Required | Description |
|---|---|---|---|
| id | String | Yes | A unique identifier for the firewall rule. Only used within Terraform. |
| network | String | Yes | Name of the VPC network that the firewall rule applies to. |
| name | String  | Yes | Name of the firewall rule. Suffix appended if set. |
| description | String | No | Free-text description field. |
| action | String | No | Allow or Deny rule. |
| direction | String | Yes | ingress or egress rule. |
| log_config | String | No | Whether the rule hits are logged. Options: ENABLED or DISABLED. |
| priority | String | Yes | Rule priority. The order of the firewall rule applied to the VPC. Lowest number is higher priority. |
| project-id | String | No | Project ID. |
| sources | String | No | List of source IPs that apply to the firewall rule. If source_list is specified, this field is not applied. |
| source_list | String | No | Retrives a data source of known IPs. Matches [these fields](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/netblock_ip_ranges#argument-reference).  |
| rules | List | No | Consists of a list of rules, with a protocol and/or port list. See example. |
| ip-forwarding | Boolean | No | Whether you want to enable IP forwarding on the VM. Default: false |
| tags | List | No | Network tags to be assigned to the VM. |
| append-suffix-tag | Boolean | No | Whether you want to append the suffix to the network tag. Default: false. |
