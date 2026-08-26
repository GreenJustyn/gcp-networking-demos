terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 7.28"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 7.28"
    }
  }
}

locals {
  suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
  suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
  full_region_list    = toset(distinct(flatten([for val in var.vpcs:  val.subnets[*].region])))
  region_zones = var.all_zones ? {for i in data.google_compute_zones.region_availability[var.region].names: i => null} : {data.google_compute_zones.region_availability[var.region].names[0] = null}
}

provider "google" {
    project     = var.project-id
    region      = var.region
}

resource "random_id" "id" {
    byte_length = 2
}

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

resource "google_project_service" "apienable" {
  for_each = toset(var.apis)
  service     = each.value
  disable_on_destroy = false
  disable_dependent_services = true
}

resource "google_compute_project_metadata" "project_meta" {
  metadata = {
    enable-oslogin  = "TRUE"
    "ncc-vpc-spokes${local.suffix}" = path.cwd
  }
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    project-id  = var.project-id
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    project-id  = var.project-id
    fw_rules    = var.fw_rules
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    project-id  = var.project-id
    vms         = var.virtual_machines
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

resource "google_compute_instance" "server_instance" {
  name         = "server${local.suffix}"
  machine_type = "e2-micro"
  zone         = random_shuffle.gcp_zones[module.google-infra-vpc.subnets["sub-primary-asia"].region].result[0]
  metadata            = {
      startup-script  = templatefile("./debian-server.sh.tftpl", { })
  }
  tags = ["allow-ssh${local.suffix}"]
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
  network_interface {
    subnetwork  = module.google-infra-vpc.subnets["sub-primary-asia"].self_link
    access_config { }
  }
  service_account {
    email = data.google_compute_default_service_account.default_sa.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
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
    auto_accept_projects = distinct(values(module.google-infra-vpc.vpcs)[*].project)
  }
}

resource "google_network_connectivity_spoke" "spokes" {
  for_each        = module.google-infra-vpc.vpcs
  name = each.value.name
  project = each.value.project
  location = "global"
  description = "description${local.suffix}"
  hub = google_network_connectivity_hub.peering_hub.id
  linked_vpc_network {
    uri = each.value.self_link
    include_export_ranges = [for subnet in flatten([for vpc in var.vpcs: vpc.subnets if vpc.network == each.key && vpc.project-id == each.value.project]): subnet.cidr_block if try(subnet.ncc_include_export,false) == true]
    exclude_export_ranges = [for subnet in flatten([for vpc in var.vpcs: vpc.subnets if vpc.network == each.key && vpc.project-id == each.value.project]): subnet.cidr_block if try(subnet.ncc_exclude_export,false) == true]
  }
}

resource "google_compute_network_firewall_policy" "fw_policy" {
  name        = "fwpolicy${local.suffix}"
  description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
  for_each          = module.google-infra-vpc.vpcs
  name              = "fwpolicyassoc${local.suffix}-${each.key}"
  attachment_target = each.value.id
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
    src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["health-checkers"].cidr_blocks_ipv4
    layer4_configs {
      ip_protocol = "tcp"
      ports = [80,443]
    }
  }
}

#
### L4 ILB ###
#

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
      subnetwork = module.google-infra-vpc.subnets["sub-secondary-asia"].self_link
      # access_config { } # Comment out for no public IP
  }
}

resource "google_compute_region_instance_group_manager" "default" {
  name = "web-igm"
  base_instance_name         = "web-ig"
  region                     = var.region
  #distribution_policy_zones  = ["us-central1-a", "us-central1-f"]
  version {
    instance_template = google_compute_instance_template.default.self_link_unique
  }
  target_size  = 3
  named_port {
    name = "http"
    port = "80"
  }
}

#resource "google_compute_instance_from_template" "webservers" {
#  for_each  = local.region_zones
#  name      = "web-inst${local.suffix}-${each.key}"
#  zone      = each.key
#  source_instance_template = google_compute_instance_template.default.self_link_unique
#  depends_on = [ google_compute_router_nat.nat_auto ]
#}

#resource "google_compute_instance_group" "webservers" {
#  for_each    = local.region_zones
#  name        = "web-ig${local.suffix}-${each.key}"
#  instances = [
#    google_compute_instance_from_template.webservers[each.key].self_link
#  ]
#  named_port {
#    name = "http"
#    port = "80"
#  }
#  zone = each.key
#  lifecycle {
#    create_before_destroy = true
#  }
#}

resource "google_compute_region_backend_service" "nlb_bs" {
    name                    = "rbs-nlb${local.suffix}"
    region                  = var.region
    protocol                = "TCP"
    timeout_sec             = 10
    health_checks           = [google_compute_region_health_check.default.id]
    load_balancing_scheme   = "INTERNAL"
    backend {
        group           = google_compute_region_instance_group_manager.default.instance_group
        balancing_mode  = "CONNECTION"
    }
}

resource "google_compute_address" "default" {
    name      = "${var.region}-ip${local.suffix}"
    region    = var.region
}

resource "google_compute_forwarding_rule" "default" {
    name                  = "fr-${var.region}${local.suffix}"
    region                = var.region
    all_ports             = true
    allow_global_access   = true
    load_balancing_scheme = "INTERNAL"
    backend_service       = google_compute_region_backend_service.nlb_bs.self_link
    subnetwork            = module.google-infra-vpc.subnets["sub-secondary-asia"].self_link
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


## SWP Config ##

resource "google_network_security_gateway_security_policy" "swp_gsp" {
    location        = var.region
    name            = "swp-gsp${local.suffix}"
    #tls_inspection_policy = google_network_security_tls_inspection_policy.default[each.key].id
}

resource "google_network_security_gateway_security_policy_rule" "swp_allow" {
    location                = var.region
    name                    = "swprule${local.suffix}-${var.region}"
    gateway_security_policy = google_network_security_gateway_security_policy.swp_gsp.name
    enabled                 = true
    priority                = 2000
    session_matcher         = "host().endsWith('com')"
    tls_inspection_enabled  = false
    basic_profile           = "ALLOW"
}

resource "google_network_services_gateway" "default" {
    location                = var.region
    name                    = "gw${local.suffix}-${var.region}"
    type                    = "SECURE_WEB_GATEWAY"
    ports                   = ["80", "443"]
    scope                   = "scope${local.suffix}"
    gateway_security_policy = google_network_security_gateway_security_policy.swp_gsp.id
    network                 = values(module.google-infra-vpc.vpcs)[0].id
    subnetwork              = values(module.google-infra-vpc.subnets)[0].id
    delete_swg_autogen_router_on_destroy = true
    routing_mode            = "NEXT_HOP_ROUTING_MODE"
}
/*
resource "google_compute_route" "default_to_swp" {
    name            = "swp-default${local.suffix}-${each.key}"
    dest_range      = "0.0.0.0/0"
    network         = google_network_services_gateway.default.network
    next_hop_ilb    = google_network_services_gateway.default[each.key].addresses[0]
    priority        = 1
}
*/