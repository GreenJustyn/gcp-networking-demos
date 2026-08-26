# This code uses the Terraform resources for the load balancer.
# If you want to use Google Cloud Plartform modules, see gclb-http

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.18"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 6.18"
    }
  }
}

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

resource "random_id" "id" {
	  byte_length = 3
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    enable-osconfig = "TRUE"
    enable-guest-attributes = "TRUE"
    "gclb-resource-http-cwd${local.suffix}" = path.cwd
  }
}

resource "google_project_service" "apienable" {
  for_each = toset(var.apis)
  service     = each.value
  disable_on_destroy = false
  disable_dependent_services = true
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    fw_rules    = var.fw_rules
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

module "google-infra-vms" {
  source        = "../modules/google-infra-vms"
  vms           = var.virtual_machines
  namesuffix    = local.suffix_nodash
  project-id    = var.project-id
  depends_on    = [ module.google-infra-vpc ]
}

resource "google_compute_global_address" "default" {
  name     = "l7-xlb-ip${local.suffix}"
}

resource "google_compute_health_check" "default" {
    name               = "hc${local.suffix}"
    check_interval_sec = 30
    timeout_sec = 10
    http_health_check {
        port_specification = "USE_SERVING_PORT"
        request_path       = "/"
    }
}

resource "google_compute_instance_template" "default" {
  name_prefix  =  "gclb-tpl${local.suffix}"
  machine_type = "e2-small"
  tags         = ["allow-hc${local.suffix}", "allow-ssh${local.suffix}"]
  network_interface {
    network    = values(module.google-infra-vpc.vpcs)[0].id
    subnetwork = values(module.google-infra-vpc.subnets)[0].id
    access_config { }
  }
  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
  }
  metadata = {
    startup-script = templatefile("./gclb-debian11.sh.tftpl", {})
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "default" {
    name = "gclb-ig${local.suffix}"
    base_instance_name         = "gclb-ig"
    region                     = var.regions[0]
    version {
        instance_template = google_compute_instance_template.default.self_link_unique
    }
    target_size  = 2
    named_port {
        name = "http"
        port = 80
    }
    auto_healing_policies {
        health_check      = google_compute_health_check.default.id
        initial_delay_sec = 300
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

resource "google_compute_region_instance_group_manager" "mirrored" {
    name = "gclb-ig-mirrored${local.suffix}"
    base_instance_name         = "gclb-ig-mirror"
    region                     = var.regions[0]
    version {
        instance_template = google_compute_instance_template.default.self_link_unique
    }
    target_size  = 1
    named_port {
        name = "http-8080"
        port = 8080
    }
    auto_healing_policies {
        health_check      = google_compute_health_check.default.id
        initial_delay_sec = 300
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

resource "google_compute_backend_service" "default" {
    name        = "bs${local.suffix}"
    port_name   = "http"
    protocol    = "HTTP"
    load_balancing_scheme = "EXTERNAL_MANAGED"
    timeout_sec = 10
    health_checks = [google_compute_health_check.default.id]
    backend {
        group           = google_compute_region_instance_group_manager.default.instance_group
        balancing_mode  = "UTILIZATION"
        capacity_scaler = 1.0
    }
}

resource "google_compute_backend_service" "mirrored" {
    name        = "bs-mirrored${local.suffix}"
    port_name   = "http-8080"
    protocol    = "HTTP"
    load_balancing_scheme = "EXTERNAL_MANAGED"
    timeout_sec = 10
    health_checks = [google_compute_health_check.default.id]
    backend {
        group           = google_compute_region_instance_group_manager.mirrored.instance_group
        balancing_mode  = "UTILIZATION"
        capacity_scaler = 1.0
    }
}

resource "google_compute_url_map" "default" {
    name        = "urlmap${local.suffix}"
    default_service = google_compute_backend_service.default.id
    host_rule {
        hosts = ["*"]
        path_matcher = "allpaths"
    }
    path_matcher {
        name = "allpaths"
        default_service = google_compute_backend_service.default.id
        route_rules {
            priority = 1
            match_rules 
                prefix_match = "/"
            }
            route_action {
                weighted_backend_services {
                    weight = 100
                    backend_service = google_compute_backend_service.default.id
                }
                request_mirror_policy {
                    backend_service = google_compute_backend_service.default.id
                }
            }
        }
    }
}

resource "google_compute_target_http_proxy" "default" {
  name     = "proxy${local.suffix}"
  url_map  = google_compute_url_map.default.id
}

resource "google_compute_global_forwarding_rule" "default" {
  name                  = "fr${local.suffix}"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}

output ipv4_address {
    value = google_compute_global_address.default.address
}