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

#To-do make the [ for i in module.google-infra-vpc.subnets: ] etc into local variable

terraform {
  required_providers {
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 6.38"
    }
    google = {
      source = "hashicorp/google"
      version     = "~> 6.38"
    }
  }
}

provider "google" {
  project         = var.project-id
  region          = var.region
  billing_project = var.project-id
}

resource "random_id" "id" {
	byte_length = 2
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

data "google_compute_image" "debian-image" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_zones" "region_availability" {
    for_each    = local.region_map
    region      = each.key
}
data "google_compute_default_service_account" "default_sa" { }

locals {
    full_region_list    = ["asia-southeast1"]
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
    region_map = {for i in distinct(flatten([for val in var.vpcs:  val.subnets[*].region])): i => null }
    asdf = {for combo in setproduct(keys(local.region_map), keys(module.google-infra-vpc.vpcs)): "${combo[0]}_${combo[1]}" => {
        region  : combo[0]
        vpc     : module.google-infra-vpc.vpcs[combo[1]]
    } }
}

resource "random_password" "vpnpassphrase" {
    length           = 16
    special          = false
}

resource "random_shuffle" "gcp_zones" {
    for_each        = { for region in data.google_compute_zones.region_availability: region.region => region.names }
    input           = [ for zone in each.value : zone ]
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "cwd${local.suffix}" = path.cwd
  }
}

resource "google_project_service" "api_enable" {
    for_each                    = { for api in var.apis : api => null }
    service                     = each.key
    disable_on_destroy          = false
    disable_dependent_services  = true
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    project-id  = var.project-id
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    project-id  = var.project-id
    vms         = var.virtual_machines
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

resource "google_compute_instance" "appliance_instance" {
    for_each            = {for i,j in setproduct(keys(local.region_map),toset(["1","2"])): "${i[0]}-inst${i[1]}" => j}
    name                = "inst${local.suffix}-${each.key}"
    machine_type        = "n1-standard-4"
    zone                = random_shuffle.gcp_zones[each.value[0]].result[each.value[1]-1]
    can_ip_forward      = true
    labels = {
        priority = each.value[1]
    }
    metadata_startup_script = templatefile("./multinic-debian.sh.tftpl", {
        cr_ext_ip_pri       = google_compute_router_interface.ncc_ext_intf_pri[each.value[0]].private_ip_address
        cr_ext_ip_sec       = google_compute_router_interface.ncc_ext_intf_sec[each.value[0]].private_ip_address
        cr_int_ip_pri       = google_compute_router_interface.ncc_int_intf_pri[each.value[0]].private_ip_address
        cr_int_ip_sec       = google_compute_router_interface.ncc_int_intf_sec[each.value[0]].private_ip_address
        appliance_ext_asn   = var.cr_base_asn+110
        appliance_int_asn   = var.cr_base_asn+10
        cr_ext_asn          = google_compute_router.cr_external[each.value[0]].bgp[0].asn
        #cr_ext_asn          = google_compute_router.nat_router["${each.value[0]}-vpc-external"].bgp[0].asn
        cr_int_asn          = google_compute_router.cr_internal[each.value[0]].bgp[0].asn
        med_priority        = 100+each.value[1]
        })
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork  = [ for i in module.google-infra-vpc.subnets: i.self_link if i.region == each.value[0] && strcontains(i.name,"external")][0]
        network_ip  = cidrhost([ for i in module.google-infra-vpc.subnets: i.ip_cidr_range if i.region == each.value[0] && strcontains(i.name,"external")][0],80+each.value[1])
    }
    network_interface {
        subnetwork  = [ for i in module.google-infra-vpc.subnets: i.self_link if i.region == each.value[0] && strcontains(i.name,"internal")][0]
        network_ip  = cidrhost([ for i in module.google-infra-vpc.subnets: i.ip_cidr_range if i.region == each.value[0] && strcontains(i.name,"internal")][0],80+each.value[1])
    }
    service_account {
        email = data.google_compute_default_service_account.default_sa.email
        scopes = ["cloud-platform"]
    }
}

#
# NCC Configs
#

resource "google_network_connectivity_hub" "hub_external" {
    project = var.project-id
    name    = "hub-external${local.suffix}"
}

resource "google_network_connectivity_hub" "hub_internal" {
    project = var.project-id
    name    = "hub-internal${local.suffix}"
}

resource "google_network_connectivity_spoke" "external_spoke" {
    for_each    = local.region_map
    name        = "spoke-ext-nva-${each.key}${local.suffix}"
    location    = each.key
    hub         = google_network_connectivity_hub.hub_external.id
    linked_router_appliance_instances {
        dynamic "instances" {
            for_each = { for i in google_compute_instance.appliance_instance: i.self_link => i if startswith(i.zone,each.key)}
            content {
                virtual_machine = instances.key
                ip_address = instances.value.network_interface[0].network_ip
            }
        }
        site_to_site_data_transfer = true
    }
}

resource "google_network_connectivity_spoke" "internal_spoke" {
    for_each    = local.region_map
    name        = "spoke-int-nva${each.key}${local.suffix}"
    location    = each.key
    hub         =  google_network_connectivity_hub.hub_internal.id
    linked_router_appliance_instances {
        dynamic "instances" {
            for_each = { for i in google_compute_instance.appliance_instance: i.self_link => i if startswith(i.zone,each.key)}
            content {
                virtual_machine = instances.key
                ip_address = instances.value.network_interface[1].network_ip
            }
        }
        site_to_site_data_transfer = true
    }
}

resource "google_compute_router" "cr_external" {
    for_each    = local.region_map
    name        = "cr-ext-${each.key}${local.suffix}"
    region      = each.key
    network     = module.google-infra-vpc.vpcs.vpc-external.self_link
    bgp {
        asn = var.cr_base_asn+100
    }
}

resource "google_compute_router" "cr_internal" {
    for_each    = local.region_map
    name        = "cr-int-${each.key}${local.suffix}"
    region      = each.key
    network     = module.google-infra-vpc.vpcs.vpc-internal.self_link
    bgp {
        asn = var.cr_base_asn
        advertise_mode    = "CUSTOM"
        advertised_groups = ["ALL_SUBNETS"]
        advertised_ip_ranges {
        range = module.google-infra-vpc.subnets["vpc-peered-subnet"].ip_cidr_range
        }
    }
}

resource "google_compute_router" "cr_remote" {
    for_each = local.region_map
    name     = "cr-remote-${each.key}${local.suffix}"
    region   = each.key
    network  = module.google-infra-vpc.vpcs.vpc-remote.self_link
    bgp {
        asn = var.cr_base_asn+200
    }
}

resource "google_compute_router_interface" "ncc_ext_intf_pri" {
    for_each            = google_compute_router.cr_external
    name                = "ncc-ext-intf-pri-${each.key}${local.suffix}"
    region              = each.value.region
    router              = each.value.name
    subnetwork          = [ for i in module.google-infra-vpc.subnets: i.self_link if i.region == each.value.region && i.network == each.value.network][0]
    private_ip_address  = cidrhost([ for i in module.google-infra-vpc.subnets: i.ip_cidr_range if i.region == each.value.region && i.network == each.value.network][0],55)
}

resource "google_compute_router_interface" "ncc_ext_intf_sec" {
    for_each            = google_compute_router.cr_external
    name                = "ncc-ext-intf-sec-${each.key}${local.suffix}"
    region              = each.value.region
    router              = each.value.name
    subnetwork          = [ for i in module.google-infra-vpc.subnets: i.self_link if i.region == each.value.region && i.network == each.value.network][0]
    private_ip_address  = cidrhost([ for i in module.google-infra-vpc.subnets: i.ip_cidr_range if i.region == each.value.region && i.network == each.value.network][0],60)
    redundant_interface = google_compute_router_interface.ncc_ext_intf_pri[each.key].name
}

resource "google_compute_router_peer" "peer_ext" {
    for_each                    = google_compute_instance.appliance_instance
    name                        = "ncc-ext-peer${local.suffix}-${each.key}-${each.value.labels.priority}"
    router                      = google_compute_router.cr_external[replace(each.value.zone,"/-.$/","")].name
    region                      = replace(each.value.zone,"/-.$/","")
    interface                   = each.value.labels.priority %2 == 0 ? google_compute_router_interface.ncc_ext_intf_pri[replace(each.value.zone,"/-.$/","")].name : google_compute_router_interface.ncc_ext_intf_sec[replace(each.value.zone,"/-.$/","")].name
    #interface                   = google_compute_router_interface.ncc_ext_intf_pri[replace(each.value.zone,"/-.$/","")].name
    router_appliance_instance   = each.value.self_link
    peer_asn                    = var.cr_base_asn+110
    peer_ip_address             = each.value.network_interface[0].network_ip
    depends_on                  = [
        google_network_connectivity_spoke.external_spoke
    ]
}

/*
resource "google_compute_router_peer" "peer_ext_primary" {
    for_each                    = google_compute_instance.appliance_instance
    name                        = "ncc-ext-peer-primary${local.suffix}-${each.key}"
    router                      = google_compute_router.cr_external[replace(each.value.zone,"/-.$/","")].name
    region                      = replace(each.value.zone,"/-.$/","")
    interface                   = google_compute_router_interface.ncc_ext_intf_pri[replace(each.value.zone,"/-.$/","")].name
    router_appliance_instance   = each.value.self_link
    peer_asn                    = var.cr_base_asn+110
    peer_ip_address             = each.value.network_interface[0].network_ip
    depends_on                  = [
        google_network_connectivity_spoke.external_spoke
    ]
}

resource "google_compute_router_peer" "peer_ext_secondary" {
    for_each                    = google_compute_instance.appliance_instance
    name                        = "ncc-ext-peer-secondary${local.suffix}-${each.key}"
    router                      = google_compute_router.cr_external[replace(each.value.zone,"/-.$/","")].name
    region                      = replace(each.value.zone,"/-.$/","")
    interface                   = google_compute_router_interface.ncc_ext_intf_sec[replace(each.value.zone,"/-.$/","")].name
    router_appliance_instance   = each.value.self_link
    peer_asn                    = var.cr_base_asn+110
    peer_ip_address             = each.value.network_interface[0].network_ip
    depends_on                  = [
        google_network_connectivity_spoke.external_spoke
    ]
}
*/
resource "google_compute_router_interface" "ncc_int_intf_pri" {
    for_each            = google_compute_router.cr_internal
    name                = "ncc-int-intf-pri-${each.key}${local.suffix}"
    region              = each.value.region
    router              = each.value.name
    subnetwork          = [ for i in module.google-infra-vpc.subnets: i.self_link if i.region == each.value.region && i.network == each.value.network][0]
    private_ip_address  = cidrhost([ for i in module.google-infra-vpc.subnets: i.ip_cidr_range if i.region == each.value.region && i.network == each.value.network][0],55)
}

resource "google_compute_router_interface" "ncc_int_intf_sec" {
    for_each            = google_compute_router.cr_internal
    name                = "ncc-int-intf-sec-${each.key}${local.suffix}"
    region              = each.value.region
    router              = each.value.name
    subnetwork          = [ for i in module.google-infra-vpc.subnets: i.self_link if i.region == each.value.region && i.network == each.value.network][0]
    private_ip_address  = cidrhost([ for i in module.google-infra-vpc.subnets: i.ip_cidr_range if i.region == each.value.region && i.network == each.value.network][0],60)
    redundant_interface = google_compute_router_interface.ncc_int_intf_pri[each.key].name
}

resource "google_compute_router_peer" "peer_int_primary" {
    for_each                    = google_compute_instance.appliance_instance
    name                        = "ncc-int-peer-primary${local.suffix}-${each.key}"
    router                      = google_compute_router.cr_internal[replace(each.value.zone,"/-.$/","")].name
    region                      = replace(each.value.zone,"/-.$/","")
    interface                   = each.value.labels.priority %2 == 0 ? google_compute_router_interface.ncc_int_intf_pri[replace(each.value.zone,"/-.$/","")].name : google_compute_router_interface.ncc_int_intf_sec[replace(each.value.zone,"/-.$/","")].name
    router_appliance_instance   = each.value.self_link
    peer_asn                    = var.cr_base_asn+10
    peer_ip_address             = each.value.network_interface[1].network_ip
    depends_on                  = [
        google_network_connectivity_spoke.internal_spoke
    ]
}

/*
resource "google_compute_router_peer" "peer_int_primary" {
    for_each                    = google_compute_instance.appliance_instance
    name                        = "ncc-int-peer-primary${local.suffix}-${each.key}"
    router                      = google_compute_router.cr_internal[replace(each.value.zone,"/-.$/","")].name
    region                      = replace(each.value.zone,"/-.$/","")
    interface                   = google_compute_router_interface.ncc_int_intf_pri[replace(each.value.zone,"/-.$/","")].name
    router_appliance_instance   = each.value.self_link
    peer_asn                    = var.cr_base_asn+10
    peer_ip_address             = each.value.network_interface[1].network_ip
    depends_on                  = [
        google_network_connectivity_spoke.internal_spoke
    ]
}

resource "google_compute_router_peer" "peer_int_secondary" {
    for_each                    = google_compute_instance.appliance_instance
    name                        = "ncc-int-peer-secondary${local.suffix}-${each.key}"
    router                      = google_compute_router.cr_internal[replace(each.value.zone,"/-.$/","")].name
    region                      = replace(each.value.zone,"/-.$/","")
    interface                   = google_compute_router_interface.ncc_int_intf_sec[replace(each.value.zone,"/-.$/","")].name
    router_appliance_instance   = each.value.self_link
    peer_asn                    = var.cr_base_asn+10
    peer_ip_address             = each.value.network_interface[1].network_ip
    depends_on                  = [
        google_network_connectivity_spoke.internal_spoke
    ]
}
*/
#
# HA VPN to remote VPC
#


resource "google_compute_ha_vpn_gateway" "hub_gateway" {
    for_each    = local.region_map
    region      = each.key
    name        = "hub-gw-${each.key}${local.suffix}"
    network     = module.google-infra-vpc.vpcs.vpc-external.self_link
}

resource "google_compute_ha_vpn_gateway" "onprem_gateway" {
    for_each    = local.region_map
    region      = each.key
    name        = "onprem-gw-${each.key}${local.suffix}"
    network     = module.google-infra-vpc.vpcs.vpc-remote.self_link
}

resource "google_compute_vpn_tunnel" "hub_tunnel" {
  for_each              = {for i,j in setproduct(keys(local.region_map),toset(["0","1"])): "${i[0]}_tun${i[1]}" => j}
  name                  = "ha-vpn-ext-${each.value[0]}-${each.value[1]+1}${local.suffix}"
  region                = each.value[0]
  vpn_gateway           = google_compute_ha_vpn_gateway.hub_gateway[each.value[0]].id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.onprem_gateway[each.value[0]].id
  shared_secret         = random_password.vpnpassphrase.result
  #router                = google_compute_router.cr_external[each.value[0]].id
  router                = google_compute_router.nat_router["${each.value[0]}-vpc-external"].id
  vpn_gateway_interface = each.value[1]
}

resource "google_compute_vpn_tunnel" "onprem_tunnel" {
  for_each              = {for i,j in setproduct(keys(local.region_map),toset(["0","1"])): "${i[0]}_tun${i[1]}" => j}
  name                  = "ha-vpn-rem-${each.value[0]}-${each.value[1]+1}${local.suffix}"
  region                = each.value[0]
  vpn_gateway           = google_compute_ha_vpn_gateway.onprem_gateway[each.value[0]].id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.hub_gateway[each.value[0]].id
  shared_secret         = random_password.vpnpassphrase.result
  router                = google_compute_router.cr_remote[each.value[0]].id
  vpn_gateway_interface = each.value[1]
}

resource "google_compute_router_interface" "router_hub_intf" {
    for_each   = google_compute_vpn_tunnel.hub_tunnel
    name       = "router-hub-${each.value.region}-intf${each.value.vpn_gateway_interface}${local.suffix}"
    router     = basename(each.value.router)
    region     = each.value.region
    ip_range   = "${cidrhost(var.vpn_ips[index(keys(google_compute_vpn_tunnel.hub_tunnel),each.key)],1)}/${split("/", var.vpn_ips[index(keys(google_compute_vpn_tunnel.hub_tunnel),each.key)])[1]}"
    vpn_tunnel = each.value.name
}

resource "google_compute_router_interface" "router_onprem_intf" {
  for_each   = google_compute_vpn_tunnel.onprem_tunnel
  name       = "router-onprem-${each.value.region}-intf${each.value.vpn_gateway_interface}${local.suffix}"
  router     = basename(each.value.router)
  region     = each.value.region
  ip_range   = "${cidrhost(var.vpn_ips[index(keys(google_compute_vpn_tunnel.onprem_tunnel),each.key)],2)}/${split("/", var.vpn_ips[index(keys(google_compute_vpn_tunnel.onprem_tunnel),each.key)])[1]}"
  vpn_tunnel = each.value.name
}

resource "google_compute_router_peer" "router_hub_peer" {
  for_each                  = google_compute_router_interface.router_hub_intf
  name                      = "peer-on-${each.value.name}"
  router                    = each.value.router
  region                    = each.value.region
  peer_ip_address           = split("/",google_compute_router_interface.router_onprem_intf[each.key].ip_range)[0]
  peer_asn                  = google_compute_router.cr_remote[each.value.region].bgp[0].asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_hub_intf[each.key].name
}

resource "google_compute_router_peer" "router_onprem_peer" {
  for_each                  = google_compute_router_interface.router_onprem_intf
  name                      = "peer-on-${each.value.name}"
  router                    = each.value.router
  region                    = each.value.region
  peer_ip_address           = split("/",google_compute_router_interface.router_hub_intf[each.key].ip_range)[0]
  peer_asn                  = google_compute_router.nat_router["${each.value.region}-vpc-external"].bgp[0].asn
  #peer_asn                  = google_compute_router.cr_external[each.value.region].bgp[0].asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_onprem_intf[each.key].name
}

resource "google_network_connectivity_spoke" "spoke_vpn_extenal" {
    for_each    = local.region_map
    name        = "spoke-vpn-ext-${each.key}${local.suffix}"
    location    = each.key
    hub         = google_network_connectivity_hub.hub_external.id
    linked_vpn_tunnels {
        uris                        = [for i in google_compute_vpn_tunnel.hub_tunnel: i.self_link if i.region == each.key]
        site_to_site_data_transfer  = true
    }
}

resource "google_compute_network_peering" "peerings-a-b" {
    for_each                = { for peer in var.peerings : format("%s-%s",peer.network_a,peer.network_b) => peer }
    name                    = "${each.key}${local.suffix}"
    network                 = module.google-infra-vpc.vpcs["${each.value.network_a}"].self_link
    peer_network            = module.google-infra-vpc.vpcs["${each.value.network_b}"].self_link
    export_custom_routes    = true
    import_custom_routes    = true
    import_subnet_routes_with_public_ip = true
    export_subnet_routes_with_public_ip = true
}

resource "google_compute_network_peering" "peerings-b-a" {
    for_each                = { for peer in var.peerings : format("%s-%s",peer.network_b,peer.network_a) => peer }
    name                    = "${each.key}${local.suffix}"
    network                 = module.google-infra-vpc.vpcs["${each.value.network_b}"].self_link
    peer_network            = module.google-infra-vpc.vpcs["${each.value.network_a}"].self_link
    import_custom_routes    = true
    export_custom_routes    = true
    import_subnet_routes_with_public_ip = true
    export_subnet_routes_with_public_ip = true
}

# Cloud NAT

resource "google_compute_router" "nat_router" {
    #Creates a CR per region per VPC
    for_each    = {for counter, combo in setproduct(keys(local.region_map), keys(module.google-infra-vpc.vpcs)):"${combo[0]}-${combo[1]}" => {
        region : combo[0]
        id : module.google-infra-vpc.vpcs[combo[1]].id
        counter : counter
    } }
    name    = "natrtr-${each.key}${local.suffix}"
    region  = each.value.region
    network = each.value.id
    bgp {
        asn = var.cr_base_asn+each.value.counter+500
    }
}

resource "google_compute_router_nat" "nat_auto" {
    for_each = google_compute_router.nat_router
    name   = "nat-${each.key}${local.suffix}"
    router = each.value.name
    region = each.value.region
    nat_ip_allocate_option = "AUTO_ONLY"
    source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# NGFW #

resource "google_compute_network_firewall_policy" "fw_policy" {
    name        = "fwpolicy${local.suffix}"
    description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
    for_each            = module.google-infra-vpc.vpcs
    name                = "fwpolicyassoc-${each.key}${local.suffix}"
    attachment_target   = each.value.id
    firewall_policy     = google_compute_network_firewall_policy.fw_policy.name
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
    src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["health-checkers"].cidr_blocks_ipv4
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

