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
      version     = "~> 6.25"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 6.25"
    }
  }
}

provider "google" {
  project     = var.project-id-consumer
  region      = var.regions[0]
}

provider "google-beta" {
  project     = var.project-id-consumer
  region      = var.regions[0]
}

data "google_compute_image" "debian-image" {
    family  = "debian-12"
    project = "debian-cloud"
}
data "google_compute_default_service_account" "default" { }

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = toset(["iap-forwarders"])
  range_type = each.value
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
    apis_list       = { for combo in setproduct(toset([var.project-id-producer, var.project-id-consumer]), var.apis): "${combo[0]}_${combo[1]}" => combo }
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_project_service" "apienable" {
    for_each            = local.apis_list
    project             = each.value[0]
    service             = each.value[1]
    disable_on_destroy  = false
    disable_dependent_services  = true
}

resource "google_compute_project_metadata" "project_metadata" {
    for_each    = toset([var.project-id-producer, var.project-id-consumer])
    project     = each.key
    metadata = {
        enable-oslogin  = "TRUE"
        "psc-endpoints-cloudrun-multiregion${local.suffix}-cwd" = path.cwd
    }
}

resource "google_cloud_run_v2_service" "json_svc" {
    project     = var.project-id-producer
    for_each = toset(var.regions)
    name     = "cloudrun-json${local.suffix}-${each.key}"
    location = each.key
    ingress = "INGRESS_TRAFFIC_ALL"
    deletion_protection = false
    template {
        containers {
            #image = "codfish/json-server:0.17.3"
            image   = "bkimminich/juice-shop"
            startup_probe {
                initial_delay_seconds = 0
                timeout_seconds = 240
                period_seconds = 240
                failure_threshold = 1
                tcp_socket {
                    #port = 80
                    port = 3000
                }
            }
            ports {
                #container_port = 80
                container_port = 3000
            }
        }
    }
}

resource "google_cloud_run_service_iam_binding" "public_cloud_run" {
    project     = var.project-id-producer
    for_each = google_cloud_run_v2_service.json_svc
    location = each.value.location
    service  = each.value.name
    role     = "roles/run.invoker"
    members = [
        "allUsers"
    ]
}

resource "google_compute_region_network_endpoint_group" "cloudrun_neg" {
    project                 = var.project-id-producer
    for_each                = google_cloud_run_v2_service.json_svc
    name                    = "cr-neg${local.suffix}-${each.key}"
    network_endpoint_type   = "SERVERLESS"
    region                  = each.value.location
    cloud_run {
        service = each.value.name
    }
}

resource "google_compute_region_backend_service" "backend" {
    project                 = var.project-id-producer
    for_each                = google_compute_region_network_endpoint_group.cloudrun_neg
    name                    = "backend${local.suffix}-${each.key}"
    region                  = each.key
    protocol                = "HTTP"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    log_config {
        enable = true
    }
    backend {
        group = google_compute_region_network_endpoint_group.cloudrun_neg[each.key].id
    }
}

#Producer

resource "google_compute_region_url_map" "psc_producer_url_map" {
    for_each                = google_compute_region_backend_service.backend
    project                 = each.value.project
    name                    = "producer-url-map${local.suffix}-${each.key}"
    region                  = each.key
    default_service         = google_compute_region_backend_service.backend[each.key].id
}

resource "google_compute_region_target_http_proxy" "psc_producer_proxy" {
    for_each                = google_compute_region_url_map.psc_producer_url_map
    project                 = each.value.project
    name                    = "producer-http-proxy${local.suffix}-${each.key}"
    region                  = each.key
    url_map                 = google_compute_region_url_map.psc_producer_url_map[each.key].id
}

resource "google_compute_forwarding_rule" "psc_producer_fr" {
    for_each                = google_compute_region_target_http_proxy.psc_producer_proxy
    project                 = each.value.project
    name                    = "psc-fr${local.suffix}-${each.key}"
    region                  = each.key
    load_balancing_scheme   = "INTERNAL_MANAGED"
    target                  = google_compute_region_target_http_proxy.psc_producer_proxy[each.key].id
    port_range              = "80"
    allow_global_access     = true
    # Find the subnet which is: (1) private (exclude proxy only subnets etc), (2) for the specific region and (3) is from the producer VPC. Take the first/only result and return a string: [0]
    subnetwork              = [for i in module.google-infra-vpc.subnets : i.self_link if i.purpose == "PRIVATE" && i.region == each.key && strcontains(i.name, "producer")][0]
}

resource "google_compute_service_attachment" "producer_service_attachment" {
    for_each                = google_compute_forwarding_rule.psc_producer_fr
    project                 = each.value.project
    name                    = "psc-attach${local.suffix}-${each.key}"
    region                  = each.key
    connection_preference   = "ACCEPT_AUTOMATIC"
    enable_proxy_protocol   = false
    nat_subnets             = [for i in module.google-infra-vpc.subnets : i.self_link if i.purpose == "PRIVATE_SERVICE_CONNECT" && i.region == each.key && strcontains(i.name, "producer")]
    target_service          = google_compute_forwarding_rule.psc_producer_fr[each.key].id
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

#Consumer Side

resource "google_compute_address" "psc_ilb_consumer_address" {
    for_each        = google_compute_service_attachment.producer_service_attachment
    project         = var.project-id-consumer
    name            = "psc-consumer-addr${local.suffix}-${each.key}"
    region          = each.key
    subnetwork      = [for i in module.google-infra-vpc.subnets : i.self_link if i.purpose == "PRIVATE" && i.region == each.key && strcontains(i.name, "consumer")][0]
    address_type    = "INTERNAL"
}

resource "google_compute_forwarding_rule" "psc_ilb_consumer" {
    for_each                = google_compute_service_attachment.producer_service_attachment
    project                 = var.project-id-consumer
    name                    = "psc-consumer-fr${local.suffix}-${each.key}"
    region                  = each.key
    target                  = google_compute_service_attachment.producer_service_attachment[each.key].id
    load_balancing_scheme   = ""
    subnetwork                 = [for i in module.google-infra-vpc.subnets : i.self_link if i.purpose == "PRIVATE" && i.region == each.key && strcontains(i.name, "consumer")][0]
    allow_psc_global_access = true
    ip_address              = google_compute_address.psc_ilb_consumer_address[each.key].id
}

# DNS

resource "google_dns_managed_zone" "psc_ilb" {
    name        = "ilb-zone${local.suffix}"
    dns_name    = "cloudrun.gcpnonprod.com."
    description = "Zone for ILB"
    visibility  = "private"
    private_visibility_config {
        networks {
            network_url = values(google_compute_forwarding_rule.psc_ilb_consumer).*.network[0]
        }
    }
}

resource "google_dns_record_set" "ilb_consumer_rs" {
    name         = google_dns_managed_zone.psc_ilb.dns_name
    managed_zone = google_dns_managed_zone.psc_ilb.name
    type         = "A"
    ttl          = 300
    routing_policy {
        dynamic "geo" {
            for_each =  google_compute_forwarding_rule.psc_ilb_consumer
            content {
                location    = geo.key
                rrdatas     = [ google_compute_address.psc_ilb_consumer_address[geo.key].address ]
                #rrdatas     = [ google_compute_forwarding_rule.psc_ilb_consumer[geo.key].id ]
                health_checked_targets {
                  internal_load_balancers {
                    load_balancer_type = "regionalL4ilb"
                    ip_address = google_compute_address.psc_ilb_consumer_address[geo.key].address
                    #ip_address      = google_compute_forwarding_rule.psc_ilb_consumer[geo.key].id
                    port = 80
                    ip_protocol = "tcp"
                    network_url = geo.value.network
                    project = geo.value.project
                    region = geo.key
                  }
                }
            }
        }
    }
}

# Firewall

resource "google_compute_network_firewall_policy" "fw_policy" {
    for_each    = toset([var.project-id-producer, var.project-id-consumer])
    project     = each.value
    name        = "fwpolicy${local.suffix}-${each.value}"
    description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
  for_each          = module.google-infra-vpc.vpcs
  project           = each.value.project
  name              = "fwpolicyassoc${local.suffix}-${each.key}"
  attachment_target = each.value.id
  firewall_policy   = google_compute_network_firewall_policy.fw_policy[each.value.project].name
}

resource "google_compute_network_firewall_policy_rule" "iap_rule" {
    for_each                = google_compute_network_firewall_policy.fw_policy
    project                 = each.value.project
    action                  = "allow"
    description             = ""
    direction               = "INGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = google_compute_network_firewall_policy.fw_policy[each.value.project].name
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
    for_each                = google_compute_network_firewall_policy.fw_policy
    project                 = each.value.project
    action                  = "allow"
    description             = ""
    direction               = "INGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = google_compute_network_firewall_policy.fw_policy[each.value.project].name
    priority                = 20000
    rule_name               = "rfc1918-allow${local.suffix}"
    match {
        src_ip_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
        layer4_configs {
        ip_protocol = "all"
        }
    }
}
