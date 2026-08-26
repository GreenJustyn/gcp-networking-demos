terraform {
  required_providers {
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 7.45.0"
    }
    google = {
      source = "hashicorp/google"
      version     = "~> 7.45.0"
    }
  }
}

locals {
  suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
  suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
  #full_region_list    = toset(distinct(flatten([for val in var.vpcs:  val.subnets[*].region])))
  #region_zones = var.all_zones ? {for i in data.google_compute_zones.region_availability[var.region].names: i => null} : {data.google_compute_zones.region_availability[var.region].names[0] = null}
}

provider "google" {
    project     = var.project-id
    region      = var.region
}

resource "random_id" "id" {
    byte_length = 2
}
/*
data "google_compute_image" "debian_image" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

data "google_compute_zones" "region_availability" {
    for_each    = local.full_region_list
    region      = each.value
}

data "google_compute_default_service_account" "default_sa" { }

resource "random_shuffle" "gcp_zones" {
    for_each        = { for region in data.google_compute_zones.region_availability: region.region => region.names }
    input           = [ for zone in each.value : zone ]
}
*/

resource "google_project_service" "apienable" {
  for_each = toset(var.apis)
  service     = each.value
  disable_on_destroy = false
  disable_dependent_services = true
}

resource "google_compute_project_metadata" "project_meta" {
  metadata = {
    enable-oslogin  = "TRUE"
    "internal-ranges${local.suffix}" = path.cwd
  }
}

resource "google_compute_network" "default_primary" {
  name                    = "ir-pri${local.suffix}"
  auto_create_subnetworks = false
}

resource "google_compute_network" "default_secondary" {
  name                    = "ir-sec${local.suffix}"
  auto_create_subnetworks = false
}

resource "google_network_connectivity_internal_range" "primary" {
  name    = "pri${local.suffix}"
  description = "pri"
  network = google_compute_network.default_primary.self_link
  usage   = "FOR_VPC"
  peering = "FOR_SELF"
  prefix_length = 24
  target_cidr_range = [
    "10.1.0.0/16"
  ]
}

resource "google_compute_subnetwork" "internal_primary" {
  name                    = "default-pri${local.suffix}"
  region                  = "us-central1"
  network                 = google_compute_network.default_primary.id
  reserved_internal_range = "networkconnectivity.googleapis.com/${google_network_connectivity_internal_range.primary.id}"
}

resource "google_network_connectivity_internal_range" "secondary" {
  name    = "sec${local.suffix}"
  description = "sec"
  network = google_compute_network.default_secondary.self_link
  usage   = "FOR_VPC"
  peering = "FOR_SELF"
  ip_cidr_range = "10.1.0.0/24"
}

resource "google_compute_subnetwork" "internal_secondary" {
  name                    = "ir-sec${local.suffix}"
  region                  = "us-central1"
  network                 = google_compute_network.default_secondary.id
  reserved_internal_range = "networkconnectivity.googleapis.com/${google_network_connectivity_internal_range.secondary.id}"
}

#
# NCC Configs
#

resource "google_network_connectivity_hub" "peering_hub" {
    project = var.project-id
    name    = "hub${local.suffix}"
}

resource "google_network_connectivity_group" "default"  {
  hub         = google_network_connectivity_hub.peering_hub.id
  name        = "default"
  auto_accept {
    auto_accept_projects = [var.project-id]
  }
}

resource "google_network_connectivity_spoke" "spoke_pri" {
  name      = "pri${local.suffix}"
  location  = "global"
  hub       = google_network_connectivity_hub.peering_hub.id
  linked_vpc_network {
    uri                   = google_compute_network.default_primary.id
    exclude_export_ranges = ["100.64.0.0/10"]
  }
}

resource "google_network_connectivity_spoke" "spoke_sec" {
  name      = "sec${local.suffix}"
  location  = "global"
  hub       = google_network_connectivity_hub.peering_hub.id
  linked_vpc_network {
    uri                   = google_compute_network.default_secondary.id
    exclude_export_ranges = ["100.64.0.0/10"]
  }
}

resource "google_network_connectivity_internal_range" "cgnat_primary" {
  name    = "cgnatpri${local.suffix}"
  description = "pri"
  network = google_compute_network.default_primary.self_link
  usage   = "FOR_VPC"
  peering = "FOR_SELF"
  #prefix_length = 23
  ip_cidr_range = "100.64.100.0/23"
  # target_cidr_range = [
  #   "100.64.0.0/10"
  # ]
}

resource "google_compute_subnetwork" "cgnat_primary" {
  name                    = "cgnat-pri${local.suffix}"
  region                  = "us-central1"
  network                 = google_compute_network.default_primary.id
  reserved_internal_range = "networkconnectivity.googleapis.com/${google_network_connectivity_internal_range.cgnat_primary.id}"
  ip_cidr_range           = "100.64.100.0/24"
}

resource "google_compute_subnetwork" "cgnat_primary_2" {
  name                    = "cgnat-pr2i${local.suffix}"
  region                  = "us-central1"
  network                 = google_compute_network.default_primary.id
  reserved_internal_range = "networkconnectivity.googleapis.com/${google_network_connectivity_internal_range.cgnat_primary.id}"
  ip_cidr_range           = "100.64.101.0/24"
}


resource "google_network_connectivity_internal_range" "cgnat_secondary" {
  name    = "cgnatsec${local.suffix}"
  description = "sec"
  network = google_compute_network.default_secondary.self_link
  usage   = "FOR_VPC"
  peering = "FOR_SELF"
  ip_cidr_range = "100.64.100.0/23"
}

resource "google_compute_subnetwork" "cgnat_secondary_1" {
  name                    = "cgnat-sec1${local.suffix}"
  region                  = "us-central1"
  network                 = google_compute_network.default_secondary.id
  reserved_internal_range = "networkconnectivity.googleapis.com/${google_network_connectivity_internal_range.cgnat_secondary.id}"
  ip_cidr_range           = "100.64.100.0/24"
}

/*
resource "google_compute_subnetwork" "cgnat_secondary" {
  for_each                = toset(["0","1","2"])
  name                    = "cgnat-${substr(md5("${each.key}${google_compute_network.default_secondary.id}"),0,4)}${local.suffix}"
  region                  = "us-central1"
  network                 = google_compute_network.default_secondary.id
  reserved_internal_range = "networkconnectivity.googleapis.com/${google_network_connectivity_internal_range.cgnat_secondary.id}"
}
*/
/*
resource "google_compute_subnetwork" "cgnat_secondary" {
  for_each                = { for i in range(pow(2, google_network_connectivity_internal_range.cgnat_secondary.prefix_length - tonumber(split("/", google_network_connectivity_internal_range.cgnat_secondary.target_cidr_range[0])[1]))): tostring(i) => i }
  name                    = "cgnat-${substr(md5("${each.key}${google_compute_network.default_secondary.id}"),0,4)}${local.suffix}"
  region                  = "us-central1"
  network                 = google_compute_network.default_secondary.id
  reserved_internal_range = "networkconnectivity.googleapis.com/${google_network_connectivity_internal_range.cgnat_secondary.id}"
  #ip_cidr_range           = 
}
*/