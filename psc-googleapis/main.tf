provider "google" {
  project     = var.project-id
  region      = var.region
}
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.16"
    }
  }
}
locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}
resource "google_project_service" "apienable" {
    for_each = toset(var.apis)
    service     = each.value
    disable_on_destroy = false
    disable_dependent_services = true
}
resource "google_compute_project_metadata" "default" {
    metadata = {
      enable-oslogin  = "TRUE"
      enable-osconfig = "TRUE"
      enable-guest-attributes = "TRUE"
      "psc-googleapis${local.suffix}" = path.cwd
    }
}
resource "random_id" "id" {
	  byte_length = 4
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    fw_rules    = var.fw_rules
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

module "google-infra-vms" {
  source        = "../modules/google-infra-vms"
  vms           = var.virtual_machines
  namesuffix    = local.suffix_nodash
  project-id    = var.project-id
  depends_on    = [ module.google-infra-vpc ]
}

resource "google_compute_global_address" "psc-ip" {
  name         = "psc-apis-ip${local.suffix}"
  address_type = "INTERNAL"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  network      = values(module.google-infra-vpc.vpcs)[0].id
  address      = "10.250.250.250"
}

resource "google_compute_global_forwarding_rule" "default" {
  name                  = "apisfr${local.suffix_nodash}"
  target                = "all-apis"
  network               = values(module.google-infra-vpc.vpcs)[0].id
  ip_address            = google_compute_global_address.psc-ip.address
  load_balancing_scheme = ""
}

# DNS #

resource "google_dns_managed_zone" "google-apis" {
  name        = "zone${local.suffix}"
  dns_name    = "googleapis.com."
  description = "private zone for Google APIs"
  visibility = "private"
  private_visibility_config {
    networks {
      network_url = values(module.google-infra-vpc.vpcs)[0].self_link
    }
  }
}

resource "google_dns_record_set" "psc_googleapis_zone_a" {
    name          = "googleapis.com."
    type          = "A"
    ttl           = 300
    managed_zone  = google_dns_managed_zone.google-apis.name
    rrdatas       = [google_compute_global_address.psc-ip.address]
}

resource "google_dns_record_set" "psc_googleapis_zone_cname" {
    name    = "*.googleapis.com."
    type    = "CNAME"
    ttl     = 300
    managed_zone = google_dns_managed_zone.google-apis.name
    rrdatas = ["googleapis.com."]
}
