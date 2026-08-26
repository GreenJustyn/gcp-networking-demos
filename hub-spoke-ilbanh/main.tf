terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.16"
    }
  }
}

provider "google" {
  project     = var.project-id
  region      = var.region
}
locals {
  suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
  suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
  vpn_spoke = {
    for key, item in setproduct(["vpc-spoke-a", "vpc-spoke-b"],["0","1"]) : "${item[0]}-${item[1]+1}" => {
      vpc = item[0]
      interface = item[1]
      id = key
    }
  }
  vpn_onprem = {
    for key, item in setproduct(["vpc-onprem-a", "vpc-onprem-b"],["0","1"]) : "${item[0]}-${item[1]+1}" => {
      vpc = item[0]
      interface = item[1]
      id = key
    }
  }
}

data "google_compute_zones" "region_availability" {
    region  = var.region
}

resource "random_id" "id" {
	  byte_length = 4
}

resource "google_compute_project_metadata" "project_meta" {
  metadata = {
    enable-oslogin  = "TRUE"
    enable-osconfig = "TRUE"
    enable-guest-attributes = "TRUE"
    "tf-hub-spoke-ilb${local.suffix}" = path.cwd
  }
}

resource "random_password" "vpnpassphrase" {
  length           = 16
  special          = false
}

resource "google_project_service" "apienable" {
  for_each                      = toset(var.apis)
  service                       = each.value
  disable_on_destroy            = false
  disable_dependent_services    = true
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
  depends_on    = [ module.google-infra-vpc ]
  project-id    = var.project-id
}

resource "google_compute_network_peering" "peerings-a-b" {
    for_each                = { for peer in var.peerings : format("%s-%s",peer.network_a,peer.network_b) => peer }
    name                    = "${each.key}${local.suffix}"
    network                 = module.google-infra-vpc.vpcs["${each.value.network_a}"].id
    peer_network            = module.google-infra-vpc.vpcs["${each.value.network_b}"].id
    export_custom_routes    = true
    #depends_on              = [ google_compute_route.route-ilb-internal1 ]
}

resource "google_compute_network_peering" "peerings-b-a" {
    for_each                = { for peer in var.peerings : format("%s-%s",peer.network_b,peer.network_a) => peer }
    name                    = "${each.key}${local.suffix}"
    network                 = module.google-infra-vpc.vpcs["${each.value.network_b}"].id
    peer_network            = module.google-infra-vpc.vpcs["${each.value.network_a}"].id
    import_custom_routes    = true
    #depends_on              = [ google_compute_route.route-ilb-internal1 ]
}

# VPN config #

resource "google_compute_ha_vpn_gateway" "hub_gateway" {
    for_each    = toset(["vpc-spoke-a", "vpc-spoke-b"])
    region      = var.region
    name        = "vpn-${each.value}${local.suffix}"
    network     = module.google-infra-vpc.vpcs[each.value].id
}

resource "google_compute_ha_vpn_gateway" "onprem_gateway" {
    for_each    = toset(["vpc-onprem-a", "vpc-onprem-b"])
    region      = var.region
    name        = "vpn-${each.value}${local.suffix}"
    network     = module.google-infra-vpc.vpcs[each.value].id
}

resource "google_compute_router" "router_hub" {
    for_each    = toset(["vpc-spoke-a", "vpc-spoke-b"])
    name        = "rtr-${each.value}${local.suffix}"
    network     = module.google-infra-vpc.vpcs[each.value].id
    bgp {
        asn = 64514
        advertise_mode    = "CUSTOM"
        advertised_groups = ["ALL_SUBNETS"]
        advertised_ip_ranges {
        range = "10.0.0.0/8"
        }
    }
}

resource "google_compute_router" "router_onprem" {
    for_each    = toset(["vpc-onprem-a", "vpc-onprem-b"])
    name        = "rtr-${each.value}${local.suffix}"
    network     = module.google-infra-vpc.vpcs[each.value].id
    bgp {
        asn = 64515
    }
}

resource "google_compute_vpn_tunnel" "hub_tunnel" {
  for_each              = local.vpn_spoke
  name                  = "tun${each.key}${local.suffix}"
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.hub_gateway[each.value.vpc].id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.onprem_gateway[[for i in var.vpn_peers: i.network_b if i.network_a == each.value.vpc][0]].id
  shared_secret         = random_password.vpnpassphrase.result
  router                = google_compute_router.router_hub[each.value.vpc].id
  vpn_gateway_interface = each.value.interface
}

resource "google_compute_vpn_tunnel" "onprem_tunnel" {
  for_each              = local.vpn_onprem
  name                  = "tun${each.key}${local.suffix}"
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.onprem_gateway[each.value.vpc].id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.hub_gateway[[for i in var.vpn_peers: i.network_a if i.network_b == each.value.vpc][0]].id
  shared_secret         = random_password.vpnpassphrase.result
  router                = google_compute_router.router_onprem[each.value.vpc].id
  vpn_gateway_interface = each.value.interface
}

resource "google_compute_router_interface" "router_hub_intf" {
  for_each   = local.vpn_spoke
  name       = "intf${each.key}${local.suffix}"
  router     = google_compute_router.router_hub[each.value.vpc].name
  region     = var.region
  ip_range   = "${cidrhost(var.vpn_ips[each.value.id],1)}/${split("/", var.vpn_ips[each.value.id])[1]}"
  vpn_tunnel = google_compute_vpn_tunnel.hub_tunnel[each.key].name
}

resource "google_compute_router_interface" "router_onprem_intf" {
  for_each   = local.vpn_onprem
  name       = "intf${each.key}${local.suffix}"
  router     = google_compute_router.router_onprem[each.value.vpc].name
  region     = var.region
  ip_range   = "${cidrhost(var.vpn_ips[each.value.id],2)}/${split("/", var.vpn_ips[each.value.id])[1]}"
  vpn_tunnel = google_compute_vpn_tunnel.onprem_tunnel[each.key].name
}

resource "google_compute_router_peer" "router_hub_peer" {
  for_each                  = local.vpn_spoke
  name                      = "peer${each.key}${local.suffix}"
  router                    = google_compute_router.router_hub[each.value.vpc].name
  region                    = var.region
  peer_ip_address           = split("/",google_compute_router_interface.router_onprem_intf["${[for i in var.vpn_peers: i.network_b if i.network_a == each.value.vpc][0]}-${each.value.interface+1}"].ip_range)[0]
  peer_asn                  = google_compute_router.router_onprem[[for i in var.vpn_peers: i.network_b if i.network_a == each.value.vpc][0]].bgp[0].asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_hub_intf[each.key].name
}

resource "google_compute_router_peer" "router_onprem_peer" {
  for_each                  = local.vpn_onprem
  name                      = "peer${each.key}${local.suffix}"
  router                    = google_compute_router.router_onprem[each.value.vpc].name
  region                    = var.region
  peer_ip_address           = split("/",google_compute_router_interface.router_hub_intf["${[for i in var.vpn_peers: i.network_a if i.network_b == each.value.vpc][0]}-${each.value.interface+1}"].ip_range)[0]
  peer_asn                  = google_compute_router.router_hub[[for i in var.vpn_peers: i.network_a if i.network_b == each.value.vpc][0]].bgp[0].asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_onprem_intf[each.key].name
}

resource "google_compute_instance_template" "gw_template" {
    name_prefix     = "gw-tpl${local.suffix}"
    machine_type = "e2-standard-4"
    region       = var.region
    lifecycle {
        create_before_destroy = true
        ignore_changes = [disk[0].source_image]
    }
    can_ip_forward = true
      metadata = {
        startup-script = "${file("ilb-multinic-debian11.sh")}"
    }
    disk {
        source_image = "debian-cloud/debian-11"
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["hub-ext-subnet"].self_link
        access_config {  }
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["hub-int-subnet"].self_link
    }
}

resource "google_compute_health_check" "https" {
    check_interval_sec  = 10
    unhealthy_threshold = 3
    name    = "hc${local.suffix}"
    https_health_check {
        port                = "443"
        host                = "dns.google"
        port_specification  = "USE_FIXED_PORT"
    }
    log_config {
        enable = true
    }
}

resource "google_compute_region_instance_group_manager" "gw_ig_manager" {
    name                = "gw-ig${local.suffix}"
    base_instance_name  = "gw-ig"
    region              = var.region
    target_size         = "1"
    version {
        instance_template = google_compute_instance_template.gw_template.id
    }
    named_port {
        name = "https"
        port = 443
    }
    auto_healing_policies {
        health_check      = google_compute_health_check.https.id
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
resource "google_compute_region_backend_service" "backend_vpc_internal" {
    name                              = "backend-svc-int${local.suffix}"
    load_balancing_scheme             = "INTERNAL"
    protocol                          = "TCP"
    region                            = var.region
    health_checks                     = [google_compute_health_check.https.self_link]
    connection_draining_timeout_sec   = 10
    network                           = module.google-infra-vpc.vpcs["vpc-hub-int"].self_link
    backend {
        group           = google_compute_region_instance_group_manager.gw_ig_manager.instance_group
        balancing_mode  = "CONNECTION"
    }
}

resource "google_compute_forwarding_rule" "ilb_rule_internal" {
    name                  = "fwdrule-int${local.suffix}"
    network               = module.google-infra-vpc.vpcs["vpc-hub-int"].self_link
    subnetwork            = module.google-infra-vpc.subnets["hub-int-subnet"].self_link
    ip_address            = cidrhost(module.google-infra-vpc.subnets["hub-int-subnet"].ip_cidr_range,100)
    all_ports             = true
    load_balancing_scheme = "INTERNAL"
    ip_protocol           = "TCP"
    region                = var.region
    backend_service       = google_compute_region_backend_service.backend_vpc_internal.self_link
}

/*

resource "google_compute_route" "route_ilb_internal1" {
    for_each      = { for route in var.routes : route.name => route }
    name          = "${each.key}${local.suffix}"
    dest_range    = each.value.cidr
    network       = module.google-infra-vpc.vpcs["${each.value.network}"].self_link
    next_hop_ilb  = google_compute_forwarding_rule.ilb-rule-internal.id
    priority      = try(each.value.priority, "0")
}

resource "google_compute_route" "route_ilb_ext" {
    name          = "untrust${local.suffix}"
    dest_range    = "10.0.0.0/8"
    network       = module.google-infra-vpc.vpcs["vpc-untrust"].self_link
    next_hop_ilb  = google_compute_forwarding_rule.ilb-rule-external.id
    priority      = "900"
}

resource "google_compute_route" "route_igw_tag" {
    name                = "default-tag${local.suffix}"
    dest_range          = "0.0.0.0/0"
    network             = module.google-infra-vpc.vpcs["vpc-trust"].self_link
    next_hop_gateway    = "default-internet-gateway"
    priority            = "700"
    tags                = ["igw${local.suffix}"]
}

#
# Extra for adding apt repo to work with the default route removed
#

resource "google_compute_global_address" "psc_ip" {
  for_each      = { for address in var.psc_ips : address.name => address }
  name          = "${each.key}${local.suffix}"
  address_type  = "INTERNAL"
  purpose       = "PRIVATE_SERVICE_CONNECT"
  network       = module.google-infra-vpc.vpcs["${each.value.network}"].self_link
  address       = each.value.address
}

resource "google_compute_global_forwarding_rule" "default" {
  for_each              = { for fwdrule in var.psc_ips : fwdrule.name => fwdrule }
  name                  = "${each.key}tfda${local.suffix_nodash}"
  target                = "all-apis"
  network               = module.google-infra-vpc.vpcs["${each.value.network}"].self_link
  ip_address            = google_compute_global_address.psc-ip["${each.key}"].id
  load_balancing_scheme = ""
}

resource "google_dns_response_policy" "googleapis_com" {
    provider = google-beta
    response_policy_name = "dns-rp${local.suffix}"
    networks {
      network_url = module.google-infra-vpc.vpcs["vpc-spoke-1"].id
    }
    networks {
      network_url = module.google-infra-vpc.vpcs["vpc-spoke-2"].id
    }
    networks {
      network_url = module.google-infra-vpc.vpcs["vpc-untrust"].id
    }
    networks {
      network_url = module.google-infra-vpc.vpcs["vpc-trust"].id
    }
}

resource "google_dns_response_policy_rule" "googleapis_com" {
    response_policy = google_dns_response_policy.googleapis-com.response_policy_name
    rule_name       = "googleapis-com-rule"
    dns_name        = "*.googleapis.com."

  local_data {
    local_datas {
      name    = "*.googleapis.com."
      type    = "A"
      ttl     = 300
      rrdatas = [google_compute_global_address.psc-ip["spoke1psc1"].address]
    }
  }  
}
resource "google_dns_response_policy_rule" "packagemanager_com" {
    response_policy = google_dns_response_policy.googleapis-com.response_policy_name
    rule_name       = "packagamanager-rule"
    dns_name        = "packages.cloud.google.com."

  local_data {
    local_datas {
      name    = "packages.cloud.google.com."
      type    = "A"
      ttl     = 300
      rrdatas = [google_compute_global_address.psc-ip["spoke1psc1"].address]
    }
  }  

}
*/