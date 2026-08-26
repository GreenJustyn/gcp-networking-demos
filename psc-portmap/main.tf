#To-Do. Doesn't work yet. Some data plane issue in the producer side.

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.27"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 6.27"
    }
  }
}

provider "google" {
  project     = var.project-id-consumer
  region      = var.region
}

provider "google-beta" {
  project     = var.project-id-consumer
  region      = var.region
}

data "google_compute_image" "debian-image" {
    family  = "debian-12"
    project = "debian-cloud"
}
data "google_compute_default_service_account" "default" { }

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

data "google_compute_zones" "region_availability" {
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
    apis_per_project  = flatten([
        for project in toset([var.project-id-producer, var.project-id-consumer]): [
            for api in var.apis: {
                api_name    = api
                project_id  = project
            }
        ]
    ])
    projects = { for i in distinct([var.project-id-producer, var.project-id-consumer]): i => null }
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_project_service" "apienable" {
    for_each            = { for item in local.apis_per_project: "${item.api_name}_${item.project_id}" => item }
    project             = each.value.project_id
    service             = each.value.api_name
    disable_on_destroy  = false
    disable_dependent_services  = true
}

resource "google_compute_project_metadata" "project_metadata" {
    for_each    = local.projects
    project     = each.key
    metadata = {
        enable-oslogin  = "TRUE"
        "psc-backends-multiport${local.suffix}-cwd" = path.cwd
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
    project-id  = var.project-id-consumer
}

# ILB Producer Side
resource "tls_private_key" "default" {
    algorithm = "RSA"
    rsa_bits  = 2048
}

resource "tls_self_signed_cert" "default" {
    private_key_pem       = tls_private_key.default.private_key_pem
    validity_period_hours = 8760
    allowed_uses          = [ "server_auth" ]
    dns_names             = ["*.gcp.internal"]
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
    lifecycle {
        create_before_destroy = true
    }
    service_account {
        email  = data.google_compute_default_service_account.default.email
        scopes = ["cloud-platform"]
    }
}

resource "google_compute_instance_from_template" "default" {
    for_each            = {8443 = null, 9443 = null}
    project             = var.project-id-producer
    name                = "inst-servers${local.suffix}-${each.key}"
    zone                = data.google_compute_zones.region_availability.names[0]
    machine_type        = "e2-small"
    source_instance_template = google_compute_instance_template.default.self_link_unique
    metadata = {
        serving_port    = each.key
        startup-script  = templatefile("./debian-host.sh.tftpl", {
            private_key = tls_private_key.default.private_key_pem,
            certificate = tls_self_signed_cert.default.cert_pem
        })
    }
}

resource "google_compute_region_network_endpoint_group" "producer_neg" {
    #for_each                = google_compute_instance_from_template.default
    project                 = var.project-id-producer
    name                    = "neg-producer-portmap${local.suffix}"
    network                 = values(google_compute_instance_from_template.default).*.network_interface[0][0].network
    subnetwork              = values(google_compute_instance_from_template.default).*.network_interface[0][0].subnetwork
    region                  = var.region
    network_endpoint_type   = "GCE_VM_IP_PORTMAP"
}

resource "google_compute_region_network_endpoint" "producer_endpoint" {
    provider                = google-beta
    for_each                = google_compute_instance_from_template.default
    region_network_endpoint_group = google_compute_region_network_endpoint_group.producer_neg.name
    instance                = each.value.id
    project                 = each.value.project
    port                    = each.value.metadata["serving_port"]
    ip_address              = each.value.network_interface[0].network_ip
    client_destination_port = each.value.metadata["serving_port"]
}

resource "google_compute_region_backend_service" "psc_producer_bs" {
    #provider                = google-beta
    #for_each                = google_compute_region_network_endpoint_group.producer_neg
    name                    = "psc-bs${local.suffix}"
    project                 = var.project-id-producer
    #health_checks           = [google_compute_region_health_check.psc_producer_hc.id]
    load_balancing_scheme   = "INTERNAL"
    protocol                = "TCP"
    connection_draining_timeout_sec = 0
    log_config {
        enable = false
    }
    backend {
        group           = google_compute_region_network_endpoint_group.producer_neg.id
        balancing_mode  = "CONNECTION"
    }
}

resource "google_compute_forwarding_rule" "producer_forwarding_rule" {
    name                    = "fr${local.suffix}"
    project                 = var.project-id-producer
    backend_service         = google_compute_region_backend_service.psc_producer_bs.id
    ip_protocol             = "TCP"
    load_balancing_scheme   = "INTERNAL"
    #allow_global_access     = true
    all_ports               = true
    network                 = values(google_compute_instance_from_template.default).*.network_interface[0][0].network
    subnetwork              = values(google_compute_instance_from_template.default).*.network_interface[0][0].subnetwork
}

resource "google_compute_service_attachment" "producer_service_attachment" {
    #for_each                = google_compute_forwarding_rule.producer_forwarding_rule
    project                 = google_compute_forwarding_rule.producer_forwarding_rule.project
    name                    = "psc-attach${local.suffix}"
    connection_preference   = "ACCEPT_AUTOMATIC"
    enable_proxy_protocol   = false
    nat_subnets             = [[for key,val in module.google-infra-vpc.subnets: val.id if strcontains(key, "producer") && val.purpose == "PRIVATE_SERVICE_CONNECT"][0]]
    target_service          = google_compute_forwarding_rule.producer_forwarding_rule.id
}

#
#Consumer Side
#

# L4 ILB Consumer

resource "google_compute_address" "psc_ilb_consumer_address" {
    project         = var.project-id-consumer
    name            = "psc-consumer-addr${local.suffix}"
    subnetwork      = [for key,val in module.google-infra-vpc.subnets: val.id if strcontains(key, "consumer") && val.purpose == "PRIVATE"][0]
    address_type    = "INTERNAL"
}

resource "google_compute_forwarding_rule" "psc_ilb_consumer" {
    #for_each                = google_compute_service_attachment.producer_service_attachment
    project                 = var.project-id-consumer
    name                    = "psc-consumer-fr${local.suffix}"
    target                  = google_compute_service_attachment.producer_service_attachment.id
    load_balancing_scheme   = ""
    network                 = [for i,j in module.google-infra-vpc.vpcs: j.id if strcontains(i, "consumer")][0]
    ip_address              = google_compute_address.psc_ilb_consumer_address.id
    #allow_psc_global_access = true
}
/*
resource "google_compute_region_network_endpoint_group" "psc_neg_consumer" {
    for_each                = google_compute_service_attachment.producer_service_attachment
    name                    = "psc-neg-consumer${local.suffix}-${each.key}"
    region                  = var.region
    project                 = var.project-id-consumer
    network_endpoint_type   = "PRIVATE_SERVICE_CONNECT"
    psc_target_service      = each.value.self_link
    network                 = [for key,val in module.google-infra-vpc.vpcs: val.self_link if strcontains(key, "consumer")][0]
    subnetwork              = [for key,val in module.google-infra-vpc.subnets: val.self_link if strcontains(key, "consumer") && val.purpose == "PRIVATE"][0]
}

resource "google_compute_region_backend_service" "psc_consumer_bs" {
    for_each                = google_compute_region_network_endpoint_group.psc_neg_consumer
    name                    = "psc-consumer-bs${local.suffix}-${each.key}"
    project                 = var.project-id-consumer
    protocol                = "TCP"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    backend {
        group           = each.value.id
        balancing_mode  = "UTILIZATION"
    }
}

resource "google_compute_region_target_tcp_proxy" "psc_consumer_proxy" {
    for_each        = google_compute_region_backend_service.psc_consumer_bs
    project         = var.project-id-consumer
    name            = "psc-consumer-proxy${local.suffix}${each.key}"
    backend_service = each.value.id
}

resource "google_compute_forwarding_rule" "psc_consumer_fr" {
    for_each                = google_compute_region_target_tcp_proxy.psc_consumer_proxy
    project                 = var.project-id-consumer
    name                    = "psc-consumer-fr${local.suffix}-${each.key}"
    region                  = var.region
    load_balancing_scheme   = "INTERNAL_MANAGED"
    subnetwork              = google_compute_address.psc_ilb_consumer_address.subnetwork
    ip_protocol             = "TCP"
    port_range              = each.key
    target                  = each.value.id
    ip_address              = google_compute_address.psc_ilb_consumer_address.id
}
*/

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
        ports = [80, 443, 8443, 9443]
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