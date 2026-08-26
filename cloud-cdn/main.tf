variable "project-id" {
    type = string
}
variable "region" {
  type = string
}
variable "nodesize" {
  type = string
}
variable "apis" {
  type = list(string)
}

resource "random_id" "id" {
	  byte_length = 4
}

terraform {
  required_providers {
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 3.65"
    }
    google = {
      source = "hashicorp/google"
      version     = "~> 3.65"
    }
  }
}

provider "google" {
 project     = var.project-id
 region      = var.region
}

provider "google-beta" {
 project     = var.project-id
 region      = var.region
}

#Enable APIs if not done already
resource "google_project_service" "apienable" {
  for_each = toset(var.apis)
  service     = each.value
  disable_on_destroy = false
  disable_dependent_services = true
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    enable-osconfig = "TRUE"
    enable-guest-attributes = "TRUE"
    "terraform-${random_id.id.hex}" = path.cwd
  }
}

# URL MAP
resource "google_compute_url_map" "cdn_url_map" {
  name            = "cdn-url-map"
  default_service = google_compute_backend_bucket.cdn_backend_bucket.self_link
}

#GCS 

resource "google_storage_bucket" "cdn_bucket" {
  name          = "cdn-bucket-${random_id.id.hex}"
  storage_class = "MULTI_REGIONAL"
  location      = "ASIA"
}
 
resource "google_compute_backend_bucket" "cdn_backend_bucket" {
  name        = "cdn-backend-bucket"
  description = "Backend bucket for serving static content through CDN"
  bucket_name = google_storage_bucket.cdn_bucket.name
  enable_cdn  = true
}

resource "google_storage_bucket_iam_member" "all_users_viewers" {
  bucket = google_storage_bucket.cdn_bucket.name
  role   = "roles/storage.legacyObjectReader"
  member = "allUsers"
}

resource "google_storage_bucket_object" "video" {
  name   = "raindrops.mp4"
  source = "./Raindrops_Videvo.mp4"
  bucket = google_storage_bucket.cdn_bucket.name
}

resource "google_compute_managed_ssl_certificate" "cdn_certificate" {
  name = "cdn-managed-certificate"
  managed {
    domains = ["cdndemo.endpoints.${var.project-id}.cloud.goog"]
  }
}

resource "google_compute_target_https_proxy" "cdn_https_proxy" {
  name             = "cdn-https-proxy"
  url_map          = google_compute_url_map.cdn_url_map.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.cdn_certificate.self_link]
}

resource "google_compute_global_address" "cdn_public_address" {
  name         = "cdn-public-address"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"
}

resource "google_compute_global_forwarding_rule" "cdn_global_forwarding_rule" {
  name       = "cdn-global-forwarding-https-rule"
  target     = google_compute_target_https_proxy.cdn_https_proxy.self_link
  ip_address = google_compute_global_address.cdn_public_address.address
  port_range = "443"
}

resource "google_endpoints_service" "demoservice" {
    service_name   = "cdndemo.endpoints.${var.project-id}.cloud.goog"
    openapi_config = <<-EOT
    swagger: "2.0"
    info:
        description: "Cloud Endpoints DNS"
        title: "Cloud Endpoints DNS"
        version: "1.0.0"
    paths: {}
    host: "cdndemo.endpoints.mhanline-cdn01.cloud.goog"
    x-google-endpoints:
    -   name: "cdndemo.endpoints.${var.project-id}.cloud.goog"
        target: "${google_compute_global_address.cdn_public_address.address}"
    EOT
}


output "endpoint_name" {
  value = google_endpoints_service.demoservice.service_name
}



## Network and Firewalls ##
/*
resource "google_compute_network" "vpc" {
  name                    = "nat-${random_id.id.hex}-net"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet-a" {
  name          = "sub-${random_id.id.hex}-a"
  ip_cidr_range = "10.229.64.0/24"
  region        = var.region
  private_ip_google_access = true
  network       = google_compute_network.vpc.self_link
}

resource "google_compute_firewall" "fw-iap-ssh" {
  name          = "ssh-${random_id.id.hex}"
  network       = google_compute_network.vpc.self_link
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
}
resource "google_compute_firewall" "hc" {
  name          = "hc-${random_id.id.hex}"
  network       = google_compute_network.vpc.self_link
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22", "209.85.152.0/22", "209.85.204.0/22"]
}
#Replace 0.0.0.0/0 with the specific source ranges you want to allow.
resource "google_compute_firewall" "fw-allow-client" {
  name          = "clientaccess-${random_id.id.hex}"
  network       = google_compute_network.vpc.self_link
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_forwarding_rule" "gce-fr" {
  name                  = "gce-fr-${random_id.id.hex}"
  region                = var.region
  port_range            = 80
  backend_service       = google_compute_region_backend_service.gce-bes.id
}

resource "google_compute_region_backend_service" "gce-bes" {
  name                            = "gce-bes-${random_id.id.hex}"
  load_balancing_scheme           = "EXTERNAL"
  region                          = var.region
  health_checks                   = [google_compute_region_health_check.gce-hc.id]
  connection_draining_timeout_sec = 10
  session_affinity                = "CLIENT_IP"
  backend {
    group          = google_compute_region_instance_group_manager.gce-mig.instance_group
    balancing_mode = "CONNECTION"
  }

}

resource "google_compute_region_health_check" "gce-hc" {
  name               = "gce-hc-${random_id.id.hex}"
  check_interval_sec = 1
  timeout_sec        = 1
  tcp_health_check {
    port = "80"
  }
}

## Compute ##

resource "google_compute_instance_template" "gce-template" {
  name_prefix  = "tpl-${random_id.id.hex}-"
  region  = var.region
  lifecycle {
    create_before_destroy = true
  }
  machine_type         = var.nodesize
  can_ip_forward       = false

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }
  disk {
    source_image = data.google_compute_image.debian10.self_link
    auto_delete  = true
    boot         = true
  }
  network_interface {
    subnetwork = google_compute_subnetwork.subnet-a.self_link
    access_config {
    }
  }
  metadata = {
    startup-script      = "${file("./debian10.sh")}"
    serial-port-enable  = "true"
  }
  service_account {
    scopes = ["cloud-platform"]
  }
}

data "google_compute_image" "debian10" {
  family  = "debian-10"
  project = "debian-cloud"
}
data "google_compute_zones" "available" {
}

resource "google_compute_region_instance_group_manager" "gce-mig" {
  name               = "mig-${random_id.id.hex}"
  base_instance_name = "mig-${random_id.id.hex}"
  region             = var.region
  distribution_policy_zones  = data.google_compute_zones.available.names
  named_port {
    name = "https"
    port = 443
  }
  named_port {
    name = "http"
    port = "80"
  }
  version {
    name              = "latest"
    instance_template = google_compute_instance_template.gce-template.id
  }
}
resource "google_compute_region_autoscaler" "gce-scaler" {
  name   = "autoscaler-${random_id.id.hex}"
  target = google_compute_region_instance_group_manager.gce-mig.id

  autoscaling_policy {
    max_replicas    = 3
    min_replicas    = 1
    cooldown_period = 60

    cpu_utilization {
      target = 0.5
    }
  }
}
*/