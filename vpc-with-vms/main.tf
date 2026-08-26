terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 7.7.0"
    }
  }
}

provider "google" {
  project     = var.project-id
  region      = var.regions[0]
}

provider "google-beta" {
  project     = var.project-id
  region      = var.regions[0]
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

data "google_compute_default_service_account" "default" { }

data "google_compute_image" "debian-image" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_zones" "region-availability" {
    for_each    = toset(var.regions)
    region      = each.value
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

resource "random_shuffle" "gcp-zones" {
    for_each        = { for region in data.google_compute_zones.region-availability: region.region => region.names }
    input           = [ for zone in each.value : zone ]
    #result_count    = 2
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    enable-osconfig = "TRUE"
    enable-guest-attributes = "TRUE"
    "tf-vpc-with-vms-${local.suffix}" = path.cwd
  }
}

resource "google_project_service" "apienable" {
  for_each = toset(var.apis)
  service     = each.value
  disable_on_destroy = false
  disable_dependent_services = true
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    project-id  = var.project-id
    vpcs        = var.vpcs
    namesuffix  = local.suffix
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    project-id  = var.project-id
    fw_rules    = var.fw_rules
    namesuffix  = local.suffix
    depends_on = [ module.google-infra-vpc ]
}

####
####
####

resource "google_compute_instance" "testvm01" {
    name         = "testvm-sin01${local.suffix}"
    machine_type = "e2-micro"
    zone         = random_shuffle.gcp-zones[var.regions[0]].result[0]
    metadata = {
        startup-script = templatefile("./debian-client.sh.tftpl", {})
    }
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["sub-vpc-sin"].self_link
    }
    service_account {
        email  = data.google_compute_default_service_account.default.email
        scopes = ["cloud-platform"]
    }
}

resource "google_compute_instance" "testvm02" {
    name         = "testvm-sin02${local.suffix}"
    machine_type = "e2-micro"
    zone         = random_shuffle.gcp-zones[var.regions[0]].result[0]
    metadata = {
        startup-script = templatefile("./debian-client.sh.tftpl", {})
    }
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["sub-vpc-sin"].self_link
    }
    service_account {
        email  = data.google_compute_default_service_account.default.email
        scopes = ["cloud-platform"]
    }
}

#
# Extra for adding apt repo to work with the default route removed
#

resource "google_compute_global_address" "psc-ip" {
  for_each      = { for address in var.psc_ips : address.name => address }
  name          = "${each.key}${local.suffix}"
  address_type  = "INTERNAL"
  purpose       = "PRIVATE_SERVICE_CONNECT"
  network       = module.google-infra-vpc.vpcs["${each.value.network}"].self_link
  address       = each.value.address
}

resource "google_compute_global_forwarding_rule" "apis-forwarding-rule" {
  for_each              = { for fwdrule in var.psc_ips : fwdrule.name => fwdrule }
  name                  = "${each.key}${local.suffix_nodash}"
  target                = "all-apis"
  network               = module.google-infra-vpc.vpcs["${each.value.network}"].self_link
  ip_address            = google_compute_global_address.psc-ip["${each.key}"].id
  load_balancing_scheme = ""
}

resource "google_dns_response_policy" "googleapis-com" {
    response_policy_name = "dns-rp${local.suffix}"
    networks {
      network_url = module.google-infra-vpc.vpcs["net-vpc"].id
    }
}

resource "google_dns_response_policy_rule" "googleapis-com" {
    response_policy = google_dns_response_policy.googleapis-com.response_policy_name
    rule_name       = "googleapis-com-rule${local.suffix}"
    dns_name        = "*.googleapis.com."

  local_data {
    local_datas {
      name    = "*.googleapis.com."
      type    = "A"
      ttl     = 300
      rrdatas = [google_compute_global_address.psc-ip["psc"].address]
    }
  }  
}

### Cloud NAT ###

resource "google_compute_router" "nat_router" {
    for_each            = module.google-infra-vpc.vpcs
    project             = each.value.project
    name                = "nat-router${local.suffix}-${each.key}"
    network             = each.value.id
}

resource "google_compute_router_nat" "nat_auto" {
    for_each    = google_compute_router.nat_router
    project     = each.value.project
    name        = "nat${local.suffix}-${each.key}"
    router      = each.value.name
    region      = each.value.region
    nat_ip_allocate_option              = "AUTO_ONLY"
    source_subnetwork_ip_ranges_to_nat  = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}


### Firewall ###

resource "google_compute_network_firewall_policy" "fw_policy" {
    name        = "fwpolicy${local.suffix}"
    description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
    for_each            = module.google-infra-vpc.vpcs
    project             = each.value.project
    name                = "fwpolicyassoc${local.suffix}-${each.key}"
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
    firewall_policy         = google_compute_network_firewall_policy.fw_policy.name
    enable_logging          = false
    priority                = 500
    rule_name               = "hc-allow${local.suffix}"
    match {
        src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["health-checkers"].cidr_blocks_ipv4
        layer4_configs {
        ip_protocol = "tcp"
        ports = [80, 443, 8443, 9443]
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