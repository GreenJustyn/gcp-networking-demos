terraform {
  required_providers {
    google = {
    }
  }
}
locals {
  suffix = var.namesuffix != "" ? "-${var.namesuffix}" : ""
  suffix_nodash = var.namesuffix != "" ? "${var.namesuffix}" : ""
}

data "google_netblock_ip_ranges" "ip_range_data" {
  for_each = toset([
    "health-checkers",
    "iap-forwarders",
    "cloud-netblocks",
    "google-netblocks",
    "restricted-googleapis",
    "private-googleapis",
    "legacy-health-checkers"
  ])
  range_type = each.key
}

resource "google_compute_firewall" "vpc_firewall_rules" {
    for_each   = {
        for index, rule in var.fw_rules:
            rule.id => rule
    }
    project         = try(each.value.project-id, var.project-id, null)
    name            = "${each.value.name}${local.suffix}"
    network         = "${each.value.network}${local.suffix}"
    description     = try(each.value.description, null)
    direction       = each.value.direction
    priority        = each.value.priority
    dynamic "allow" {
        for_each =  {
            for index, allowrule in each.value.rules:
                index => allowrule
        }
        iterator        = allowlist
        content {
            protocol    = lower(allowlist.value.protocol)
            ports       = try(split(",", allowlist.value.ports),allowlist.value.ports, [])
        }
    }
    source_ranges   = concat(try(flatten([for ipsource in each.value.source_list: data.google_netblock_ip_ranges.ip_range_data[ipsource].cidr_blocks_ipv4]),[]), each.value.sources)
    target_tags     = try(distinct([for tag in each.value.target_tags:
        "${tag}${local.suffix}"
    ]), [])
}
