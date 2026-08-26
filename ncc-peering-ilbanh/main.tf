provider "google" {
    project     = var.project-id
}

resource "random_id" "id" {
    byte_length = 3
}

data "google_compute_image" "debian_image" {
    family  = "debian-11"
    project = "debian-cloud"
}

data "google_compute_zones" "region_availability" {
    for_each    = local.full_region_list
    region      = each.value
}

locals {
    full_region_list    = toset(distinct(flatten([for val in var.vpcs:  val.subnets[*].region])))
}

resource "random_shuffle" "gcp_zones" {
    for_each        = { for region in data.google_compute_zones.region_availability: region.region => region.names }
    input           = [ for zone in each.value : zone ]
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "ilbanh-${random_id.id.hex}-cwd" = path.cwd
  }
}

resource "google_project_service" "apienable" {
    for_each                    = toset(var.apis)
    service                     = each.value
    disable_on_destroy          = false
    disable_dependent_services  = true
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    project-id  = var.project-id
    vpcs        = var.vpcs
    namesuffix  = random_id.id.hex
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    project-id  = var.project-id
    fw_rules    = var.fw_rules
    namesuffix  = random_id.id.hex
    depends_on = [ module.google-infra-vpc ]
}

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    project-id  = var.project-id
    vms         = var.virtual_machines
    namesuffix  = random_id.id.hex
    depends_on = [ module.google-infra-vpc ]
}

#
# NCC Configs
#

resource "google_network_connectivity_hub" "peering_hub" {
    project = var.project-id
    name    = "hub-${random_id.id.hex}"
}

resource "google_network_connectivity_spoke" "internal-spoke" {
  name = "spokeint-${random_id.id.hex}"
  project = "mhanline-playpen002"
  location = "global"
  description = "description-${random_id.id.hex}"
  hub = google_network_connectivity_hub.peering_hub.id
  linked_vpc_network {
    uri = module.google-infra-vpc.vpcs["vpc-internal"].self_link
  }
}

resource "google_network_connectivity_spoke" "external-spoke" {
  name = "spokeext-${random_id.id.hex}"
  project = "mhanline-playpen001cd psc-"
  location = "global"
  description = "description-${random_id.id.hex}"
  hub = google_network_connectivity_hub.peering_hub.id
  linked_vpc_network {
    uri = module.google-infra-vpc.vpcs["vpc-external"].self_link
  }
}