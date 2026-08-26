terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.32"
    }
  }
}

provider "google" {
    project     = var.project-id
    region = var.regions[0]
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}


data "google_compute_image" "debian-image" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_zones" "region_availability" {
    region  = var.regions[0]
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "${local.suffix_nodash}-cwd" = path.cwd
  }
}

resource "google_project_service" "apienable" {
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

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

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

#Block proxy subnet to backend. This firewall rule has no effect currently (2025)
/*
resource "google_compute_network_firewall_policy_rule" "filter_proxy_rule" {
    action                  = "deny"
    description             = ""
    direction               = "EGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = google_compute_network_firewall_policy.fw_policy.name
    priority                = 15000
    rule_name               = "filter-proxy-range${local.suffix}"
    match {
        src_ip_ranges = [module.google-infra-vpc.subnets["hybrid-test-sub-sin-proxy"].ip_cidr_range]
        dest_ip_ranges = [module.google-infra-vpc.subnets["hybrid-test-sub-sin"].ip_cidr_range]
        layer4_configs {
        ip_protocol = "all"
        }
    }
}
*/

resource "google_compute_instance" "testvm01" {
    name         = "testvm-consumer${local.suffix}"
    machine_type = "e2-micro"
    zone         = data.google_compute_zones.region_availability.names[0]
    metadata = {
        startup-script = "${file("debian-client.sh")}"
    }
    tags = [ ]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["hybrid-test-sub-sin"].self_link
    }
    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }
}

resource "google_compute_instance" "producer_vm" {
    name         = "producer-vm01${local.suffix}"
    machine_type = "e2-micro"
    zone         = data.google_compute_zones.region_availability.names[0]
    metadata = {
        startup-script = "${file("ilb-debian.sh")}"
    }
    tags = [ ]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["producer-subsin"].self_link
        network_ip  = google_compute_address.producer_vm_reservation.address
    }
    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }
}

resource "google_compute_address" "producer_vm_reservation" {
  name         = "producer-vm-reservation${local.suffix}"
  subnetwork   = module.google-infra-vpc.subnets["producer-subsin"].self_link
  address_type = "INTERNAL"
  address      = cidrhost(module.google-infra-vpc.subnets["producer-subsin"].ip_cidr_range,100)
  region       = var.regions[0]
}

resource "google_dns_response_policy" "regional_internet_neg_rule" {
    response_policy_name = "dns-rp${local.suffix}"
    networks {
      network_url = module.google-infra-vpc.vpcs["hybrid-test-vpc"].id
    }
}

resource "google_dns_response_policy_rule" "internal_vm" {
    response_policy = google_dns_response_policy.regional_internet_neg_rule.response_policy_name
    rule_name       = "internal-vm-rule"
    dns_name        = "host.internal."

  local_data {
    local_datas {
      name    = "host.internal."
      type    = "A"
      ttl     = 300
      rrdatas = [google_compute_address.producer_vm_reservation.address]
    }
  }  
}

resource "google_compute_network_peering" "peering_a_b" {
  name         = "peering-a-b${local.suffix}"
  network      = module.google-infra-vpc.vpcs["hybrid-test-vpc"].self_link
  peer_network = module.google-infra-vpc.vpcs["producer-vpc"].self_link
}

resource "google_compute_network_peering" "peering_b_a" {
  name         = "peering-b-a${local.suffix}"
  network      = module.google-infra-vpc.vpcs["producer-vpc"].self_link
  peer_network = module.google-infra-vpc.vpcs["hybrid-test-vpc"].self_link
}

resource "google_compute_region_network_endpoint_group" "neg_fqdn_port" {
    name                    = "fqdn-port-neg${local.suffix}"
    network                 = module.google-infra-vpc.vpcs["hybrid-test-vpc"].self_link
    region                  = var.regions[0]
    network_endpoint_type   = "INTERNET_FQDN_PORT"
}

resource "google_compute_region_network_endpoint" "region_fqdn_ip_port" {
    region_network_endpoint_group   = google_compute_region_network_endpoint_group.neg_fqdn_port.name
    region                          = var.regions[0]
    fqdn                            = google_dns_response_policy_rule.internal_vm.local_data[0].local_datas[0].name
    port                            = 80
}

resource "google_compute_region_backend_service" "default" {
    name                    = "hybrid-bs${local.suffix}"
    region                  = var.regions[0]
    protocol                = "TCP"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    backend {
        group           = google_compute_region_network_endpoint_group.neg_fqdn_port.id
        balancing_mode  = "UTILIZATION"
    }
}

resource "google_compute_region_target_tcp_proxy" "default" {
    name            = "tcp-proxy${local.suffix}"
    backend_service = google_compute_region_backend_service.default.id
}

resource "google_compute_address" "fr_address" {
    name            = "fr${local.suffix}"
    subnetwork      = module.google-infra-vpc.subnets["hybrid-test-sub-sin"].self_link
    address_type    = "INTERNAL"
}

resource "google_compute_forwarding_rule" "psc_consumer_fr" {
    name                    = "fr${local.suffix}"
    region                  = var.regions[0]
    load_balancing_scheme   = "INTERNAL_MANAGED"
    subnetwork              = module.google-infra-vpc.subnets["hybrid-test-sub-sin"].self_link
    ip_protocol             = "TCP"
    port_range              = 80
    target                  = google_compute_region_target_tcp_proxy.default.id
    ip_address              = google_compute_address.fr_address.address
}

resource "google_compute_router" "nat_router" {
    for_each            = module.google-infra-vpc.vpcs
    name    = "nat-router-${each.key}${local.suffix}"
    region  = var.regions[0]
    network = each.value.id
}

resource "google_compute_router_nat" "nat_auto" {
    for_each = google_compute_router.nat_router
    name   = "nat${each.key}${local.suffix}"
    router = each.value.name
    region = each.value.region
    nat_ip_allocate_option = "AUTO_ONLY"
    source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}