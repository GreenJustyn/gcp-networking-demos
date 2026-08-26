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
  project     = var.project-id-consumer01
  region      = var.region
}

provider "google-beta" {
  project     = var.project-id-consumer01
  region      = var.region
}

data "google_compute_image" "debian-image" {
    family  = "debian-12"
    project = "debian-cloud"
}
data "google_compute_default_service_account" "default" {
    project = var.project-id-producer
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
    apis_per_project  = {for i in setproduct([var.project-id-producer, var.project-id-consumer01, var.project-id-consumer02],var.apis): "${i[0]}_${i[1]}" => i}
    projects = { for i in distinct([var.project-id-producer, var.project-id-consumer01, var.project-id-consumer02]): i => null }
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_project_service" "apienable" {
    for_each            = local.apis_per_project
    project             = each.value[0]
    service             = each.value[1]
    disable_on_destroy  = false
    disable_dependent_services  = true
}

resource "google_compute_project_metadata" "project_metadata" {
    for_each    = local.projects
    project     = each.key
    metadata = {
        enable-oslogin  = "TRUE"
        "psc-endpoints${local.suffix}-cwd" = path.cwd
    }
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
    depends_on  = [ module.google-infra-vpc ]
    project-id  = var.project-id-consumer01
}

resource "google_compute_region_health_check" "psc_producer_hc" {
    name                = "health-check${local.suffix}"
    project             = var.project-id-producer
    region              = var.region
    log_config {
      enable = false
    }
    timeout_sec        = 1
    check_interval_sec = 15
    https_health_check {
        port_specification  = "USE_FIXED_PORT"
        port                = "443"
    }
}

resource "tls_private_key" "default" {
    algorithm = "RSA"
    rsa_bits  = 2048
}

resource "tls_self_signed_cert" "default" {
    private_key_pem       = tls_private_key.default.private_key_pem
    validity_period_hours = 8760
    allowed_uses          = [ "server_auth" ]
    dns_names             = ["*.gcp.internal"]
    #ip_addresses          = [ google_compute_address.default.address ]
    subject {
        common_name       = "internal"
        organization      = "Googleyness Inc"
    }
}

resource "google_compute_region_ssl_certificate" "default" {
    project = var.project-id-producer
    name_prefix = "ilbcert${local.suffix}"
    private_key = tls_private_key.default.private_key_pem
    certificate = tls_self_signed_cert.default.cert_pem
    lifecycle {
        create_before_destroy = true
    }
}

resource "google_compute_instance_template" "default" {
    project = var.project-id-producer
    name_prefix   =  "ilb-tpl${local.suffix}"
    machine_type  = "e2-small"
    network_interface {
        network     = [for i,j in module.google-infra-vpc.vpcs: j.id if strcontains(i, "producer")][0]
        subnetwork  = [for i,j in module.google-infra-vpc.subnets: j.id if strcontains(i, "producer")][0]
        #access_config { } #Omit for private IP only.
    }
    disk {
        source_image = "debian-cloud/debian-12"
        auto_delete  = true
        boot         = true
    }
    metadata = {
        startup-script  = templatefile("./debian-host.sh.tftpl", {
            private_key = tls_private_key.default.private_key_pem,
            certificate  = tls_self_signed_cert.default.cert_pem
        })
    }
    lifecycle {
        create_before_destroy = true
    }
    service_account {
        email  = data.google_compute_default_service_account.default.email
        scopes = ["cloud-platform"]
    }
}

resource "google_compute_region_instance_group_manager" "default" {
    project             = var.project-id-producer
    name                = "ilb-ig${local.suffix}"
    base_instance_name  = "ilb-ig"
    version {
        instance_template = google_compute_instance_template.default.self_link_unique
    }
    target_size  = 1
#    named_port {
#        name = "http"
#        port = 80
#    }
    named_port {
        name = "https"
        port = 443
    }
    update_policy { 
        type = "PROACTIVE" 
        instance_redistribution_type = "PROACTIVE" 
        minimal_action = "REPLACE" 
        max_surge_percent = null 
        max_unavailable_percent = null 
        max_surge_fixed = 4 
        max_unavailable_fixed = null 
        replacement_method = "SUBSTITUTE" 
    }
}

#L4 ILB Producer

resource "google_compute_forwarding_rule" "psc_producer_fr" {
    project                 = var.project-id-producer
    name                    = "psc-producer-fr${local.suffix}"
    load_balancing_scheme   = "INTERNAL"
    backend_service         = google_compute_region_backend_service.psc_producer_bs.id
    all_ports               = true
    subnetwork              = [for key,val in module.google-infra-vpc.subnets: val.id if strcontains(key, "producer") && val.purpose == "PRIVATE"][0]
}

resource "google_compute_region_backend_service" "psc_producer_bs" {
    name                    = "psc-bs${local.suffix}"
    project                 = var.project-id-producer
    health_checks = [google_compute_region_health_check.psc_producer_hc.id]
    log_config {
      enable = false
    }
    backend {
        group               = google_compute_region_instance_group_manager.default.instance_group
        balancing_mode      = "CONNECTION"
    }
}

resource "google_compute_service_attachment" "producer_service_attachment" {
    project                 = var.project-id-producer
    name                    = "psc-attach${local.suffix}"
    connection_preference   = "ACCEPT_AUTOMATIC"
    enable_proxy_protocol   = false
    nat_subnets             = [[for key,val in module.google-infra-vpc.subnets: val.id if strcontains(key, "producer") && val.purpose == "PRIVATE_SERVICE_CONNECT"][0]]
    target_service          = google_compute_forwarding_rule.psc_producer_fr.id
    domain_names            = ["${var.region}.p.mikehanline.com."]
}

#
#Consumer Side
#

# L4 ILB Consumer

resource "google_compute_address" "psc_ilb_consumer_address01" {
    project         = var.project-id-consumer01
    name            = "psc-consumer-addr01${local.suffix}"
    subnetwork      = [for key,val in module.google-infra-vpc.subnets: val.id if strcontains(key, "consumer") && val.purpose == "PRIVATE" && val.project == var.project-id-consumer01][0]
    address_type    = "INTERNAL"
}

resource "google_compute_forwarding_rule" "psc_ilb_consumer01" {
    project                 = var.project-id-consumer01
    name                    = "psc-consumer-fr01${local.suffix}"
    target                  = google_compute_service_attachment.producer_service_attachment.id
    load_balancing_scheme   = ""
    network                 = [for i,j in module.google-infra-vpc.vpcs: j.id if strcontains(i, "consumer") && j.project == var.project-id-consumer01][0]
    ip_address              = google_compute_address.psc_ilb_consumer_address01.id
    allow_psc_global_access = true
    service_directory_registrations {
      namespace = "mynamespace"
    }
}

resource "google_compute_address" "psc_ilb_consumer_address02" {
    project         = var.project-id-consumer02
    name            = "psc-consumer-addr02${local.suffix}"
    subnetwork      = [for key,val in module.google-infra-vpc.subnets: val.id if strcontains(key, "consumer") && val.purpose == "PRIVATE" && val.project == var.project-id-consumer02][0]
    address_type    = "INTERNAL"
}

resource "google_compute_forwarding_rule" "psc_ilb_consumer02" {
    project                 = var.project-id-consumer02
    name                    = "psc-consumer-fr02${local.suffix}"
    target                  = google_compute_service_attachment.producer_service_attachment.id
    load_balancing_scheme   = ""
    network                 = [for i,j in module.google-infra-vpc.vpcs: j.id if strcontains(i, "consumer") && j.project == var.project-id-consumer02][0]
    ip_address              = google_compute_address.psc_ilb_consumer_address02.id
    allow_psc_global_access = true
    service_directory_registrations {
      namespace = "mynamespace"
    }
}

resource "google_compute_network_firewall_policy" "fw_policy" {
    for_each    = local.projects
    project     = each.key
    name        = "fwpolicy${local.suffix}-${each.key}"
    description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
    for_each            = module.google-infra-vpc.vpcs
    project             = each.value.project
    name                = "fwpolicyassoc${local.suffix}-${each.key}"
    attachment_target   = each.value.id
    firewall_policy     = google_compute_network_firewall_policy.fw_policy[each.value.project].name
}

resource "google_compute_network_firewall_policy_rule" "iap_rule" {
    for_each                = google_compute_network_firewall_policy.fw_policy
    project                 = each.value.project
    action                  = "allow"
    description             = ""
    direction               = "INGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = each.value.name
    priority                = 200
    rule_name               = "iap-allow${local.suffix}-${each.key}"
    match {
        src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["iap-forwarders"].cidr_blocks_ipv4
        layer4_configs {
        ip_protocol = "tcp"
        ports = [22]
        }
    }
}

resource "google_compute_network_firewall_policy_rule" "hc_rule" {
    for_each                = google_compute_network_firewall_policy.fw_policy
    project                 = each.value.project
    action                  = "allow"
    description             = ""
    direction               = "INGRESS"
    disabled                = false
    firewall_policy         = each.value.name
    enable_logging          = false
    priority                = 500
    rule_name               = "hc-allow${local.suffix}-${each.key}"
    match {
        src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["health-checkers"].cidr_blocks_ipv4
        layer4_configs {
        ip_protocol = "tcp"
        ports = [80, 443]
        }
    }
}

resource "google_compute_network_firewall_policy_rule" "rfc1918_rule" {
    for_each                = google_compute_network_firewall_policy.fw_policy
    project                 = each.value.project
    action                  = "allow"
    description             = ""
    direction               = "INGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = each.value.name
    priority                = 20000
    rule_name               = "rfc1918-allow${local.suffix}-${each.key}"
    match {
        src_ip_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
        layer4_configs {
        ip_protocol = "all"
        }
    }
}

# Cloud NAT

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