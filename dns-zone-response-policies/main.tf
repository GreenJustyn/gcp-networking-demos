#Purpose:
# Root zone forwards nowhere by default. Useful for testing response policy passthrough configurations.

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.33"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 6.33"
    }
  }
}

provider "google" {
  project     = var.project-id
}

provider "google-beta" {
  project     = var.project-id
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    enable-osconfig = "TRUE"
    enable-guest-attributes = "TRUE"
    "dns-zones-${local.suffix}" = path.cwd
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

module "google-infra-vms" {
  source      = "../modules/google-infra-vms"
  project-id  = var.project-id
  vms         = var.virtual_machines
  namesuffix  = local.suffix_nodash
  depends_on = [ module.google-infra-vpc ]
}

## Managed DNS Zone ##

resource "google_dns_managed_zone" "default" {
  name        = "root-zone${local.suffix}"
  dns_name    = "."
  description = local.suffix_nodash
  visibility = "private"
  private_visibility_config {
    networks {
      network_url = module.google-infra-vpc.vpcs["net-vpc"].id
    }
  }
}
/*
resource "google_dns_managed_zone" "mongodb_zone" {
  name        = "mongodb-zone${local.suffix}"
  dns_name    = "o1tvi.mongodb.net."
  description = local.suffix_nodash
  visibility = "private"
  private_visibility_config {
    networks {
      network_url = module.google-infra-vpc.vpcs["net-vpc"].id
    }
  }
  forwarding_config {
    target_name_servers {
      ipv4_address = "8.8.8.8"
      forwarding_path = "default"
    }
  }
}

resource "google_dns_policy" "default" {
  name                      = "default${local.suffix}"
  enable_logging = true
  networks {
    network_url = module.google-infra-vpc.vpcs["net-vpc"].id
  }
}

resource "google_dns_record_set" "default" {
  name = "abcd.${google_dns_managed_zone.default.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = google_dns_managed_zone.default.name

  rrdatas = ["10.99.99.99"]
}
*/

resource "google_dns_response_policy" "default" {
    response_policy_name = "dns-rp${local.suffix}"
    networks {
      network_url = module.google-infra-vpc.vpcs["net-vpc"].id
    }
}

resource "google_dns_response_policy_rule" "default" {
  provider        = google-beta
  response_policy = google_dns_response_policy.default.response_policy_name
  rule_name       = "default-rule${local.suffix}"
  dns_name        = "*.o1tvi.mongodb.net."
  behavior        = "bypassResponsePolicy"
}

/*
resource "google_dns_response_policy_rule" "default2" {
  provider        = google-beta
  response_policy = google_dns_response_policy.default.response_policy_name
  rule_name       = "default-rule2${local.suffix}"
  dns_name        = "test-jd-shard-00-02.o1tvi.mongodb.net."
  local_data {
    local_datas {
      name    = "test-jd-shard-00-02.o1tvi.mongodb.net."
      type    = "A"
      ttl     = 300
      rrdatas = ["1.2.3.4"]
    }
  }
}
*/

### FIREWALL ###

resource "google_compute_network_firewall_policy" "fw_policy" {
    name        = "fwpolicy${local.suffix}"
    description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
  name              = "fwpolicyassoc${local.suffix}"
  attachment_target = values(module.google-infra-vpc.vpcs)[0].id
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