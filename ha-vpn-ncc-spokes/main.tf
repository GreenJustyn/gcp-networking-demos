#Creates a NCC hub with 2xVPC Spokes, a HA-VPN connected to a remote VPC to simulate on-prem.
#You can ping across from the on-prem VPC to the VPC spokes using the dynamic route exchange feature with NCC.
#Bug: Inbound server policy's IP address doesn't get created automatically.

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.21"
    }
  }
}

provider "google" {
  project     = var.project-id
  region      = var.region-1
}
locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

data "google_compute_default_service_account" "default_sa" {
}

resource "random_id" "id" {
	  byte_length = 4
}
resource "random_password" "vpnpassphrase" {
  length           = 16
  special          = false
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
    enable-osconfig = "TRUE"
    enable-guest-attributes = "TRUE"
    "tf-ha-vpn-ncc${local.suffix}" = path.cwd
  }
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
  source      = "../modules/google-infra-vms"
  vms         = var.virtual_machines
  namesuffix  = local.suffix_nodash
  depends_on = [ module.google-infra-vpc ]
  project-id = var.project-id
}

#VPN

resource "google_compute_ha_vpn_gateway" "hub_gateway" {
  region   = var.region-1
  name     = "hub-vpn1${local.suffix}"
  network  = module.google-infra-vpc.vpcs["vpc-hub"].id
}
resource "google_compute_ha_vpn_gateway" "onprem_gateway" {
  region   = var.region-1
  name     = "onprem-vpn1${local.suffix}"
  network  = module.google-infra-vpc.vpcs["vpc-onprem"].id
}

resource "google_compute_router" "router_hub" {
  name     = "ha-vpn-hub-rtr${local.suffix}"
  network  = module.google-infra-vpc.vpcs["vpc-hub"].id
  bgp {
    asn = 64514
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]
    advertised_ip_ranges {
      range = "10.20.0.0/22"
    }
  }
}

resource "google_compute_router" "router_onprem" {
  name     = "ha-vpn-onprem-rtr${local.suffix}"
  network  = module.google-infra-vpc.vpcs["vpc-onprem"].id
  bgp {
    asn = 64515
  }
}

resource "google_compute_vpn_tunnel" "hub_tunnel" {
  for_each              = toset(["0","1"])
  name                  = "ha-vpn-hub-tun${each.value+1}${local.suffix}"
  region                = var.region-1
  vpn_gateway           = google_compute_ha_vpn_gateway.hub_gateway.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.onprem_gateway.id
  shared_secret         = random_password.vpnpassphrase.result
  router                = google_compute_router.router_hub.id
  vpn_gateway_interface = each.value
}

resource "google_compute_vpn_tunnel" "onprem_tunnel" {
  for_each              = toset(["0","1"])
  name                  = "ha-vpn-onprem-tun${each.value+1}${local.suffix}"
  region                = var.region-1
  vpn_gateway           = google_compute_ha_vpn_gateway.onprem_gateway.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.hub_gateway.id
  shared_secret         = random_password.vpnpassphrase.result
  router                = google_compute_router.router_onprem.id
  vpn_gateway_interface = each.value
}


resource "google_compute_router_interface" "router_hub_intf" {
  for_each   = toset(["0","1"])
  name       = "router-hub-intf${each.value+1}${local.suffix}"
  router     = google_compute_router.router_hub.name
  region     = var.region-1
  ip_range   = "${cidrhost(var.vpn_ips[each.value],1)}/${split("/", var.vpn_ips[each.value])[1]}"
  vpn_tunnel = google_compute_vpn_tunnel.hub_tunnel[each.value].name
}

resource "google_compute_router_peer" "router_hub_peer" {
  for_each                  = toset(["0","1"])
  name                      = "router-hub-peer${each.value+1}${local.suffix}"
  router                    = google_compute_router.router_hub.name
  region                    = var.region-1
  peer_ip_address           = split("/",google_compute_router_interface.router_onprem_intf[each.value].ip_range)[0]
  peer_asn                  = google_compute_router.router_onprem.bgp[0].asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_hub_intf[each.value].name
}

resource "google_compute_router_interface" "router_onprem_intf" {
  for_each   = toset(["0","1"])
  name       = "router-onprem-intf${each.value+1}${local.suffix}"
  router     = google_compute_router.router_onprem.name
  region     = var.region-1
  ip_range   = "${cidrhost(var.vpn_ips[each.value],2)}/${split("/", var.vpn_ips[each.value])[1]}"
  vpn_tunnel = google_compute_vpn_tunnel.onprem_tunnel[each.value].name
}

resource "google_compute_router_peer" "router_onprem_peer" {
  for_each                  = toset(["0","1"])
  name                      = "router-onprem-peer${each.value+1}${local.suffix}"
  router                    = google_compute_router.router_onprem.name
  region                    = var.region-1
  peer_ip_address           = split("/",google_compute_router_interface.router_hub_intf[each.value].ip_range)[0]
  peer_asn                  = google_compute_router.router_hub.bgp[0].asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_onprem_intf[each.value].name
}

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

resource "google_network_connectivity_spoke" "vpc_spokes" {
  #for_each        = module.google-infra-vpc.vpcs
  for_each         = toset(["vpc-nccpeer", "vpc-hub"])
  # name = each.value.name
  name             = "${module.google-infra-vpc.vpcs[each.key].name}${local.suffix}"
  project          = module.google-infra-vpc.vpcs[each.key].project
  #project = each.value.project
  location          = "global"
  description       = "${each.key}-${local.suffix}"
  hub               = google_network_connectivity_hub.peering_hub.id
  linked_vpc_network {
    uri = module.google-infra-vpc.vpcs[each.key].self_link
  }
}

resource "google_network_connectivity_spoke" "vpn_spokes" {
  name              = "vpn-tunnel-spoke${local.suffix}"
  location          = var.region-1
  description       = "descr${local.suffix}"
  hub               = google_network_connectivity_hub.peering_hub.id
  linked_vpn_tunnels {
    uris                       = values(google_compute_vpn_tunnel.hub_tunnel)[*].self_link
    site_to_site_data_transfer = false
    include_import_ranges      = ["ALL_IPV4_RANGES"]
  }
}

resource "google_dns_managed_zone" "default" {
  name        = "woot-zone${local.suffix}"
  dns_name    = "onaws.net."
  description = local.suffix_nodash
  visibility = "private"
  private_visibility_config {
    networks {
      network_url = module.google-infra-vpc.vpcs["vpc-nccpeer"].id
    }
  }
}

resource "google_dns_record_set" "default" {
  name         = "woot.${google_dns_managed_zone.default.dns_name}"
  managed_zone = google_dns_managed_zone.default.name
  type         = "A"
  ttl          = 300
  rrdatas = ["10.1.2.3"]
}

resource "google_dns_policy" "default" {
  name                      = "default${local.suffix}"
  enable_logging            = true
  enable_inbound_forwarding = true
  networks {
    network_url = module.google-infra-vpc.vpcs["vpc-nccpeer"].id
  }
}

resource "google_dns_managed_zone" "peering-zone" {
  name        = "peering-zone${local.suffix}"
  dns_name    = "."
  description = "dsd"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = module.google-infra-vpc.vpcs["vpc-hub"].id
    }
  }

  peering_config {
    target_network {
      network_url = module.google-infra-vpc.vpcs["vpc-nccpeer"].id
    }
  }
}
/*
resource "google_compute_network_peering" "hub-isolated" {
  name                  = "hub-isol${local.suffix}"
  network               = module.google-infra-vpc.vpcs["vpc-hub"].self_link
  peer_network          = module.google-infra-vpc.vpcs["vpc-nccpeer"].self_link
  export_custom_routes  = true
}
resource "google_compute_network_peering" "isolated-hub" {
  name                  = "isol-hub${local.suffix}"
  network               = module.google-infra-vpc.vpcs["vpc-nccpeer"].self_link
  peer_network          = module.google-infra-vpc.vpcs["vpc-hub"].self_link
  import_custom_routes  = true
}
*/