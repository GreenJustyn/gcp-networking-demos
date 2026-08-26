
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 7.29"
    }
  }
}

provider "google" {
  project     = var.project-id
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
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
    "compute-regions-v6${local.suffix}"  = path.cwd
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

resource "google_compute_network" "default_v6_ext" {
  name                      = "default-v6-ext${local.suffix}"
  auto_create_subnetworks   = false
  mtu                       = 1500
}

resource "google_compute_network" "default_v6_int" {
  name                      = "default-v6-int${local.suffix}"
  auto_create_subnetworks   = false
  mtu                       = 1500
  #enable_ula_internal_ipv6  = true
}

resource "google_compute_subnetwork" "subnetwork_v6_int" {
  for_each                = { for index, region in sort(values(data.google_compute_zones.filtered).*.region): region =>
      { 
        index = index + 1
      }
  }
  name                    = "int-${each.key}"
  ip_cidr_range           = "10.${each.value.index}.0.0/24"
  #stack_type              = "IPV4_IPV6"
  #stack_type              = "IPV6_ONLY"
  region                  = each.key
  #ipv6_access_type        = "INTERNAL"
  network                 = google_compute_network.default_v6_int.id
}

resource "google_compute_subnetwork" "subnetwork_v6_ext" {
  for_each                = data.google_compute_zones.filtered
  name                    = "ext-${each.key}"
  stack_type              = "IPV6_ONLY"
  region                  = each.key
  ipv6_access_type        = "EXTERNAL"
  network                 = google_compute_network.default_v6_ext.id
}

data "google_compute_default_service_account" "default_sa" { }

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
    stack_type = "IPV6_ONLY"
    subnetwork = google_compute_subnetwork.subnetwork_v6_ext[each.key].self_link
  }
  network_interface {
    #stack_type = "IPV4_IPV6"
    subnetwork = google_compute_subnetwork.subnetwork_v6_int[each.key].self_link
  }
  service_account {
    email = data.google_compute_default_service_account.default_sa.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
}

resource "google_tags_tag_key" "tag_key" {
  description = ""
  parent      = "projects/${var.project-id}"
  purpose     = "GCE_FIREWALL"
  short_name  = "vpc-tags${local.suffix}"
  purpose_data = {
    network = "${var.project-id}/${google_compute_network.default_v6_int.name}"
    network = "${var.project-id}/${google_compute_network.default_v6_ext.name}"
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

resource "google_compute_network_firewall_policy" "fw_policy_v6" {
  name        = "fwpolicyv6${local.suffix}"
  description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
  name              = "fwpolicyassoc${local.suffix}"
  attachment_target = google_compute_network.default_v6_int.id
  firewall_policy   =  google_compute_network_firewall_policy.fw_policy.name
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association_v6" {
  name              = "fwpolicyassoc${local.suffix}"
  attachment_target = google_compute_network.default_v6_ext.id
  firewall_policy   =  google_compute_network_firewall_policy.fw_policy_v6.name
}

resource "google_compute_network_firewall_policy_rule" "iap_rule_200" {
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
    src_ip_ranges =  ["0.0.0.0/0"]
    layer4_configs {
      ip_protocol = "tcp"
      ports = [22]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "iap_rule_220" {
  action                  = "allow"
  description             = ""
  direction               = "INGRESS"
  disabled                = false
  enable_logging          = false
  firewall_policy         = google_compute_network_firewall_policy.fw_policy_v6.name
  priority                = 220
  rule_name               = "iap-allow-v6${local.suffix}"
  target_secure_tags {
    name    = "tagValues/${google_tags_tag_value.tag_value_client.name}"
  }
  match {
    src_ip_ranges =  ["::/0"]
    layer4_configs {
      ip_protocol = "tcp"
      ports = [22]
    }
  }
}

resource "google_tags_location_tag_binding" "client_binding" {
  for_each      = google_compute_instance.client_instance
  parent        = "//compute.googleapis.com/projects/${data.google_project.default.number}/zones/${each.value.zone}/instances/${each.value.instance_id}"
  tag_value     = google_tags_tag_value.tag_value_client.id
  location      = each.value.zone
}
