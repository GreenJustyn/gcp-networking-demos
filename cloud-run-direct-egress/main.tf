locals {
  suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
  suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.35"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 6.35"
    }
  }
}

provider "google" {
 project     = var.project-id
}

provider "google-beta" {
 project     = var.project-id
}
data "google_netblock_ip_ranges" "netblock" {
    range_type = "cloud-netblocks"
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_project_service" "apienable" {
    project                     = var.project-id
    for_each                    = toset(var.apis)
    service                     = each.value
    disable_on_destroy          = false
    disable_dependent_services  = true
}

resource "google_compute_project_metadata" "project_metadata" {
    metadata = {
        #enable-oslogin  = "TRUE"
        "cloud-run${local.suffix}-cwd" = path.cwd
    }
}

resource "google_cloud_run_v2_service" "json_svc" {
    name     = "cloudrun-json${local.suffix}"
    location = var.region
    ingress = "INGRESS_TRAFFIC_ALL"
    template {
        containers {
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
  location = google_cloud_run_v2_service.json_svc.location
  service  = google_cloud_run_v2_service.json_svc.name
  role     = "roles/run.invoker"
  members = [
    "allUsers"
  ]
}
resource "google_compute_region_network_endpoint_group" "cloudrun_neg" {
    name                    = "cloudrun-neg${local.suffix}"
    network_endpoint_type   = "SERVERLESS"
    region                  = var.region
    cloud_run {
        service = google_cloud_run_v2_service.json_svc.name
    }
}

resource "google_compute_backend_service" "backend" {
    name                    = "backend${local.suffix}"
    protocol                = "HTTP"
    load_balancing_scheme   = "EXTERNAL_MANAGED"
    log_config {
        enable = true
    }
    backend {
        group = google_compute_region_network_endpoint_group.cloudrun_neg.id
    }
    security_policy = google_compute_security_policy.security-policy-1.self_link
}

resource "google_compute_url_map" "url_map" {
    name            = "url-map${local.suffix}"
    default_service = google_compute_backend_service.backend.id
}

resource "google_compute_target_http_proxy" "http_proxy" {
    name    = "http-proxy${local.suffix}"
    url_map = google_compute_url_map.url_map.id
}

resource "google_compute_global_address" "external_ip" {
  name = "cloudrun-ip${local.suffix}"
}

resource "google_compute_global_forwarding_rule" "frontend" {
    name                    = "frontend${local.suffix}"
    target                  = google_compute_target_http_proxy.http_proxy.id
    port_range              = "80"
    ip_address              = google_compute_global_address.external_ip.address
    load_balancing_scheme   = "EXTERNAL_MANAGED"
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}
