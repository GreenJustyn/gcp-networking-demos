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
    #region_zones = {for i in random_shuffle.gcp_zones[var.regions[0]].result: i => null}
    region_zones = var.all_zones ? {for i in data.google_compute_zones.region_availability[var.regions[0]].names: i => null} : {data.google_compute_zones.region_availability[var.regions[0]].names[0] = null}
}
provider "google" {
    project     = var.project-id
    region     = var.regions[0]
}

provider "google-beta" {
    project     = var.project-id
    region     = var.regions[0]
}

data "google_compute_image" "debian_image" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_zones" "region_availability" {
  for_each    = { for region in var.regions : region => null }
  region      = each.value
  status      = "UP"
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "terraform-cwd${local.suffix}" = path.cwd
  }
}

resource "google_project_service" "api_enable" {
    for_each                    = { for api in var.apis : api => null }
    service                     = each.key
    disable_on_destroy          = false
    disable_dependent_services  = true
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    project-id  = var.project-id
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

resource "google_compute_router" "nat_router" {
  name    = "nat-router${local.suffix}"
  network = values(module.google-infra-vpc.vpcs)[0].id
}

resource "google_compute_router_nat" "nat_auto" {
  name                                = "nat${local.suffix}"
  router                              = google_compute_router.nat_router.name
  region                              = google_compute_router.nat_router.region
  nat_ip_allocate_option              = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat  = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_instance_template" "default" {
    name_prefix     = "ilb-tpl${local.suffix}"
    machine_type    = "e2-micro"
    lifecycle {
        create_before_destroy = true
        ignore_changes        = [disk[0].source_image]
    }
      metadata = {
        startup-script = templatefile("./debian-server-npm.sh.tftpl", { })
    }
    disk {
        source_image = data.google_compute_image.debian_image.self_link
    }
    network_interface {
        subnetwork = values(module.google-infra-vpc.subnets)[0].self_link
        # access_config { } # Comment out for no public IP
    }
}

resource "google_compute_instance_from_template" "webservers" {
  for_each  = local.region_zones
  name      = "web-inst${local.suffix}-${each.key}"
  zone      = each.key
  source_instance_template = google_compute_instance_template.default.self_link_unique
  depends_on = [ google_compute_router_nat.nat_auto ]
}

resource "google_compute_instance_group" "webservers" {
  for_each    = local.region_zones
  name        = "web-ig${local.suffix}-${each.key}"
  instances = [
    google_compute_instance_from_template.webservers[each.key].id
  ]
  named_port {
    name = "http"
    port = "80"
  }
  zone = each.key
  lifecycle {
    create_before_destroy = true
  }
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

resource "google_compute_backend_service" "default" {
    name                    = "bs${local.suffix}"
    port_name               = "http"
    protocol                = "HTTP"
    timeout_sec             = 10
    health_checks           = [google_compute_health_check.default.id]
    load_balancing_scheme   = "EXTERNAL_MANAGED"
    dynamic "backend" {
      for_each  = google_compute_instance_group.webservers
      content {
        group           = backend.value.self_link
        balancing_mode  = "UTILIZATION"
      }
    }
    #security_policy         = google_compute_security_policy.policy.id
}

resource "google_compute_url_map" "default" {
    name        = "urlmap${local.suffix}"
    default_service = google_compute_backend_service.default.id
}

resource "google_compute_target_http_proxy" "default" {
    name     = "http-prx${local.suffix}"
    url_map  = google_compute_url_map.default.id
}

resource "google_compute_global_address" "default" {
    name     = "alb-ip${local.suffix}"
}

resource "google_compute_global_forwarding_rule" "default" {
    name                  = "fwd-rule${local.suffix}"
    ip_protocol           = "TCP"
    load_balancing_scheme = "EXTERNAL_MANAGED"
    port_range            = "80"
    target                = google_compute_target_http_proxy.default.id
    ip_address            = google_compute_global_address.default.id
}

/*
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
*/

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

resource "google_compute_network_firewall_policy_rule" "hc_rule" {
  action                  = "allow"
  description             = ""
  direction               = "INGRESS"
  disabled                = false
  enable_logging          = false
  firewall_policy         = google_compute_network_firewall_policy.fw_policy.name
  priority                = 1200
  rule_name               = "hc-allow${local.suffix}"
  match {
    src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["health-checkers"].cidr_blocks_ipv4
    layer4_configs {
      ip_protocol = "tcp"
      ports = [80,443]
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
