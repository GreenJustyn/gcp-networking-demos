provider "google" {
  project     = var.project-id
  #version     = "~> 3.37"
}
provider "google-beta" {
  project     = var.project-id
  #version     = "~> 3.37"
}
provider "random" {
  #version     = "~> 2.3"
}
resource "random_id" "id" {
  byte_length = 3
}
data "google_compute_image" "debian-image" {
    family  = "debian-11"
    project = "debian-cloud"
}
locals {
  rand = var.nameprefix
  zones = values(var.zoneregions)
  regions = keys(var.zoneregions)
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "tf-path-${random_id.id.hex}" = path.cwd
  }
}

# Network Setup #
resource "google_compute_network" "vpc" {
  name                    = "net-${local.rand}"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "region-a-sub" {
  name          = "a-${local.rand}"
  ip_cidr_range = var.subnets[0]
  region        = local.regions[0]
  private_ip_google_access = true
  network       = google_compute_network.vpc.self_link
}

# Firewall Setup #
resource "google_compute_firewall" "fw-iap-ssh" {
  name          = "ssh-${local.rand}"
  network       = google_compute_network.vpc.self_link
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
}
resource "google_compute_firewall" "rfc1918-in" {
  name          = "int-${local.rand}"
  network       = google_compute_network.vpc.self_link
  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

# Test VMs
resource "google_compute_instance" "vm1" {
    name          = "vm-${local.rand}-01"
    machine_type  = var.vm_spec
    zone          = element(local.zones[0], 0)
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    metadata = {
        startup-script      = templatefile("./debian-11-client.sh.tftpl", { })
    }
    network_interface {
        subnetwork = google_compute_subnetwork.region-a-sub.self_link
    }
    service_account {
        scopes = ["cloud-platform"]
    }
}

#
# Internally access Googleapis and apt repo updates so they don't go via SWP / Cloud NAT etc
#

resource "google_compute_global_address" "psc-ip" {
  for_each      = { for address in var.psc_ips : address.name => address }
  name          = "${each.key}-${random_id.id.hex}"
  address_type  = "INTERNAL"
  purpose       = "PRIVATE_SERVICE_CONNECT"
  network       = module.google-infra-vpc.vpcs["${each.value.network}"].self_link
  address       = each.value.address
}

resource "google_compute_global_forwarding_rule" "apis-forwarding-rule" {
  for_each              = { for fwdrule in var.psc_ips : fwdrule.name => fwdrule }
  name                  = "${each.key}${random_id.id.hex}"
  target                = "all-apis"
  network               = module.google-infra-vpc.vpcs["${each.value.network}"].self_link
  ip_address            = google_compute_global_address.psc-ip["${each.key}"].id
  load_balancing_scheme = ""
}

resource "google_dns_response_policy" "googleapis-com" {
    response_policy_name = "dns-rp-${random_id.id.hex}"
    networks {
      network_url = module.google-infra-vpc.vpcs["net-swg-demo"].id
    }
}

resource "google_dns_response_policy_rule" "googleapis-com" {
    response_policy = google_dns_response_policy.googleapis-com.response_policy_name
    for_each        = { for rule in var.dns_rp_rules : rule.name => rule }
    rule_name       = "${each.key}-${random_id.id.hex}"
    dns_name        = each.value.dns_name
    local_data {
        local_datas {
            name    = each.value.dns_name
            type    = "A"
            ttl     = 300
            rrdatas = [google_compute_global_address.psc-ip["${each.value.psc-ip}"].address]
        }
    }
}

#Enable APIs if not done already
resource "google_project_service" "apienable" {
  for_each = toset(var.apis)
  service     = each.value
  disable_on_destroy = false
  disable_dependent_services = true
}
