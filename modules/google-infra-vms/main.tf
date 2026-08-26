terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

locals {
  suffix            = var.namesuffix != "" ? "-${var.namesuffix}" : ""
  suffix_nodash     = var.namesuffix != "" ? "${var.namesuffix}" : ""
  vms                = { for index, vm in var.vms:  vm.name => vm }
  #secure_tag_items  = flatten([for vm_entry in var.virtual_machines: [ for key,value in vm_entry: value if key == "secure-tags"]])
}

data "google_compute_zones" "region_availability" {
    for_each    = {
        for val in var.vms:
            "${coalesce(val.project-id, var.project-id)}/${val.region}" => val... if val.region != null
    }
    region      = each.value[0].region
    project     = each.value[0].project-id
}
/*
data "google_compute_subnetwork" "project_subnets" {
    name   = "default-us-east1"
    region = "us-east1"
}
*/
resource "random_shuffle" "region_zones" {
    for_each        = data.google_compute_zones.region_availability
    input           = each.value.names
}

data "google_compute_image" "compute_image" {
    for_each   = local.vms
    family  = try(split("/", each.value.image)[1], "debian-12")
    project = try(split("/", each.value.image)[0], "debian-cloud")
}

data "google_compute_default_service_account" "default_sa" {
    for_each    = toset(distinct(compact(setunion(var.vms.*.project-id,[var.project-id]))))
    project     = each.value
}

resource "google_compute_instance" "instances" {
    for_each   = {
        for index, vm in var.vms:
            vm.name => vm
    }
    name            = "${each.value.name}${local.suffix}"
    allow_stopping_for_update = true
    project         = coalesce(each.value.project-id, var.project-id)
    zone            = coalesce(each.value.zone, try(random_shuffle.region_zones["${coalesce(each.value.project-id, var.project-id)}/${each.value.region}"].result[0],""))
    machine_type    = each.value.machine-type
    description     = each.value.description
    can_ip_forward  = each.value.ip-forwarding
    tags   = try(try(each.value.append-suffix-tag, true) != false ? formatlist("%s${local.suffix}", each.value.tags) : each.value.tags, [])
    service_account {
        email   = data.google_compute_default_service_account.default_sa[coalesce(try(each.value.project-id,""), var.project-id)].email
        scopes  = try(each.value.scopes, ["cloud-platform"])
    }
    metadata_startup_script = try(templatefile(each.value.script, {}),null)
    network_interface {
        network             = can(each.value.subnet-project-id) ? null : can(each.value.network) ? "${each.value.network}${local.suffix}" : null
        #subnetwork          = try("${each.value.subnet}${local.suffix}", null)
        #May need to try a data source instead. Could fail on default network reference.
        subnetwork          = "projects/${coalesce(each.value.subnet-project-id, each.value.project-id, var.project-id)}/regions/${coalesce(each.value.region,try(replace(each.value.zone, "/.{2}$/", ""),""))}/subnetworks/${each.value.subnet}${local.suffix}"
        subnetwork_project  = try(each.value.subnet-project-id, each.value.project-id, var.project-id, null)
        dynamic "access_config" {
            for_each = coalesce(each.value.external-ipv4,true) ? [""] : []
            content {
                nat_ip  = null
            }
        }
        network_ip = try(
            each.value.private-ip,
            #Calculates the host number from the var.vpcs subnet. Painfully complex, sorry.
            cidrhost(flatten(var.vpcs[*].subnets.*.cidr_block)[index(flatten(var.vpcs[*].subnets.*.subnet_name),each.value.subnet)],each.value.cidrhostnum),
            null
        )
    }
    boot_disk {
        initialize_params {
        image = data.google_compute_image.compute_image[each.value.name].self_link
        labels = { }
        }
    }
}
/*
#Secure tags can only be scoped to a single VPC network. Requires network-name + tag key for uniqueness.
resource "google_tags_tag_key" "fw_tag_key" {
    for_each            = distinct(flatten([for item in local.secure_tag_items: keys(item)]))
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