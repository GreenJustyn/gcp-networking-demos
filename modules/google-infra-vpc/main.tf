terraform {
  required_providers {
    google-beta = {
      source = "hashicorp/google-beta"
      version     = ">= 7.44"
    }
    google = {
      source = "hashicorp/google"
      version     = ">= 7.44"
    }
  }
}

locals {
  network_subnets       = flatten([
    for vpc_key, subnet in var.vpcs : [
      subnet.subnets == null ? [] : [
        for subnet_details in subnet.subnets : {
          network         = subnet.network
          cidr_block      = subnet_details.cidr_block
          region          = subnet_details.region
          subnet_name     = subnet_details.subnet_name
          purpose         = try(subnet_details.purpose, null)
          role            = try(subnet_details.role, null)
          project         = try(subnet.project-id, null)
          pga             = try(subnet_details.pga, null)
        }
      ]
    ]
  ])
  suffix = var.namesuffix != "" ? "-${var.namesuffix}" : ""
  suffix_nodash = var.namesuffix != "" ? "${var.namesuffix}" : ""
}

resource "google_compute_network" "vpc" {
  # If duplicate keys (i.e. same VPC name across projects, then catch the failure and use "project/VPCname" instead.)
  for_each                        = try({
    for index, vpc in var.vpcs:
        vpc.network => vpc 
  },
  {
    for index, vpc in var.vpcs:
        "${coalesce(vpc.project-id,var.project-id)}/${vpc.network}" => vpc
  })
  name                            = "${each.value.network}${local.suffix}"
  auto_create_subnetworks         = try(each.value.auto_create_subnets, false)
  delete_default_routes_on_create = try(each.value.delete_default_route, false)
  mtu                             = try(each.value.mtu, 1500)
  project                         = try(coalesce(each.value.project-id, var.project-id))
  lifecycle {
      create_before_destroy = false
  }
}

resource "google_compute_subnetwork" "subnet" {
    for_each                    = {
        for index, subnet in local.network_subnets:
            subnet.subnet_name => subnet
    }
    name                        = "${each.value.subnet_name}${local.suffix}"
    ip_cidr_range               = each.value.cidr_block
    region                      = each.value.region
    #Support either VPC-name or project/VPC-Name format
    network                     = try(
      google_compute_network.vpc[each.value.network].name,
      google_compute_network.vpc["${try(each.value.project, var.project-id)}/${each.value.network}"].name
    )
    purpose                     = try(each.value.purpose, null)
    role                        = try(each.value.role, null)
    project                     = try(each.value.project, var.project-id)
    # You can only turn on PGA for private subnets
    private_ip_google_access    = coalesce(each.value.pga,coalesce(each.value.purpose, "PRIVATE") == "PRIVATE" ? true : false)
    lifecycle {
        create_before_destroy = false
    }
}
