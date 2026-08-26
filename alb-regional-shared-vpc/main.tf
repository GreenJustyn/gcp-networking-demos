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
        for project in toset([var.project-id-hp, var.project-id-sp01, var.project-id-sp02]): [
            for api in var.apis: {
                api_name    = api
                project_id  = project
            }
        ]
    ])
}

data "google_project" "project" {
    for_each    = toset([var.project-id-sp01, var.project-id-sp02])
    project_id  = each.value
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

resource "google_project_service" "apienable" {
    for_each            = { for item in local.apis_per_project: "${item.api_name}_${item.project_id}" => item }
    project             = each.value.project_id
    service             = each.value.api_name
    disable_on_destroy  = false
    disable_dependent_services  = true
}

resource "google_compute_project_metadata" "project_metadata" {
    for_each    = toset([var.project-id-hp, var.project-id-sp01, var. project-id-sp02])
    project     = each.key
    metadata = {
        enable-oslogin  = "TRUE"
        "alb-regional-svpc${local.suffix}" = path.cwd
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
    namesuffix  = module.google-infra-vpc.namesuffix #Creates an arbitrary dependency for VPC module.
    depends_on  = [ module.google-infra-vpc ]
}

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    vms         = var.virtual_machines
    namesuffix  = module.google-infra-firewall.namesuffix #Creates an arbitrary dependency for the Firewall module.
    depends_on = [ module.google-infra-vpc ]
}

module "mig_template" {
    source      = "terraform-google-modules/vm/google//modules/instance_template"
    version     = "9.0.0"
    project_id  = var.project-id-sp01
    network     = module.google-infra-vpc.vpcs[keys(module.google-infra-vpc.vpcs)[0]].self_link
    subnetwork  = module.google-infra-vpc.subnets[keys(module.google-infra-vpc.subnets)[0]].self_link
    service_account = {
        email           = ""
        scopes          = ["cloud-platform"]
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
        "allow-hc-${random_id.id.hex}",
        "allow-ssh-${random_id.id.hex}"
    ]
}

module "mig" {
    source              = "terraform-google-modules/vm/google//modules/mig"
    version             = "9.0.0"
    project_id          = var.project-id-sp01
    instance_template   = module.mig_template.self_link
    region              = var.region
    hostname            = "inst${local.suffix}"
    target_size         = 1
    named_ports         = [{
        name            = "http",
        port            = 80
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

resource "google_project_iam_member" "shared_vpc_subnet_use" {
    for_each    = toset([for item in data.google_project.project: item.number])
    project     = var.project-id-hp
    role        = "roles/compute.networkUser"
    member      = "serviceAccount:${each.value}@cloudservices.gserviceaccount.com"
}

resource "google_compute_region_health_check" "http_health_check" {
    provider    = google-beta
    region      = var.region
    name        = "health-check${local.suffix}"
    project     = var.project-id-sp01
    http_health_check {
        port_specification = "USE_SERVING_PORT"
    }
}

resource "google_compute_region_backend_service" "sp_backend_svc" {
    provider                = google-beta
    region                  = var.region
    name                    = "sp-bs${local.suffix}"
    project                 = var.project-id-sp01
    port_name               = "http"
    protocol                = "HTTP"
    timeout_sec             = 10
    load_balancing_scheme   = "EXTERNAL_MANAGED"
    health_checks           = [google_compute_region_health_check.http_health_check.id]
    backend {
        group               = module.mig.instance_group
        balancing_mode      = "UTILIZATION"
        capacity_scaler     = 1.0
    }
}

resource "google_compute_region_url_map" "url_map" {
    provider        = google-beta
    region          = var.region
    name            = "urlmap${local.suffix}"
    project         = var.project-id-sp02
    default_service = google_compute_region_backend_service.sp_backend_svc.id
    host_rule {
        hosts = ["*"]
        path_matcher = "allpaths"
    }
    path_matcher {
        name = "allpaths"
        default_service = google_compute_region_backend_service.sp_backend_svc.id
    }
}

resource "google_compute_region_target_http_proxy" "http_proxy" {
    provider        = google-beta
    region          = var.region
    project         = var.project-id-sp02
    name            = "http-proxy${local.suffix}"
    url_map         = google_compute_region_url_map.url_map.id
}

resource "google_compute_address" "rxlb_ip" {
    region          = var.region
    network_tier    = "STANDARD"
    name            = "l7-xlb-ip${local.suffix}"
    project         = var.project-id-sp02
}

resource "google_compute_forwarding_rule" "rxlb_fr" {
    provider                = google-beta
    project                 = var.project-id-sp02
    name                    = "fwd-rule${local.suffix}"
    ip_protocol             = "TCP"
    load_balancing_scheme   = "EXTERNAL_MANAGED"
    port_range              = "80"
    target                  = google_compute_region_target_http_proxy.http_proxy.id
    ip_address              = google_compute_address.rxlb_ip.id
    region                  = var.region
    network                 = module.google-infra-vpc.vpcs[keys(module.google-infra-vpc.vpcs)[0]].self_link
    network_tier            = "STANDARD"
}
