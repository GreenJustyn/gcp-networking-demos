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
    apis_per_project  = flatten([
        for project in toset([var.project-id-producer, var.project-id-consumer]): [
            for api in var.apis: {
                api_name    = api
                project_id  = project
            }
        ]
    ])
}
provider "google" {
    project     = var.project-id-producer
}

provider "google-beta" {
    project     = var.project-id-producer
}

data "google_compute_image" "debian_image" {
    family  = "debian-11"
    project = "debian-cloud"
}

resource "random_id" "id" {
	  byte_length = 3
}

resource "google_project_service" "apienable" {
    for_each            = { for item in local.apis_per_project: "${item.api_name}_${item.project_id}" => item }
    project             = each.value.project_id
    service             = each.value.api_name
    disable_on_destroy  = false
    disable_dependent_services  = true
}

resource "google_compute_project_metadata" "project_metadata" {
    for_each    = toset([var.project-id-producer, var.project-id-consumer])
    project     = each.key
    metadata = {
        enable-oslogin  = "TRUE"
        "psc-consumer-producer${local.suffix}-cwd" = path.cwd
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
    namesuffix  = module.google-infra-vpc.namesuffix
    depends_on = [
      module.google-infra-vpc
    ]
}

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    vms         = var.virtual_machines
    namesuffix  = module.google-infra-firewall.namesuffix
    depends_on = [
      module.google-infra-vpc
    ]
}

resource "google_compute_region_health_check" "hc_producer" {
    name                = "health-check${local.suffix}"
    project             = var.project-id-producer
    region              = var.region
    timeout_sec        = 1
    check_interval_sec = 15
    http_health_check {
        port_specification = "USE_SERVING_PORT"
    }
}

resource "google_compute_region_health_check" "hc_consumer" {
    name                = "hc-consumer${local.suffix}"
    project             = var.project-id-consumer
    region              = var.region
    timeout_sec        = 1
    check_interval_sec = 15
    http_health_check {
        port_specification = "USE_SERVING_PORT"
    }
}

resource "google_compute_instance_template" "multi_nic_tpl" {
    name        = "multinic-tpl${local.suffix}"
    tags        = ["allow-hc${local.suffix}", "allow-ssh${local.suffix}"]
    machine_type         = "e2-medium"
    can_ip_forward       = true
    disk {
        source_image = data.google_compute_image.debian_image.self_link
        auto_delete  = true
        boot         = true
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["sub-a"].self_link
        access_config { }
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["sub-b"].self_link
    }
    metadata_startup_script = templatefile("./debian11.sh.tftpl", {})
    lifecycle {
        create_before_destroy = true
    }
}

resource "google_compute_region_instance_group_manager" "multi_nic_mig" {
    name    = "multinic-mig${local.suffix}"
    region  = var.region
    version {
        instance_template  = google_compute_instance_template.multi_nic_tpl.id
    }
    base_instance_name = "vm-multinic"
    target_size        = 1
    auto_healing_policies {
        health_check      = google_compute_region_health_check.hc_producer.id
        initial_delay_sec = 300
    }
}

#L4 ILB Producer

resource "google_compute_forwarding_rule" "psc_producer_fr" {
    project                 = var.project-id-producer
    name                    = "psc-producer-fr${local.suffix}"
    region                  = var.region
    load_balancing_scheme   = "INTERNAL"
    backend_service         = google_compute_region_backend_service.psc_producer_bs.id
    all_ports               = true
    subnetwork              = module.google-infra-vpc.subnets["sub-b-lb"].self_link
}

resource "google_compute_region_backend_service" "psc_producer_bs" {
    name                    = "psc-bs${local.suffix}"
    project                 = var.project-id-producer
    region                  = var.region
    network                 = module.google-infra-vpc.vpcs["net-b"].self_link
    health_checks = [google_compute_region_health_check.hc_producer.id]
    backend {
        group               = google_compute_region_instance_group_manager.multi_nic_mig.instance_group
        balancing_mode      = "CONNECTION"
    }
}

resource "google_compute_service_attachment" "psc_attachment" {
    name                    = "sa${local.suffix}"
    region                  = var.region
    enable_proxy_protocol   = false
    connection_preference   = "ACCEPT_AUTOMATIC"
    nat_subnets             = [ module.google-infra-vpc.subnets["sub-b-psc-nat"].self_link ]
    target_service          = google_compute_forwarding_rule.psc_producer_fr.id
}

# L4 ILB Consumer

resource "google_compute_address" "psc_ilb_consumer_address" {
    project         = var.project-id-consumer
    name            = "psc-consumer-addr${local.suffix}"
    region          = var.region
    subnetwork      = module.google-infra-vpc.subnets["sub-a-lb"].self_link
    address_type    = "INTERNAL"
    address         = "10.221.102.5"
}

resource "google_compute_forwarding_rule" "psc_ilb_consumer" {
    project                 = var.project-id-consumer
    name                    = "psc-consumer-fr${local.suffix}"
    region                  = var.region
    target                  = google_compute_service_attachment.psc_attachment.self_link
    load_balancing_scheme   = ""
    network                 = module.google-infra-vpc.vpcs["net-a"].self_link
    ip_address              = google_compute_address.psc_ilb_consumer_address.id
}

# ILB as Next Hop

resource "google_compute_forwarding_rule" "ilb-rule-internal" {
    name                  = "fwdrule-int${local.suffix}"
    network               = module.google-infra-vpc.vpcs["net-a"].self_link
    subnetwork            = module.google-infra-vpc.subnets["sub-a-lb"].self_link
    all_ports             = true
    load_balancing_scheme = "INTERNAL"
    ip_protocol           = "TCP"
    region                = var.region
    backend_service       = google_compute_region_backend_service.bs_ilb.self_link
}


resource "google_compute_region_backend_service" "bs_ilb" {
    name                              = "backend-svc-int${local.suffix}"
    load_balancing_scheme             = "INTERNAL"
    protocol                          = "TCP"
    region                            = var.region
    health_checks                     = [google_compute_region_health_check.hc_consumer.self_link]
    connection_draining_timeout_sec   = 10
    network                           = module.google-infra-vpc.vpcs["net-a"].self_link
    backend {
        group = google_compute_region_instance_group_manager.multi_nic_mig.instance_group
    }
}

resource "google_compute_route" "route-ilb-internal1" {
    name          = "ilbnhroute${local.suffix}"
    dest_range    = "0.0.0.0/0"
    network       = module.google-infra-vpc.vpcs["net-a"].self_link
    next_hop_ilb  = google_compute_forwarding_rule.ilb-rule-internal.id
    priority      = "100"
}