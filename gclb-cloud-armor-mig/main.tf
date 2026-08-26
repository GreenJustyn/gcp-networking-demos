terraform {
  required_providers {
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 6.38"
    }
    google = {
      source = "hashicorp/google"
      version     = "~> 6.38"
    }
  }
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}
provider "google" {
    project     = var.project-id
    region     = var.regions[0]
}

provider "google-beta" {
    project     = var.project-id
    region     = var.regions[0]
}

data "google_compute_image" "debian-image" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_zones" "region-availability" {
    for_each    = toset(var.regions)
    region  = each.value
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

resource "random_shuffle" "gcp-zones" {
    for_each        = { for region in data.google_compute_zones.region-availability: region.region => region.names }
    input           = [ for zone in each.value : zone ]
    #result_count    = 2
}

resource "random_id" "id" {
	  byte_length = 3
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "terraform-cwd${local.suffix}" = path.cwd
  }
}

resource "google_project_service" "apienable" {
  for_each = toset(var.apis)
  service     = each.value
  disable_on_destroy = false
  disable_dependent_services = true
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    project-id  = var.project-id
    #version     = "1.0.0"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

resource "google_compute_global_address" "default" {
    name     = "l7-xlb-ip${local.suffix}"
}

resource "google_compute_global_forwarding_rule" "default" {
    name                  = "fwd-rule${local.suffix}"
    ip_protocol           = "TCP"
    load_balancing_scheme = "EXTERNAL_MANAGED"
    port_range            = "80"
    target                = google_compute_target_http_proxy.default.id
    ip_address            = google_compute_global_address.default.id
}

resource "google_compute_target_http_proxy" "default" {
    name     = "http-proxy${local.suffix}"
    url_map  = google_compute_url_map.urlmap-a.id
}

resource "google_compute_url_map" "urlmap-a" {
    name        = "urlmap${local.suffix}"
    default_service = google_compute_backend_service.default.id
    host_rule {
        hosts = ["*"]
        path_matcher = "allpaths"
    }
    path_matcher {
        name = "allpaths"
        default_service = google_compute_backend_service.default.id
        path_rule {
            paths = [
                "/group2",
                "/group2/*"
            ]
            service = google_compute_backend_service.default.id
        }
    }
}

resource "google_compute_backend_service" "default" {
    name                    = "bs${local.suffix}"
    port_name               = "http"
    protocol                = "HTTP"
    timeout_sec             = 10
    health_checks           = [google_compute_health_check.default.id]
    load_balancing_scheme   = "EXTERNAL_MANAGED"
    backend {
        group               = module.mig.instance_group
        balancing_mode      = "UTILIZATION"
        capacity_scaler     = 1.0
    }
    security_policy         = google_compute_security_policy.policy.id
}

resource "google_compute_health_check" "default" {
    name               = "hc${local.suffix}"
    check_interval_sec = 1
    timeout_sec        = 1
    http_health_check {
        port_specification = "USE_SERVING_PORT"
        request_path       = "/"
    }
}


module "mig_template" {
    source     = "terraform-google-modules/vm/google//modules/instance_template"
    version    = "8.0.1"
    network    = module.google-infra-vpc.vpcs["net-http-lb"].self_link
    subnetwork = module.google-infra-vpc.subnets["sub-http-lb"].self_link
    service_account = {
        email  = ""
        scopes = ["cloud-platform"]
    }
    access_config = [{
        nat_ip       = null
        network_tier = null
    }]
    name_prefix             = "gclb-mig${local.suffix}"
    startup_script          = templatefile("./gclb-debian.sh.tftpl", {})
    source_image_family     = "debian-12"
    source_image_project    = "debian-cloud"
    tags = [
        "allow-hc${local.suffix}",
        "allow-ssh${local.suffix}"
    ]
}

module "mig" {
  source            = "terraform-google-modules/vm/google//modules/mig"
  version           = "~> 7.9"
  instance_template = module.mig_template.self_link
  region            = var.regions[0]
  #hostname          = "${var.network_prefix}-group1"
  target_size       = 1
  named_ports = [{
    name = "http",
    port = 80
  }]
  network    = module.google-infra-vpc.vpcs["net-http-lb"].self_link
  subnetwork = module.google-infra-vpc.subnets["sub-http-lb"].self_link
    update_policy = [{ 
        type = "PROACTIVE" 
        instance_redistribution_type = "PROACTIVE" 
        minimal_action = "REPLACE" 
        max_surge_percent = null 
        max_unavailable_percent = null 
        max_surge_fixed = 4 
        max_unavailable_fixed = null 
        min_ready_sec = 50 
        replacement_method = "SUBSTITUTE" 
    }] 
}

resource "google_compute_security_policy" "policy" {
  name = "secpol${local.suffix}"
  rule {
    action   = "deny(403)"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["9.9.9.0/24"]
      }
    }
    description = "Deny access to IPs in 9.9.9.0/24"
  }

  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "default rule"
  }
   rule {
    action   = "deny(403)"
    priority = "100"
    match {
      expr {
        expression = <<-EOT
        !(request.path.matches("/status.*|/notifications.*"))
        EOT
      }
    }
  }
}

####
#### Test VMs
####

resource "google_compute_instance" "testvm01" {
    name         = "testvm-consumer-sin${local.suffix}"
    machine_type = "e2-micro"
    zone         = random_shuffle.gcp-zones[var.regions[0]].result[0]
    metadata = {
        startup-script = templatefile("./debian-client.sh.tftpl", {})
    }
    tags = ["allow-ssh${local.suffix}"]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork = module.google-infra-vpc.subnets["sub-http-lb"].self_link
    }
    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }
}

output ipv4_address {
    value = google_compute_global_address.default.address
}

resource "google_compute_network_firewall_policy" "fw_policy" {
    name        = "fwpolicy${local.suffix}"
    description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
  name              = "fwpolicyassoc${local.suffix}"
  attachment_target = values(module.google-infra-vpc.vpcs)[0].id
  firewall_policy   = google_compute_network_firewall_policy.fw_policy.name
}

resource "google_compute_network_firewall_policy_rule" "iap_rule" {
    action                  = "allow"
    description             = ""
    direction               = "INGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = google_compute_network_firewall_policy.fw_policy.name
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
    action                  = "allow"
    description             = ""
    direction               = "INGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = google_compute_network_firewall_policy.fw_policy.name
    priority                = 20000
    rule_name               = "rfc1918-allow${local.suffix}"
    match {
        src_ip_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
        layer4_configs {
        ip_protocol = "all"
        }
    }
}
