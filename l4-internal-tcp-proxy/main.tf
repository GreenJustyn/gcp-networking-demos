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
 project     = var.project-id
}
provider "google-beta" {
 project     = var.project-id
}

data "google_compute_image" "debian-image" {
    family  = "debian-11"
    project = "debian-cloud"
}

resource "random_id" "id" {
	byte_length = 3
}

resource "google_project_service" "apienable" {
    project                     = var.project-id
    for_each                    = toset(var.apis)
    service                     = each.value
    disable_on_destroy          = false
    disable_dependent_services  = true
}

resource "google_compute_project_metadata" "project_meta" {
    metadata = {
        #enable-oslogin  = "TRUE"
        "l4tcpproxy${local.suffix}-cwd" = path.cwd
    }
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    fw_rules    = var.fw_rules
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    vms         = var.virtual_machines
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

resource "google_compute_region_health_check" "hc_http" {
    name                = "hc-http${local.suffix}"
    region              = var.region
    timeout_sec        = 1
    check_interval_sec = 5
    http_health_check {
        port_specification = "USE_SERVING_PORT"
    }
    log_config {
        enable = true
    }
}

module "mig_template" {
    source          = "terraform-google-modules/vm/google//modules/instance_template"
    version         = "~> 8.0.1"
    network         = module.google-infra-vpc.vpcs["net-lbtest"].self_link
    subnetwork      = module.google-infra-vpc.subnets["sub-lbtest"].self_link
    service_account = {
        email  = ""
        scopes = ["cloud-platform"]
    }
    access_config = [{
        nat_ip       = null
        network_tier = null
    }]
    name_prefix             = "ilb-mig${local.suffix}"
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
    mig_name            = "ilb-mig${local.suffix}"
    version             = "~> 8.0.1"
    instance_template   = module.mig_template.self_link
    region              = var.region
    target_size         = 1
    named_ports         = [{
        name            = "port8080",
        port            = 8080
    },
    {
        name            = "port8081",
        port            = 8081
    }]
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

# Internal TCP Proxy

resource "google_compute_region_backend_service" "internal_bs_8080" {
    name                    = "bs-8080${local.suffix}"
    region                  = var.region
    port_name               = "port8080"
    protocol                = "TCP"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    timeout_sec             = 10
    health_checks           = [google_compute_region_health_check.hc_http.id]
    backend {
        group               = module.mig.instance_group
        balancing_mode      = "UTILIZATION"
        capacity_scaler     = 1.0
    }
}

resource "google_compute_region_backend_service" "internal_bs_8081" {
    name                    = "bs-8081${local.suffix}"
    region                  = var.region
    port_name               = "port8081"
    protocol                = "TCP"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    timeout_sec             = 10
    health_checks           = [google_compute_region_health_check.hc_http.id]
    backend {
        group               = module.mig.instance_group
        balancing_mode      = "UTILIZATION"
        capacity_scaler     = 1.0
    }
}
resource "google_compute_region_target_tcp_proxy" "internal_tcp_proxy_8080" {
    name            = "internal-tcp-8080${local.suffix}"
    region          = var.region
    backend_service = google_compute_region_backend_service.internal_bs_8080.id
}
resource "google_compute_region_target_tcp_proxy" "internal_tcp_proxy_8081" {
    name            = "internal-tcp-8081${local.suffix}"
    region          = var.region
    backend_service = google_compute_region_backend_service.internal_bs_8081.id
}

resource "google_compute_address" "ilb_address" {
    name         = "ilb-addr${local.suffix}"
    region       = var.region
    subnetwork   = module.google-infra-vpc.subnets["sub-lbtest"].self_link
    address_type = "INTERNAL"
    purpose      = "SHARED_LOADBALANCER_VIP"
}

resource "google_compute_forwarding_rule" "internal_tcp_fr_8080" {
    name                    = "int-tcp-fr-8080${local.suffix}"
    target                  = google_compute_region_target_tcp_proxy.internal_tcp_proxy_8080.id
    region                  = var.region
    ip_protocol             = "TCP"
    port_range              = "8080"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    network                 = module.google-infra-vpc.vpcs["net-lbtest"].self_link
    subnetwork              = module.google-infra-vpc.subnets["sub-lbtest"].self_link
    network_tier            = "PREMIUM"
    ip_address              = google_compute_address.ilb_address.id
}
resource "google_compute_forwarding_rule" "internal_tcp_fr_8081" {
    name                    = "int-tcp-fr-8081${local.suffix}"
    target                  = google_compute_region_target_tcp_proxy.internal_tcp_proxy_8081.id
    region                  = var.region
    ip_protocol             = "TCP"
    port_range              = "8081"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    network                 = module.google-infra-vpc.vpcs["net-lbtest"].self_link
    subnetwork              = module.google-infra-vpc.subnets["sub-lbtest"].self_link
    network_tier            = "PREMIUM"
    ip_address              = google_compute_address.ilb_address.id
}