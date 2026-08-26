#Copyright 2025 Google LLC
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.24"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 6.24"
    }
  }
}

provider "google" {
  project     = var.project-id
  region      = var.region
}

provider "google-beta" {
  project     = var.project-id
  region      = var.region
}

locals {
  suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
  suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

data "google_compute_snapshot" "default" {
  name        = var.snapshot_name
  project     = var.snapshot_project
  most_recent = true
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = toset(["iap-forwarders"])
  range_type = each.value
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_compute_network" "default" {
  name                    = "workstations${local.suffix}"
  auto_create_subnetworks = true
  mtu                     = 1500
}

data "google_compute_subnetwork" "default" {
  name   = google_compute_network.default.name
  region = var.region
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin                    = "TRUE"
    "workstations${local.suffix}"  = path.cwd
  }
}

data "google_compute_default_service_account" "default_sa" { }

resource "google_project_service" "apienable" {
    for_each                    = toset(var.apis)
    service                     = each.value
    disable_on_destroy          = false
    disable_dependent_services  = true
}

resource "google_workstations_workstation_cluster" "default" {
  provider               = google-beta
  workstation_cluster_id = "ws-cluster${local.suffix}"
  network                = google_compute_network.default.id
  subnetwork             = data.google_compute_subnetwork.default.id
  location               = var.region
#  private_cluster_config {
#    enable_private_endpoint = true
#  }
}

resource "google_workstations_workstation_config" "default" {
  provider               = google-beta
  workstation_config_id  = "ws-config${local.suffix}"
  workstation_cluster_id = google_workstations_workstation_cluster.default.workstation_cluster_id
  location                    = var.region
  host {
    gce_instance {
      machine_type            = var.machine_size
      boot_disk_size_gb       = 35
      service_account         = data.google_compute_default_service_account.default_sa.email
      service_account_scopes  = ["https://www.googleapis.com/auth/cloud-platform"]
      disable_ssh             = false
      #disable_public_ip_addresses = true
    }
  }
  persistent_directories {
    mount_path = "/home"
    gce_pd {
      source_snapshot = data.google_compute_snapshot.default.id
      reclaim_policy  = "RETAIN"
    }
  }
}

resource "google_workstations_workstation" "default" {
  provider               = google-beta
  workstation_id         = "ws${local.suffix}"
  workstation_config_id  = google_workstations_workstation_config.default.workstation_config_id
  workstation_cluster_id = google_workstations_workstation_cluster.default.workstation_cluster_id
  location                    = var.region
  labels = {  }
  env = {  }
  annotations = {  }
}


resource "google_compute_network_firewall_policy" "fw_policy" {
  name        = "fwpolicy${local.suffix}"
  description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
  name              = "fwpolicyassoc${local.suffix}"
  attachment_target = google_compute_network.default.id
  firewall_policy   =  google_compute_network_firewall_policy.fw_policy.name
}

resource "google_compute_network_firewall_policy_rule" "iap_rule" {
  action                  = "allow"
  description             = ""
  direction               = "INGRESS"
  disabled                = false
  enable_logging          = false
  firewall_policy         = google_compute_network_firewall_policy.fw_policy.name
  priority                = 200
  rule_name               = "iap-allow${local.suffix}"
  match {
    src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["iap-forwarders"].cidr_blocks_ipv4
    layer4_configs {
      ip_protocol = "tcp"
      ports = [22]
    }
  }
}