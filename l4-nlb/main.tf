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
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 7.7.0"
    }
    google = {
      source = "hashicorp/google"
      version     = "~> 7.7.0"
    }
  }
}

locals {
  suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
  suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
  region_zones = var.all_zones ? {for i in data.google_compute_zones.region_availability[var.regions[0]].names: i => null} : {data.google_compute_zones.region_availability[var.regions[0]].names[0] = null}
}

provider "google" {
  project         = var.project-id
  region          = var.regions[0]
}
provider "google-beta" {
  project         = var.project-id
  region          = var.regions[0]
}

data "google_compute_image" "debian_image" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_zones" "region_availability" {
  for_each    = { for region in var.regions : region => null }
  region      = each.value
  status      = "UP"
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null, "legacy-health-checkers" = null }
  range_type = each.key
}

resource "random_id" "id" {
	byte_length = 2
}

resource "google_project_service" "api_enable" {
    for_each                    = { for api in var.apis : api => null }
    service                     = each.key
    disable_on_destroy          = false
    disable_dependent_services  = true
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "tf-dir${local.suffix}" = path.cwd
  }
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
    project-id  = var.project-id 
}

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    vms         = var.virtual_machines
    namesuffix  = local.suffix_nodash
    project-id  = var.project-id 
    depends_on = [ module.google-infra-vpc ]
}

resource "google_compute_region_health_check" "default" {
  name               = "hc-regional${local.suffix}"
  check_interval_sec = 1
  timeout_sec        = 1
  http_health_check {
    port_specification = "USE_SERVING_PORT"
    request_path       = "/"
  }
}

resource "google_compute_instance_template" "default" {
    name_prefix     = "elb-tpl${local.suffix}"
    machine_type    = "e2-micro"
    lifecycle {
        create_before_destroy = true
        ignore_changes        = [disk[0].source_image]
    }
      metadata = {
        startup-script = templatefile("./debian-svr.sh.tftpl", { })
    }
    disk {
        source_image = data.google_compute_image.debian_image.self_link
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["sub-lbtest"].self_link
        # access_config { } # Comment out for no public IP
    }
}

resource "google_compute_instance_from_template" "webservers" {
  for_each  = local.region_zones
  name      = "web-inst${local.suffix}-${each.key}"
  zone      = each.key
  source_instance_template = google_compute_instance_template.default.self_link_unique
  depends_on = [ google_compute_router_nat.nat_auto ]
}

resource "google_compute_instance_group" "webservers" {
  for_each    = local.region_zones
  name        = "web-ig${local.suffix}-${each.key}"
  instances = [
    google_compute_instance_from_template.webservers[each.key].self_link
  ]
  named_port {
    name = "http"
    port = "80"
  }
  zone = each.key
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_backend_service" "nlb_bs" {
    name                    = "bs-nlb${local.suffix}"
    region                  = var.regions[0]
    port_name               = "http"
    protocol                = "TCP"
    timeout_sec             = 10
    health_checks           = [google_compute_region_health_check.default.id]
    load_balancing_scheme   = "EXTERNAL"
    dynamic "backend" {
      for_each  = google_compute_instance_group.webservers
      content {
        group           = backend.value.self_link
        balancing_mode  = "CONNECTION"
      }
    }
}

resource "google_compute_address" "default" {
    name      = "${var.regions[0]}-ip${local.suffix}"
    region    = var.regions[0]
}

resource "google_compute_forwarding_rule" "default" {
    name                  = "fr-${var.regions[0]}${local.suffix}"
    region                = var.regions[0]
    port_range            = 80
    ip_address            = google_compute_address.default.address
    backend_service       = google_compute_region_backend_service.nlb_bs.self_link
}

#Firewall

resource "google_compute_network_firewall_policy" "fw_policy" {
    name        = "fwpolicy${local.suffix}"
    description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
  for_each          = module.google-infra-vpc.vpcs
  name              = "assoc-${each.value.name}"
  attachment_target = each.value.id
  firewall_policy   = google_compute_network_firewall_policy.fw_policy.name
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

resource "google_compute_network_firewall_policy_rule" "hc_rule" {
  action                  = "allow"
  description             = ""
  direction               = "INGRESS"
  disabled                = false
  enable_logging          = false
  firewall_policy         = google_compute_network_firewall_policy.fw_policy.name
  priority                = 1200
  rule_name               = "hc-allow${local.suffix}"
  match {
    src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["legacy-health-checkers"].cidr_blocks_ipv4
    layer4_configs {
      ip_protocol = "tcp"
      ports = [80,443]
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

# NAT

resource "google_compute_router" "nat_router" {
  for_each  = module.google-infra-vpc.vpcs
  name      = "router${each.value.name}"
  network   = each.value.id
}

resource "google_compute_router_nat" "nat_auto" {
  for_each                            = google_compute_router.nat_router  
  name                                = "nat-${each.value.name}"
  router                              = each.value.name
  region                              = each.value.region
  nat_ip_allocate_option              = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat  = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# PSC

resource "google_compute_region_backend_service" "psc_bs" {
    name                    = "bs-psc${local.suffix}"
    region                  = var.regions[0]
    protocol                = "TCP"
    timeout_sec             = 10
    health_checks           = [google_compute_region_health_check.default.id]
    load_balancing_scheme   = "INTERNAL"
    dynamic "backend" {
      for_each  = google_compute_instance_group.webservers
      content {
        group           = backend.value.self_link
        balancing_mode  = "CONNECTION"
      }
    }
}

resource "google_compute_forwarding_rule" "psc_producer_fr" {
    name                    = "psc-producer-fr${local.suffix}"
    load_balancing_scheme   = "INTERNAL"
    backend_service         = google_compute_region_backend_service.psc_bs.id
    all_ports               = true
    subnetwork              = [for key,val in module.google-infra-vpc.subnets: val.id if strcontains(key, "sub-lb") && val.purpose == "PRIVATE"][0]
}

resource "google_compute_service_attachment" "producer_service_attachment" {
    name                    = "psc-attach${local.suffix}"
    connection_preference   = "ACCEPT_AUTOMATIC"
    enable_proxy_protocol   = false
    nat_subnets             = [[for key,val in module.google-infra-vpc.subnets: val.id if strcontains(key, "producer") && val.purpose == "PRIVATE_SERVICE_CONNECT"][0]]
    target_service          = google_compute_forwarding_rule.psc_producer_fr.id
}

# L4 ILB Consumer

resource "google_compute_address" "psc_ilb_consumer_address" {
    name            = "psc-consumer-addr${local.suffix}"
    subnetwork      = [for key,val in module.google-infra-vpc.subnets: val.id if strcontains(key, "consumer") && val.purpose == "PRIVATE"][0]
    address_type    = "INTERNAL"
}

resource "google_compute_forwarding_rule" "psc_ilb_consumer" {
    name                    = "psc-consumer-fr${local.suffix}"
    target                  = google_compute_service_attachment.producer_service_attachment.id
    load_balancing_scheme   = ""
    network                 = [for i,j in module.google-infra-vpc.vpcs: j.id if strcontains(i, "consumer")][0]
    ip_address              = google_compute_address.psc_ilb_consumer_address.id
    allow_psc_global_access = true
}