terraform {
  required_providers {
    google = {
    }
  }
}
locals {
    suffix          = var.namesuffix != "" ? "-${var.namesuffix}" : ""
    suffix_nodash   = var.namesuffix != "" ? "${var.namesuffix}" : ""
    policy_assoc    = transpose({for index,rule in var.fw_rules: rule.policy_name => rule.networks})
    policy_rule     = flatten([
        for policy in var.fw_rules: [
            for rule in policy.rule: {
                policyname                  = policy.policy_name
                rule_priority               = rule.priority
                rule_descr                  = try(rule.description,null)
                logging                     = try(rule.enable_logging, false)
                action                      = try(rule.action,"allow") #allow/deny/goto_next
                direction                   = try(rule.direction,"INGRESS")
                disabled                    = try(rule.disabled,null)
                src_ip_ranges               = try(split(",", rule.src_ip_ranges),rule.src_ip_ranges,null)
                dest_ip_ranges              = try(rule.dest_ip_ranges,null)
                src_address_groups          = try(rule.src_address_groups,null)
                dest_address_groups         = try(rule.dest_address_groups,null)
                src_fqdns                   = try(rule.src_fqdns,null)
                dest_fqdns                  = try(rule.dest_fqdns,null)
                src_region_codes            = try(rule.src_geo,null)
                dest_region_codes           = try(rule.dest_geo,null)
                src_secure_tags             = try(rule.src_secure_tags,null)
                dest_secure_tags            = try(rule.dest_secure_tags,null)
                src_threat_intelligences    = try(rule.src_threat_intelligences,null)
                dest_threat_intelligences   = try(rule.dst_threat_intelligences,null)
                layer4_configs              = rule.layer4_configs
            }
        ]
    ])
    tag_key         = flatten([
        for item in var.fw_tags: [
            for network in item.networks: {
                concat_key      = "${network}.${item.tag_name}"
                tag_network     = network
                tag_name        = item.tag_name
                tag_description = try(item.description, null)
                tag_parent      = try(
                    lower(item.parent) == "project" ? "projects/${data.google_project.project.number}" : tolist("x"),
                    lower(item.parent) == "organization" ? "organizations/" : tolist("x"), #To-do
                    "projects/${data.google_project.project.number}"
                )
                tag_values      = item.values
            }
        ]
    ])
    tag_value       = flatten([
        for item in local.tag_key: [
            for tag_value in item.tag_values: {
                concat_key          = "${item.concat_key}.${tag_value.tag_value}"
                concat_parent_key   = item.concat_key
                tag_value           = tag_value.tag_value
                parent              = item.tag_name
                description         = try(tag_value.description, null)
            }
        ]
    ])
}

data "google_project" "project" { 
}

resource "google_compute_network_firewall_policy" "fw_policy" {
    for_each            = {for policy in var.fw_rules: policy.policy_name => policy}
    name                = "${each.key}${local.suffix}"
    description         = try(each.value.description, [])
    project             = try(var.project-id, null)
}

resource "google_compute_network_firewall_policy_association" "fw_policy_assoc" {
    for_each            = local.policy_assoc
    name                = "${one(each.value)}${each.key}${local.suffix}"
    attachment_target   =  "projects/${google_compute_network_firewall_policy.fw_policy[one(each.value)].project}/global/networks/${each.key}${local.suffix}"
    firewall_policy     =  google_compute_network_firewall_policy.fw_policy[one(each.value)].id
    project             =  try(each.value.project-ids, null)
}

resource "google_compute_network_firewall_policy_rule" "fw_policy_rule" {
    for_each   = {
        for index,rule in local.policy_rule:
            "${rule.policyname}.${rule.rule_priority}" => rule
    }
    firewall_policy = google_compute_network_firewall_policy.fw_policy[each.value.policyname].name
    description     = each.value.rule_descr
    priority        = each.value.rule_priority
    enable_logging  = each.value.logging
    action          = lower(each.value.action)
    direction       = upper(each.value.direction)
    disabled        = each.value.disabled
    match {
        dynamic "layer4_configs" {
            for_each = {
                for index, l4config in each.value.layer4_configs:
                    index => l4config
            }
            iterator        = l4configlist
            content {
                ip_protocol = lower(l4configlist.value.protocol)
                ports       = try(split(",", l4configlist.value.ports), l4configlist.value.ports, [])
            }
        }
        dest_ip_ranges              = each.value.dest_ip_ranges
        src_ip_ranges               = each.value.src_ip_ranges
        dest_fqdns                  = each.value.dest_fqdns
        src_fqdns                   = each.value.src_fqdns
        dest_region_codes           = each.value.dest_region_codes
        src_region_codes            = each.value.src_region_codes
        dest_threat_intelligences   = each.value.dest_threat_intelligences
        src_threat_intelligences    = each.value.src_threat_intelligences
        src_address_groups          = each.value.src_address_groups
        dest_address_groups         = each.value.dest_address_groups
        #src_secure_tags {
        #    each.value.src_secure_tags #to-do
        #}
        #dest_secure_tags {
        #    each.value.dest_secure_tags #To-do
        #}
    }
    #target_service_accounts = ["my@service-account.com"]
}

#
# Tag Configs
#

#Secure tags can only be scoped to a single VPC network. Requires network-name + tag key for uniqueness.
/*
resource "google_tags_tag_key" "fw_tag_key" {
    for_each            = { for entry in local.tag_key: entry.concat_key => entry }
    parent              = each.value.tag_parent
    short_name          = "${each.value.tag_network}-${each.value.tag_name}${local.suffix}"
    description         = each.value.tag_description
    purpose             = "GCE_FIREWALL"
    purpose_data        = {
        network = "${data.google_project.project.number}/${each.value.tag_network}${local.suffix}"
    }
}
resource "google_tags_tag_value" "fw_tag_value" {
    for_each            = { for entry in local.tag_value: entry.concat_key => entry}
    parent              = "tagKeys/${google_tags_tag_key.fw_tag_key[each.value.concat_parent_key].name}"
    short_name          = "${each.value.tag_value}${local.suffix}"
    description         = each.value.description
}
*/
/*
resource "google_tags_tag_binding" "tag_binding" {
    for_each = { for entry in local.tag_value: entry.concat_key => entry}
    parent = "//cloudresourcemanager.googleapis.com/projects/${data.google_project.project.number}"
    tag_value = "tagValues/${google_tags_tag_value.fw_tag_value[each.key].name}"
}
*/

