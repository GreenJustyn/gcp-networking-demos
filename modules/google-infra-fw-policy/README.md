# Google Infra VM Module

This module creates a set of VMs from JSON.

# Installation

`git clone ....`

# Usage

## Refer to the module in Terraform

```
module "google-infra-vms" {
    source      = "../modules/google-infra-fw-policy"
    project-id  = var.project-id
    fw_rules    = var.fw_rules
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}
```

namesuffix refers to a suffix you would like to append to any resources such as the VM name.

# Variable Reference

Example

```
fw_rules = [
    {
        policy_name = "global1",
        networks  = ["net-test", "net-dev"]
        description = "test policy"
        rule = [{
            action = "allow",
            description = "Test rule description",
            direction = "INGRESS",
            log_config = "DISABLED",
            priority = 1002,
            src_ip_ranges = [
                "192.168.0.0/16",
                "10.0.0.0/8",
                "172.16.0.0/12"
            ],
            layer4_configs = [{
                protocol = "TCP"
                ports   = [80, 443]
            },
            {
                protocol = "ICMP"
            }]
        },
        {
            action = "allow",
            direction = "INGRESS",
            log_config = "DISABLED",
            priority = 1001,
            src_ip_ranges = [
                "192.168.0.0/16",
                "10.0.0.0/8",
                "172.16.0.0/12"
            ],
            layer4_configs = [{
                protocol = "TCP"
                ports   = 80
            },
            {
                protocol = "ICMP"
            }]
        }        
]
    }
]
```

| Name  | Type  | Required | Description |
|---|---|---|---|
| policy_name | String | Yes | Name of the firewall policy. Appends a suffix if one is provided using namesuffix. |
| networks | List | Yes | Names of 1 or more VPC networks to associate the policy with. Matches the network name + suffix if one is provided. |
| description | String  | No | Description of the policy. |
| rule | Object | Yes | One or more firewall rules. Requires a unique priority per rule per policy. |
| rule:action | String | No | Name of the project-ID. Uses the Provider's project-id if omitted. |
| rule:description | String | No | Rule description. |
| rule:direction | String | No | Options are INGRESS or EGRESS. Direction of the firewall rule. If unspecified, defaults to INGRESS. |
| rule:enable_logging | boolean | No | Enable or disable logging. If unset, defaults to false. |
| rule:priority | Integer | Yes | Unique priority number of the rule. Must be unique per policy. |
| rule:src_ip_ranges | List | No | List of IPs for a rule to apply to. Accepts a list type, or a comma separated string. |
| rule:layer4_configs | Object | Yes | Used to specify the ports/protocols. |
| rule:layer4_configs:protocol | String | No | Name of the protocol. Can either be tcp, udp, icmp, esp, ah, ipip, sctp, or the IP protocol number. |
| rule:layer4_configs:ports | List | No | List of ports. Accepts a list type, or a comma separated string. |
| --- | Boolean | No | --- |
