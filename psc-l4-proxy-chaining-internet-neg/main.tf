# Proxy LB Chaining use case
# L4 ILB (consumer) -> Service Attachment -> L4 Proxy LB -> FQDN NEGs -> L4 ILB -> Instance Group -> Backend
#

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

resource "google_compute_network_firewall_policy_rule" "hc_rule" {
    action                  = "allow"
    description             = ""
    direction               = "INGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = google_compute_network_firewall_policy.fw_policy.name
    priority                = 300
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

resource "google_compute_instance" "testvm_producer" {
    name         = "testvm-producer${local.suffix}"
    machine_type = "e2-micro"
    zone         = data.google_compute_zones.region_availability.names[0]
    allow_stopping_for_update = true
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
        subnetwork = module.google-infra-vpc.subnets["producer-sub-sin"].self_link
    }
    service_account {
        scopes = ["cloud-platform"]
    }
}

resource "google_compute_instance" "testvm_consumer" {
    name         = "testvm-consumer${local.suffix}"
    machine_type = "e2-micro"
    zone         = data.google_compute_zones.region_availability.names[0]
    allow_stopping_for_update = true
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
        subnetwork = module.google-infra-vpc.subnets["consumer-sub-sin"].self_link
    }
    service_account {
        scopes = ["cloud-platform"]
    }
}

resource "google_compute_instance" "producer_vm" {
    name         = "producer-vm01${local.suffix}"
    machine_type = "e2-micro"
    zone         = data.google_compute_zones.region_availability.names[0]
    allow_stopping_for_update = true
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
        subnetwork = module.google-infra-vpc.subnets["producer-sub-sin"].self_link
        network_ip  = google_compute_address.producer_vm_reservation.address
    }
    service_account {
        scopes = ["cloud-platform"]
    }
}

resource "google_compute_address" "producer_vm_reservation" {
  name         = "producer-vm-reservation${local.suffix}"
  subnetwork   = module.google-infra-vpc.subnets["producer-sub-sin"].self_link
  address_type = "INTERNAL"
  address      = cidrhost(module.google-infra-vpc.subnets["producer-sub-sin"].ip_cidr_range,100)
  region       = var.regions[0]
}

resource "google_compute_instance_group" "producer_vm_ig" {
    name        = "producer-ig${local.suffix}"
    description = "${local.suffix_nodash}"
    instances = [
        google_compute_instance.producer_vm.id
    ]
    named_port {
        name = "http"
        port = "80"
    }
    zone = google_compute_instance.producer_vm.zone
}

resource "google_compute_health_check" "http_hc" {
    name = "hc${local.suffix}"
    http_health_check {
      port_specification = "USE_SERVING_PORT"
    }
}

resource "google_compute_region_backend_service" "bs_producer" {
    name          = "bs${local.suffix}"
    health_checks = [google_compute_health_check.http_hc.self_link]
    backend {
        group = google_compute_instance_group.producer_vm_ig.self_link
        balancing_mode = "CONNECTION"
    }
}

resource "google_compute_address" "producer_fr_ip" {
    name            = "fr-producer${local.suffix}"
    subnetwork      = module.google-infra-vpc.subnets["producer-sub-sin"].self_link
    address_type    = "INTERNAL"
}

resource "google_compute_forwarding_rule" "producer_fr" {
    name                  = "fr-producer${local.suffix}"
    load_balancing_scheme = "INTERNAL"
    ports                 = ["80"]
    network               = module.google-infra-vpc.vpcs["producer-vpc"].self_link
    subnetwork            = module.google-infra-vpc.subnets["producer-sub-sin"].self_link
    backend_service       = google_compute_region_backend_service.bs_producer.self_link
    ip_address            = google_compute_address.producer_fr_ip.address
}

resource "google_compute_service_attachment" "producer_service_attachment" {
    name                    = "psc-attach${local.suffix}"
    connection_preference   = "ACCEPT_AUTOMATIC"
    enable_proxy_protocol   = false
    nat_subnets             = [[for key,val in module.google-infra-vpc.subnets: val.id if strcontains(key, "producer") && val.purpose == "PRIVATE_SERVICE_CONNECT"][0]]
    target_service          = google_compute_forwarding_rule.psc_producer_fr.id
}

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
    allow_psc_global_access = false
}

### DNS Settings ###

resource "google_dns_response_policy" "regional_internet_neg_rule" {
    response_policy_name = "dns-rp${local.suffix}"
    networks {
      network_url = module.google-infra-vpc.vpcs["producer-vpc"].id
    }
}

resource "google_dns_response_policy_rule" "fqdn_neg_resolve" {
    response_policy = google_dns_response_policy.regional_internet_neg_rule.response_policy_name
    rule_name       = "internal-neg-rule${local.suffix}"
    dns_name        = "host.internal."
    local_data {
        local_datas {
            name    = "host.internal."
            type    = "A"
            ttl     = 300
            rrdatas = [google_compute_forwarding_rule.producer_fr.ip_address]
        }
    }  
}

resource "google_compute_region_network_endpoint_group" "neg_fqdn_port" {
    name                    = "internet-fqdn-port-neg${local.suffix}"
    network                 = module.google-infra-vpc.vpcs["producer-vpc"].self_link
    region                  = var.regions[0]
    network_endpoint_type   = "INTERNET_FQDN_PORT"
}

resource "google_compute_region_network_endpoint" "region_fqdn_ip_port" {
    region_network_endpoint_group   = google_compute_region_network_endpoint_group.neg_fqdn_port.name
    region                          = var.regions[0]
    fqdn                            = google_dns_response_policy_rule.fqdn_neg_resolve.local_data[0].local_datas[0].name
    port                            = 80
}

resource "google_compute_region_backend_service" "producer_neg_bs" {
    name                    = "hybrid-bs${local.suffix}"
    region                  = var.regions[0]
    protocol                = "TCP"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    backend {
        group           = google_compute_region_network_endpoint_group.neg_fqdn_port.id
        balancing_mode  = "UTILIZATION"
    }
}

resource "google_compute_region_target_tcp_proxy" "producer_tcp_proxy" {
    name            = "tcp-proxy${local.suffix}"
    backend_service = google_compute_region_backend_service.producer_neg_bs.id
}

resource "google_compute_address" "fr_address" {
    name            = "fr${local.suffix}"
    subnetwork      = module.google-infra-vpc.subnets["producer-sub-sin"].self_link
    address_type    = "INTERNAL"
}

resource "google_compute_forwarding_rule" "psc_producer_fr" {
    name                    = "fr${local.suffix}"
    region                  = var.regions[0]
    load_balancing_scheme   = "INTERNAL_MANAGED"
    subnetwork              = module.google-infra-vpc.subnets["producer-sub-sin"].self_link
    ip_protocol             = "TCP"
    port_range              = 80
    target                  = google_compute_region_target_tcp_proxy.producer_tcp_proxy.id
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