provider "google" {
 project     = local.project-ids[0]
}

provider "google-beta" {
 project     = local.project-ids[0]
}

resource "random_id" "id" {
	  byte_length = 3
}

locals {
    full_region_list    = toset(distinct(flatten([for val in var.vpcs:  val.subnets[*].region])))
    project-ids         = distinct([for val in var.vpcs: val.project-id])
}

data "google_compute_image" "debian-image" {
    family  = "debian-11"
    project = "debian-cloud"
}

data "google_compute_zones" "region-availability" {
    for_each    = local.full_region_list
    region      = each.value
}
resource "google_project_service" "apienable" {
    for_each                    = toset(var.apis)
    service                     = each.value
    disable_on_destroy          = false
    disable_dependent_services  = true
}
resource "random_shuffle" "gcp-zones" {
    for_each        = { for region in data.google_compute_zones.region-availability: region.region => region.names }
    input           = [ for zone in each.value : zone ]
}

resource "google_compute_project_metadata" "default" {
    for_each    = toset(local.project-ids)
    project     = each.value
    metadata = {
        enable-oslogin  = "TRUE"
        "${random_id.id.hex}-cwd" = path.cwd
    }
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = random_id.id.hex
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    fw_rules    = var.fw_rules
    namesuffix  = random_id.id.hex
    depends_on = [ module.google-infra-vpc ]
}

resource "google_compute_network_peering" "peerings-a-b" {
    for_each                = { for peer in var.peerings : format("%s-%s",peer.network_a,peer.network_b) => peer }
    name                    = "${each.key}-${random_id.id.hex}"
    network                 = module.google-infra-vpc.vpcs["${each.value.network_a}"].self_link
    peer_network            = module.google-infra-vpc.vpcs["${each.value.network_b}"].self_link
    export_custom_routes    = true
}

resource "google_compute_network_peering" "peerings-b-a" {
    for_each                = { for peer in var.peerings : format("%s-%s",peer.network_b,peer.network_a) => peer }
    name                    = "${each.key}-${random_id.id.hex}"
    network                 = module.google-infra-vpc.vpcs["${each.value.network_b}"].self_link
    peer_network            = module.google-infra-vpc.vpcs["${each.value.network_a}"].self_link
    import_custom_routes    = true
}

resource "google_compute_instance" "testvms" {
    for_each            = { for vm in var.vms : vm.name => vm }
    name                = "${each.key}-${random_id.id.hex}"
    machine_type        = each.value.size
    zone                = random_shuffle.gcp-zones[each.value.region].result[0]
    metadata            = {
        startup-script      = templatefile("./debian-11-client.sh.tftpl", { })
    }
    tags = [
        "allow-ssh-${random_id.id.hex}"
        #one(google_compute_firewall.iap-ssh-access.target_tags) 
    ]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork  = module.google-infra-vpc.subnets[each.value.subnet].self_link
        network_ip  = cidrhost(module.google-infra-vpc.subnets[each.value.subnet].ip_cidr_range,100)
    }
    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }
    depends_on  = [
        #google_dns_response_policy_rule.googleapis-com
    ]
}

#
# Extra for adding apt repo to work with the default route removed
#



#
# HA-VPN Tunnel from NCC-01 to NCC-04
#
/*
resource "random_password" "vpnpassphrase" {
  length           = 16
  special          = false
}

module "vpn_ha-1" {
    source  = "terraform-google-modules/vpn/google//modules/vpn_ha"
    version = "~> 1.3.0"
    project_id  = "mhanline-ncc-01"
    region  = "asia-southeast1"
    network         = module.google-infra-vpc.vpcs["vpc-hub"].self_link
    name            = "hub-ncc-04"
    peer_gcp_gateway = module.vpn_ha-2.self_link
    router_asn = 64514
    router_advertise_config = {
        groups = ["ALL_SUBNETS"]
        ip_ranges = {
            "10.229.66.0/24" = "spoke-1",
            "10.229.67.0/24" = "spoke-2"
        }
        mode = "CUSTOM"
    }
  tunnels = {
    remote-0 = {
        bgp_peer = {
            address = "169.254.1.1"
            asn     = 64513
        }
        bgp_peer_options  = null
        bgp_session_range = "169.254.1.2/30"
        ike_version       = 2
        vpn_gateway_interface = 0
        peer_external_gateway_interface = null
        shared_secret     = random_password.vpnpassphrase.result
    }
    remote-1 = {
      bgp_peer = {
        address = "169.254.2.1"
        asn     = 64513
      }
      bgp_peer_options  = null
      bgp_session_range = "169.254.2.2/30"
      ike_version       = 2
      vpn_gateway_interface = 1
      peer_external_gateway_interface = null
      shared_secret     = random_password.vpnpassphrase.result
    }
  }
}

module "vpn_ha-2" {
  source  = "terraform-google-modules/vpn/google//modules/vpn_ha"
  version = "~> 1.3.0"
  project_id  = "mhanline-ncc-01"
  region  = "asia-southeast1"
  network         = module.google-infra-vpc.vpcs["vpc-spoke-3"].self_link
  name            = "net2-to-net1"
  router_asn = 64513
  peer_gcp_gateway = module.vpn_ha-1.self_link
  tunnels = {
    remote-0 = {
      bgp_peer = {
        address = "169.254.1.2"
        asn     = 64514
      }
      bgp_peer_options  = null
      bgp_session_range = "169.254.1.1/30"
      ike_version       = 2
      vpn_gateway_interface = 0
      peer_external_gateway_interface = null
      shared_secret     = random_password.vpnpassphrase.result
    }
    remote-1 = {
      bgp_peer = {
        address = "169.254.2.2"
        asn     = 64514
      }
      bgp_peer_options  = null
      bgp_session_range = "169.254.2.1/30"
      ike_version       = 2
      vpn_gateway_interface = 1
      peer_external_gateway_interface = null
      shared_secret     = random_password.vpnpassphrase.result
    }
  }
}*/

output "hub_id" { 
    value = one([for network in module.google-infra-vpc.vpcs: network.id if length(regexall("vpc-hub", network.name)) > 0])
}
output "spoke_ids" {
    value = [for network in module.google-infra-vpc.vpcs: network.id if length(regexall("vpc-hub", network.name)) < 1]
}