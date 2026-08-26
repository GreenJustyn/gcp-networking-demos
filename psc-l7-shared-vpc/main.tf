#Copyright 2023 Google LLC
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
locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}
provider "google" {
    project     = var.project-id-hp
}

provider "google-beta" {
    project     = var.project-id-hp
}

data "google_compute_image" "debian-image" {
    family  = "debian-11"
    project = "debian-cloud"
}

resource "random_id" "id" {
	  byte_length = 3
}

resource "google_project_service" "apienable-hp" {
    project                     = var.project-id-hp
    for_each                    = toset(var.apis-hp)
    service                     = each.value
    disable_on_destroy          = false
    disable_dependent_services  = true
}
resource "google_project_service" "apienable-sp" {
    project                     = var.project-id-sp01
    for_each                    = toset(var.apis-sp)
    service                     = each.value
    disable_on_destroy          = false
    disable_dependent_services  = true
}

/*resource "google_compute_project_metadata" "project_meta" {
    for_each = setunion(toset([var.project-id-hp]),toset([var.project-id-sp01]))
    metadata = {
        #enable-oslogin  = "TRUE"
        "psc-l7${local.suffix}-cwd" = path.cwd
    }
}*/

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    fw_rules    = var.fw_rules
    namesuffix  = module.google-infra-vpc.namesuffix #Creates an arbitrary dependency for VPC module.
}

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    vms         = var.virtual_machines
    namesuffix  = module.google-infra-firewall.namesuffix #Creates an arbitrary dependency for the Firewall module.
}

resource "google_compute_region_health_check" "psc_producer_hc" {
    name                = "health-check${local.suffix}"
    project             = var.project-id-producer
    region              = var.region
    timeout_sec        = 1
    check_interval_sec = 15
    https_health_check {
        port_specification = "USE_SERVING_PORT"
    }
}

module "mig_template" {
    source          = "terraform-google-modules/vm/google//modules/instance_template"
    version         = "8.0.1"
    project_id      = var.project-id-producer
    network         = module.google-infra-vpc.vpcs["net-producer"].self_link
    subnetwork      = module.google-infra-vpc.subnets["sub-producer"].self_link
    service_account = {
        email  = ""
        scopes = ["cloud-platform"]
    }
    access_config = [{
        nat_ip       = null
        network_tier = null
    }]
    name_prefix             = "gclb-mig${local.suffix}"
    startup_script          = templatefile("./debian11.sh.tftpl", {})
    source_image_family     = "debian-11"
    source_image_project    = "debian-cloud"
    tags = [
        "allow-hc${local.suffix}",
        "allow-ssh${local.suffix}"
    ]
}

module "mig" {
    source              = "terraform-google-modules/vm/google//modules/mig"
    project_id          = var.project-id-producer
    mig_name            = "psc-mig${local.suffix}"
    version             = "~> 7.9"
    instance_template   = module.mig_template.self_link
    region              = var.region
    target_size         = 1
    named_ports         = [{
        name            = "https",
        port            = 443
    }]
    network             = module.google-infra-vpc.vpcs["net-producer"].self_link
    subnetwork          = module.google-infra-vpc.subnets["sub-producer"].self_link
    update_policy       = [{ 
        type                            = "PROACTIVE" 
        instance_redistribution_type    = "PROACTIVE" 
        minimal_action                  = "REPLACE" 
        max_surge_percent               = null 
        max_unavailable_percent         = null 
        max_surge_fixed                 = 4 
        max_unavailable_fixed           = null 
        min_ready_sec                   = 50 
        replacement_method              = "SUBSTITUTE" 
    }] 
}

#L4 ILB Producer
/*
resource "google_compute_forwarding_rule" "psc_producer_fr" {
    project                 = var.project-id-producer
    name                    = "psc-producer-fr${local.suffix}"
    region                  = var.region
    load_balancing_scheme   = "INTERNAL"
    backend_service         = google_compute_region_backend_service.psc_producer_bs.id
    all_ports               = true
    subnetwork              = module.google-infra-vpc.subnets["sub-producer-lb"].self_link
}

resource "google_compute_region_backend_service" "psc_producer_bs" {
    name                    = "psc-bs${local.suffix}"
    project                 = var.project-id-producer
    region                  = var.region
    health_checks = [google_compute_region_health_check.psc_producer_hc.id]
    backend {
        group               = module.mig.instance_group
        balancing_mode      = "CONNECTION"
    }
}
*/

# Producer L7 ILB

resource "google_compute_region_backend_service" "psc_producer_bs" {
    name                    = "psc-bs${local.suffix}"
    project                 = var.project-id-producer
    region                  = var.region
    port_name               = "https"
    protocol                = "HTTPS"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    timeout_sec             = 10
    health_checks           = [google_compute_region_health_check.psc_producer_hc.id]
    backend {
        group               = module.mig.instance_group
        balancing_mode      = "UTILIZATION"
        capacity_scaler     = 1.0
    }
}
resource "google_compute_region_url_map" "psc_producer_url_map" {
    project         = var.project-id-producer
    name            = "producer-url-map${local.suffix}"
    region          = var.region
    default_service = google_compute_region_backend_service.psc_producer_bs.id
}
resource "tls_private_key" "default" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "default" {
    private_key_pem = tls_private_key.default.private_key_pem
    validity_period_hours = 12
    early_renewal_hours = 3
    allowed_uses = [
        "key_encipherment",
        "digital_signature",
        "server_auth",
    ]
    dns_names = ["example.com"]
    subject {
        common_name  = "example.com"
        organization = "ACME Examples, Inc"
    }
}

resource "google_compute_region_ssl_certificate" "cert_producer" {
    name_prefix = "cert${local.suffix}"
    project = var.project-id-producer
    private_key = tls_private_key.default.private_key_pem
    certificate = tls_self_signed_cert.default.cert_pem
    region      = var.region
    lifecycle {
        create_before_destroy = true
    }
}
resource "google_compute_region_target_https_proxy" "psc_producer_proxy" {
    project = var.project-id-producer
    name    = "producer-http-proxy${local.suffix}"
    region  = var.region
    url_map = google_compute_region_url_map.psc_producer_url_map.id
    ssl_certificates = [google_compute_region_ssl_certificate.cert_producer.self_link]
}

resource "google_compute_forwarding_rule" "psc_producer_fr" {
    project                 = var.project-id-producer
    name                    = "psc-producer-fr${local.suffix}"
    region                  = var.region
    load_balancing_scheme   = "INTERNAL_MANAGED"
    subnetwork              = module.google-infra-vpc.subnets["sub-producer-lb"].self_link
    ip_protocol             = "TCP"
    port_range              = "443"
    target                  = google_compute_region_target_https_proxy.psc_producer_proxy.id
}

resource "google_compute_service_attachment" "producer_service_attachment" {
    project                 = var.project-id-producer
    name                    = "psc-attach${local.suffix}"
    region                  = var.region
    connection_preference   = "ACCEPT_AUTOMATIC"
    enable_proxy_protocol   = false
    nat_subnets             = [module.google-infra-vpc.subnets["sub-producer-psc-nat"].self_link]
    target_service          = google_compute_forwarding_rule.psc_producer_fr.id
}

#
#Consumer Side
#

# L4 ILB Consumer

/*
resource "google_compute_address" "psc_ilb_consumer_address" {
    project         = var.project-id-hp
    name            = "psc-consumer-addr${local.suffix}"
    region          = var.region
    subnetwork      = module.google-infra-vpc.subnets["sub-shared"].self_link
    address_type    = "INTERNAL"
    address         = "10.221.100.50"
}

resource "google_compute_forwarding_rule" "psc_ilb_consumer" {
    project                 = var.project-id-hp
    name                    = "psc-consumer-fr${local.suffix}"
    region                  = var.region
    target                  = google_compute_service_attachment.producer_service_attachment.id
    load_balancing_scheme   = ""
    network                 = module.google-infra-vpc.vpcs["net-shared"].self_link
    ip_address              = google_compute_address.psc_ilb_consumer_address.id
}
*/

# L7 PSC Consumer

resource "google_compute_region_network_endpoint_group" "psc_neg_consumer" {
    name                    = "psc-neg-consumer${local.suffix}"
    region                  = var.region
    project                 = var.project-id-sp02
    network_endpoint_type   = "PRIVATE_SERVICE_CONNECT"
    psc_target_service      = google_compute_service_attachment.producer_service_attachment.self_link
    network                 = module.google-infra-vpc.vpcs["net-shared"].self_link
    subnetwork              = module.google-infra-vpc.subnets["sub-shared"].self_link
}
resource "google_compute_region_backend_service" "psc_consumer_bs" {
    name                    = "psc-consumer-bs${local.suffix}"
    project                 = var.project-id-sp02
    region                  = var.region
    protocol                = "HTTP"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    backend {
        group           = google_compute_region_network_endpoint_group.psc_neg_consumer.id
        balancing_mode  = "UTILIZATION"
    }
}

resource "google_compute_region_url_map" "psc_consumer_url_map" {
    project         = var.project-id-sp01
    name            = "consumer-url-map${local.suffix}"
    region          = var.region
    default_service = google_compute_region_backend_service.psc_consumer_bs.id
}
resource "google_compute_region_ssl_certificate" "cert_consumer" {
  name_prefix = "cert-consumer${local.suffix}"
  project = var.project-id-sp01
  private_key = tls_private_key.default.private_key_pem
  certificate = tls_self_signed_cert.default.cert_pem
  region      = var.region
  lifecycle {
    create_before_destroy = true
  }
}
resource "google_compute_region_target_https_proxy" "psc_consumer_proxy" {
    project = var.project-id-sp01
    name    = "consumer-http-proxy${local.suffix}"
    region  = var.region
    url_map = google_compute_region_url_map.psc_consumer_url_map.id
    ssl_certificates = [google_compute_region_ssl_certificate.cert_consumer.self_link]
}

resource "google_compute_forwarding_rule" "psc_consumer_fr" {
    project                 = var.project-id-sp01
    name                    = "psc-consumer-fr${local.suffix}"
    region                  = var.region
    load_balancing_scheme   = "INTERNAL_MANAGED"
    subnetwork              = module.google-infra-vpc.subnets["sub-consumer-lb"].self_link
    ip_protocol             = "TCP"
    port_range              = "443"
    target                  = google_compute_region_target_https_proxy.psc_consumer_proxy.id
    ip_address              = cidrhost(module.google-infra-vpc.subnets["sub-consumer-lb"].ip_cidr_range,10)
}