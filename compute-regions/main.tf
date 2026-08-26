
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 7.38"
    }
  }
}

provider "google" {
  project     = var.project-id
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
    #vms_region = {for i in setproduct(tolist(keys(data.google_compute_zones.filtered)),range(1,var.vms_per_region+1)): "${i[0]}_${i[1]}" => i}
}

data "google_project" "default" { }

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_project_service" "apienable" {
  for_each                    = toset(var.apis)
  service                     = each.value
  disable_on_destroy          = false
  disable_dependent_services  = true
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin                    = "TRUE"
    "compute-regions${local.suffix}"  = path.cwd
  }
}

data "google_compute_image" "default" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_regions" "all_regions" {
  status = "UP"
}

data "google_compute_zones" "filtered" {
  for_each  = {
    for region in data.google_compute_regions.all_regions.names: region => region if length([
      for filter_region in var.region_filter: filter_region if strcontains(region, filter_region)
    ]) > 0 || length(var.region_filter) == 0
  }
  region    = each.key
  status    = "UP"
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = toset(["iap-forwarders"])
  range_type = each.value
}

resource "google_compute_network" "default_net" {
  name                    = "default${local.suffix}"
  auto_create_subnetworks = true
  mtu                     = 1500
}

data "google_compute_default_service_account" "default_sa" { }

#Generate a cartesian product of regions and VMs per region. Then iterate over that to create the VMs.
resource "google_compute_instance" "client_instance" {
  for_each     = {for i in setproduct(tolist(keys(data.google_compute_zones.filtered)),range(1,var.vms_per_region+1)): "${i[0]}-${i[1]}" => i}
  name         = "inst${local.suffix}-${each.key}"
  machine_type = "e2-micro"
  #zone         = data.google_compute_zones.filtered[each.value[0]].names[0]
  zone         = element(data.google_compute_zones.filtered[each.value[0]].names,each.value[1]-1)
  metadata            = {
      startup-script  = templatefile("./debian-client.sh.tftpl", { })
  }
  boot_disk {
    initialize_params {
      image = data.google_compute_image.default.self_link
    }
  }
  network_interface {
    network = google_compute_network.default_net.self_link
    access_config {  }
  }
  service_account {
    email = data.google_compute_default_service_account.default_sa.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
}

/*
resource "google_compute_instance" "client_instance" {
  for_each     = data.google_compute_zones.filtered
  name         = "inst${local.suffix}-${each.key}"
  machine_type = "e2-micro"
  zone         = each.value.names[0]
  metadata            = {
      startup-script  = templatefile("./debian-client.sh.tftpl", { })
  }
  boot_disk {
    initialize_params {
      image = data.google_compute_image.default.self_link
    }
  }
  network_interface {
    network = google_compute_network.default_net.self_link
    access_config {  }
  }
  service_account {
    email = data.google_compute_default_service_account.default_sa.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
}
*/

resource "google_tags_tag_key" "tag_key" {
  description = ""
  parent      = "projects/${var.project-id}"
  purpose     = "GCE_FIREWALL"
  short_name  = "vpc-tags${local.suffix}"
  purpose_data = {
    network = "${var.project-id}/${google_compute_network.default_net.name}"
  }
}

resource "google_tags_tag_value" "tag_value_client" {
  description = ""
  parent      = "tagKeys/${google_tags_tag_key.tag_key.name}"
  short_name  = "client${local.suffix}"
}

resource "google_compute_network_firewall_policy" "fw_policy" {
  name        = "fwpolicy${local.suffix}"
  description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
  name              = "fwpolicyassoc${local.suffix}"
  attachment_target = google_compute_network.default_net.id
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
  target_secure_tags {
    name    = "tagValues/${google_tags_tag_value.tag_value_client.name}"
  }
  match {
    src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["iap-forwarders"].cidr_blocks_ipv4
    layer4_configs {
      ip_protocol = "tcp"
      ports = [22]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "rfc1918_rule" {
    action                  = "allow"
    description             = ""
    direction               = "INGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = google_compute_network_firewall_policy.fw_policy.name
    priority                = 20000
    rule_name               = "rfc1918-allow${local.suffix}"
    match {
        src_ip_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
        layer4_configs {
        ip_protocol = "all"
        }
    }
}

resource "google_tags_location_tag_binding" "client_binding" {
  for_each      = google_compute_instance.client_instance
  parent        = "//compute.googleapis.com/projects/${data.google_project.default.number}/zones/${each.value.zone}/instances/${each.value.instance_id}"
  tag_value     = google_tags_tag_value.tag_value_client.id
  location      = each.value.zone
}
