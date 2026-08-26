# Set up for https://codelabs.developers.google.com/cloud-firewall-plus
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.36"
    }
  }
}

provider "google" {
  project               = var.project-id
  region                = var.region
  billing_project       = var.project-id
  user_project_override = true
}

locals {
  suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
  suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
  #zones = { for zone in data.google_compute_zones.region_availability.names : zone => reverse(split("-",zone))[0] }
  zones = var.all_zones ? {for zone in data.google_compute_zones.region_availability.names : zone => reverse(split("-",zone))[0]} : tomap({(data.google_compute_zones.region_availability.names[0]) = reverse(split("-",data.google_compute_zones.region_availability.names[0]))[0]})
}

data "google_compute_image" "debian_image" {
  family  = "debian-12"
  project = "debian-cloud"
}

data "google_compute_zones" "region_availability" {
  region  = var.region
}

data "google_project" "project_info" {
  project_id  = var.project-id
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

data "google_compute_default_service_account" "default" { }

resource "random_id" "id" {
  byte_length = 2
}

resource "google_project_service" "apienable" {
    for_each                    = { for api in var.apis : api => null }
    service                     = each.key
    disable_on_destroy          = false
    disable_dependent_services  = true
}

resource "google_compute_project_metadata" "project_meta" {
  metadata = {
    enable-oslogin            = "TRUE"
    "ngfw-ent${local.suffix}" = path.cwd
  }
}

module "google-infra-vpc" {
  source      = "../modules/google-infra-vpc"
  vpcs        = var.vpcs
  namesuffix  = local.suffix_nodash
}

resource "google_network_security_security_profile" "security_profile" {
  name        = "fw-sp${local.suffix}"
  parent      = "organizations/${var.org-id}"
  description = "Terraform created security profile for ${local.suffix_nodash}"
  type        = "THREAT_PREVENTION"
}

resource "google_network_security_security_profile_group" "security_profile_group" {
  name                      = "fw-spg${local.suffix}"
  parent                    = google_network_security_security_profile.security_profile.parent
  description               = "Terraform created security profile group for ${local.suffix}"
  threat_prevention_profile = google_network_security_security_profile.security_profile.id
}

resource "google_network_security_firewall_endpoint" "fw_endpoint" {
  for_each            = local.zones
  name                = "fwep${local.suffix}-${each.value}"
  parent              = google_network_security_security_profile_group.security_profile_group.parent
  location            = each.key
  billing_project_id  = var.project-id
}

resource "google_network_security_firewall_endpoint_association" "ngfw_association" {
  for_each          = google_network_security_firewall_endpoint.fw_endpoint
  name              = "fw-assoc${local.suffix}-${each.key}"
  parent            = "projects/${var.project-id}"
  location          = each.value.location
  network           = values(module.google-infra-vpc.vpcs)[0].id
  firewall_endpoint = each.value.id
}

resource "google_compute_router" "nat_router" {
  name    = "nat-router${local.suffix}"
  region  = var.region
  network = values(module.google-infra-vpc.vpcs)[0].id
}

resource "google_compute_router_nat" "nat_auto" {
  name                                = "nat${local.suffix}"
  router                              = google_compute_router.nat_router.name
  region                              = google_compute_router.nat_router.region
  nat_ip_allocate_option              = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat  = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_instance_template" "default" {
    name_prefix     = "ilb-tpl${local.suffix}"
    machine_type    = "e2-micro"
    region          = var.region
    lifecycle {
        create_before_destroy = true
        ignore_changes        = [disk[0].source_image]
    }
      metadata = {
        startup-script = templatefile("./debian-host.sh.tftpl", { })
    }
    disk {
        source_image = data.google_compute_image.debian_image.self_link
    }
    network_interface {
        subnetwork = values(module.google-infra-vpc.subnets)[0].self_link
        access_config { }
    }
}

resource "google_compute_health_check" "default" {
  name               = "hc${local.suffix}-host"
  https_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}

resource "google_compute_region_instance_group_manager" "default" {
    name                = "ig${local.suffix}"
    base_instance_name  = "ig"
    region              = var.region
    target_size         = length(local.zones)
    version {
        instance_template = google_compute_instance_template.default.id
    }
    named_port {
        name = "https"
        port = 443
    }
    auto_healing_policies {
        health_check      = google_compute_health_check.default.id
        initial_delay_sec = 30
    }
    update_policy {
        type                            = "PROACTIVE"
        minimal_action                  = "REPLACE"
        most_disruptive_allowed_action  = "REPLACE"
        max_surge_fixed                 = 0
        max_unavailable_fixed           = length(data.google_compute_zones.region_availability.names)
    }
}

resource "google_compute_region_backend_service" "bs_internal" {
    name                              = "bs-int${local.suffix}"
    load_balancing_scheme             = "INTERNAL"
    protocol                          = "TCP"
    region                            = var.region
    health_checks                     = [google_compute_health_check.default.self_link]
    connection_draining_timeout_sec   = 10
    network                           = values(module.google-infra-vpc.vpcs)[0].self_link
    backend {
        group = google_compute_region_instance_group_manager.default.instance_group
        balancing_mode = "CONNECTION"
    }
}

resource "google_compute_forwarding_rule" "default" {
    name                    = "fr-internal${local.suffix}"
    network                 = values(module.google-infra-vpc.vpcs)[0].self_link
    subnetwork              = values(module.google-infra-vpc.subnets)[0].self_link
    all_ports               = true
    load_balancing_scheme   = "INTERNAL"
    ip_protocol             = "TCP"
    region                  = var.region
    ip_address              = google_compute_address.ilb_reserve.id
    allow_global_access     = true
    backend_service         = google_compute_region_backend_service.bs_internal.id
}

resource "google_compute_address" "ilb_reserve" {
  name         = "res${local.suffix}"
  subnetwork   = module.google-infra-vpc.subnets[module.google-infra-vpc.network_subnets[0].subnet_name].self_link
  address_type = "INTERNAL"
  address      = cidrhost(values(module.google-infra-vpc.subnets)[0].ip_cidr_range,50)
  region       = var.region
}

resource "google_compute_instance" "host_instance" {
  name         = "inst${local.suffix}-host"
  machine_type = "e2-micro"
  zone         = data.google_compute_zones.region_availability.names[0]
  metadata            = {
      startup-script      = templatefile("./debian-host.sh.tftpl", { })
  }
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
  network_interface {
    subnetwork = module.google-infra-vpc.subnets[module.google-infra-vpc.network_subnets[0].subnet_name].self_link
    #network_ip  = google_compute_address.host_reservation.address
  }
  service_account {
    email = data.google_compute_default_service_account.default.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
}

resource "google_compute_instance_group" "host" {
  name        = "ig${local.suffix}-host"
  instances = [
    google_compute_instance.host_instance.id
  ]
  zone = google_compute_instance.host_instance.zone
}

resource "google_compute_instance" "client_instance" {
  for_each      = local.zones
  name          = "inst${local.suffix}-client${each.key}"
  machine_type  = "e2-micro"
  zone          = each.key
  metadata            = {
      startup-script      = templatefile("./debian-client.sh.tftpl", {
        nlb_ip      = google_compute_forwarding_rule.default.ip_address
      })
  }
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
  network_interface {
    subnetwork = module.google-infra-vpc.subnets[module.google-infra-vpc.network_subnets[0].subnet_name].self_link
  }
  service_account {
    email = data.google_compute_default_service_account.default.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
}

resource "google_tags_tag_key" "tag_key_purpose" {
  description = ""
  parent      = "projects/${var.project-id}"
  purpose     = "GCE_FIREWALL"
  short_name  = "vm-purpose${local.suffix}"
  purpose_data = {
    network = "${var.project-id}/${module.google-infra-vpc.vpcs[module.google-infra-vpc.network_subnets[0].network].name}"
  }
}

resource "google_tags_tag_key" "tag_key_internet" {
  description = ""
  parent      = "projects/${var.project-id}"
  purpose     = "GCE_FIREWALL"
  short_name  = "vm-internet${local.suffix}"
  purpose_data = {
    network = "${var.project-id}/${module.google-infra-vpc.vpcs[module.google-infra-vpc.network_subnets[0].network].name}"
  }
}

resource "google_tags_tag_value" "tag_value_purpose" {
  for_each    = { "client" = null, "server" = null }
  description = ""
  parent      = "tagKeys/${google_tags_tag_key.tag_key_purpose.name}"
  short_name  = "${each.key}${local.suffix}"
}

resource "google_tags_tag_value" "tag_value_internet" {
  description = ""
  parent      = "tagKeys/${google_tags_tag_key.tag_key_internet.name}"
  short_name  = "true${local.suffix}"
}

resource "google_tags_location_tag_binding" "client_binding" {
  for_each      = google_compute_instance.client_instance
  parent        = "//compute.googleapis.com/projects/${data.google_project.project_info.number}/zones/${each.value.zone}/instances/${each.value.instance_id}"
  tag_value     = google_tags_tag_value.tag_value_purpose["client"].id
  location      = each.value.zone
}

resource "google_tags_location_tag_binding" "host_binding" {
  parent        = "//compute.googleapis.com/projects/${data.google_project.project_info.number}/zones/${google_compute_instance.host_instance.zone}/instances/${google_compute_instance.host_instance.instance_id}"
  tag_value     = google_tags_tag_value.tag_value_purpose["server"].id
  location      = google_compute_instance.host_instance.zone
}

resource "google_compute_network_firewall_policy" "ngfw_fw_policy" {
  name        = "ngfwpolicy${local.suffix}"
  description = ""
}

resource "google_compute_network_firewall_policy_association" "ngfw_fw_policy_association" {
  name              = "ngfwpolicyassoc${local.suffix}"
  attachment_target = module.google-infra-vpc.vpcs[module.google-infra-vpc.network_subnets[0].network].id
  firewall_policy   =  google_compute_network_firewall_policy.ngfw_fw_policy.name
}

resource "google_compute_network_firewall_policy_rule" "hc_rule" {
  action                  = "allow"
  description             = ""
  direction               = "INGRESS"
  disabled                = false
  enable_logging          = false
  firewall_policy         = google_compute_network_firewall_policy.ngfw_fw_policy.name
  priority                = 101
  rule_name               = "health-check-allow${local.suffix}"
  target_secure_tags {
    name = "tagValues/${google_tags_tag_value.tag_value_purpose["server"].name}"
  }
  match {
    src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["health-checkers"].cidr_blocks_ipv4
    layer4_configs {
      ip_protocol = "tcp"
      ports = [80]
    }
    layer4_configs {
      ip_protocol = "tcp"
      ports = [443]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "iap_rule" {
  action                  = "allow"
  description             = ""
  direction               = "INGRESS"
  disabled                = false
  enable_logging          = false
  firewall_policy         = google_compute_network_firewall_policy.ngfw_fw_policy.name
  priority                = 201
  rule_name               = "iap-allow${local.suffix}"
  target_secure_tags {
    name    = "tagValues/${google_tags_tag_value.tag_value_purpose["server"].name}"
  }
  target_secure_tags {
    name    = "tagValues/${google_tags_tag_value.tag_value_purpose["client"].name}"
  }
  match {
    src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["iap-forwarders"].cidr_blocks_ipv4
    layer4_configs {
      ip_protocol = "tcp"
      ports = [22]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "ingress_internal_rule" {
  action                  = "apply_security_profile_group"
  description             = ""
  direction               = "INGRESS"
  disabled                = false
  enable_logging          = false
  firewall_policy         = google_compute_network_firewall_policy.ngfw_fw_policy.name
  priority                = 800
  rule_name               = "ingress-int-allow${local.suffix}"
  security_profile_group  = "//networksecurity.googleapis.com/${google_network_security_security_profile_group.security_profile_group.id}"
  target_secure_tags {
    name  = "tagValues/${google_tags_tag_value.tag_value_purpose["server"].name}"
  }
  match {
    src_ip_ranges = ["10.0.0.0/8"]
    layer4_configs {
      ip_protocol = "tcp"
      ports = [80,443]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "egress_out_rule" {
  action                  = "apply_security_profile_group"
  description             = ""
  direction               = "EGRESS"
  disabled                = false
  enable_logging          = true
  firewall_policy         = google_compute_network_firewall_policy.ngfw_fw_policy.name
  priority                = 8001
  rule_name               = "egress-internet${local.suffix}"
  security_profile_group  = "//networksecurity.googleapis.com/${google_network_security_security_profile_group.security_profile_group.id}"
  target_secure_tags      {
    name = "tagValues/${google_tags_tag_value.tag_value_purpose["client"].name}"
  }
  match {
    dest_ip_ranges = ["0.0.0.0/0"]
    layer4_configs {
      ip_protocol = "tcp"
      ports = [80,443]
    }
  }
}
