terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.13"
    }
  }
}

provider "google" {
  project     = var.project-id
  region = "us-central1"
}

locals {
  suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
  suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

resource "random_id" "id" {
	byte_length = 4
}

resource "google_compute_project_metadata" "project_meta" {
  metadata = {
    enable-oslogin  = "TRUE"
    "scratch${local.suffix}" = path.cwd
  }
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    fw_rules    = var.fw_rules
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    vms         = var.virtual_machines
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}
