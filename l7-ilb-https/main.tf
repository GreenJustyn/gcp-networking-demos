terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.24"
    }
  }
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

data "google_compute_zones" "region_availability" {
    region  = var.region
}
data "google_compute_image" "debian_image" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_default_service_account" "default_sa" { }

provider "google" {
    project    = var.project-id
    region     = var.region
}

provider "google-beta" {
    project    = var.project-id
    region     = var.region
}

resource "random_id" "id" {
	byte_length = 2
}

resource "google_project_service" "apienable" {
    for_each                    = toset(var.apis)
    service                     = each.value
    disable_on_destroy          = false
    disable_dependent_services  = true
}

resource "google_compute_project_metadata" "project_metadata" {
    metadata = {
        enable-oslogin  = "TRUE"
        "l7ilb${local.suffix}" = path.cwd
    }
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

resource "google_compute_region_health_check" "default" {
    name                = "hc-http${local.suffix}"
    region              = var.region
    timeout_sec         = 1
    check_interval_sec  = 10
    https_health_check {
        port_specification = "USE_SERVING_PORT"
    }
    log_config {
        enable = true
    }
}

resource "google_compute_instance_template" "default" {
  name_prefix   =  "ilb-tpl${local.suffix}"
  machine_type  = "e2-small"
  tags          = ["allow-hc${local.suffix}", "allow-ssh${local.suffix}"]
  network_interface {
    network     = values(module.google-infra-vpc.vpcs)[0].id
    subnetwork  = values(module.google-infra-vpc.subnets)[0].id
    access_config { }
  }
  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
  }
  metadata = {
    startup-script  = templatefile("./debian-host.sh.tftpl", {
        private_key = tls_private_key.default.private_key_pem,
        certificate  = tls_self_signed_cert.default.cert_pem
    })
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "default" {
    name = "ilb-ig${local.suffix}"
    base_instance_name         = "ilb-ig"
    version {
        instance_template = google_compute_instance_template.default.self_link_unique
    }
    target_size  = 1
    named_port {
        name = "http"
        port = 80
    }
    named_port {
        name = "https"
        port = 443
    }
#    auto_healing_policies {
#        health_check      = google_compute_region_health_check.default.id
#        initial_delay_sec = 300
#    }
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

# L7 ILB

resource "google_compute_region_backend_service" "default" {
    name                    = "bs${local.suffix}"
    port_name               = "https"
    protocol                = "HTTPS"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    timeout_sec             = 10
    health_checks           = [google_compute_region_health_check.default.id]
    backend {
        group               = google_compute_region_instance_group_manager.default.instance_group
        balancing_mode      = "UTILIZATION"
        capacity_scaler     = 1.0
    }
}

resource "google_compute_address" "default" {
    name         = "ilb-addr${local.suffix}"
    subnetwork   = [for i in module.google-infra-vpc.subnets : i.self_link if i.purpose == "PRIVATE"][0]
    address_type = "INTERNAL"
    purpose      = "SHARED_LOADBALANCER_VIP"
}

resource "google_compute_region_url_map" "default" {
    name            = "url-map-443${local.suffix}"
    default_service = google_compute_region_backend_service.default.id
}

resource "tls_private_key" "default" {
  algorithm = "RSA"
  rsa_bits  = 2048
}
resource "tls_self_signed_cert" "default" {
    private_key_pem       = tls_private_key.default.private_key_pem
    validity_period_hours = 8760
    allowed_uses          = [ "server_auth" ]
    dns_names             = ["*.gcp.internal"]
    ip_addresses          = [ google_compute_address.default.address ]
    subject {
        common_name       = "internal"
        organization      = "Googleyness Inc"
    }
}

resource "google_compute_region_ssl_certificate" "default" {
    name_prefix = "ilbcert${local.suffix}"
    private_key = tls_private_key.default.private_key_pem
    certificate = tls_self_signed_cert.default.cert_pem
    lifecycle {
        create_before_destroy = true
    }
}
resource "google_compute_region_target_https_proxy" "default" {
    name    = "https-proxy-443${local.suffix}"
    url_map = google_compute_region_url_map.default.id
    ssl_certificates = [google_compute_region_ssl_certificate.default.self_link]
}

resource "google_compute_forwarding_rule" "default" {
    name                    = "int-fr-443${local.suffix}"
    ip_protocol             = "TCP"
    port_range              = "443"
    load_balancing_scheme   = "INTERNAL_MANAGED"
    subnetwork              = google_compute_address.default.subnetwork
    ip_address              = google_compute_address.default.id
    target                  = google_compute_region_target_https_proxy.default.id
}


resource "google_compute_instance" "client_instance" {
  name         = "inst${local.suffix}-test"
  machine_type = "e2-micro"
  zone         = data.google_compute_zones.region_availability.names[0]
  metadata            = {
      startup-script  = templatefile("./debian-client.sh.tftpl", {
        ALB_VIP     = google_compute_forwarding_rule.default.ip_address,
        PEM_CERT    = tls_self_signed_cert.default.cert_pem
      })
  }
  tags = ["allow-ssh${local.suffix}"]
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
  network_interface {
    subnetwork = module.google-infra-vpc.subnets[module.google-infra-vpc.network_subnets[0].subnet_name].self_link
    access_config {  }
  }
  service_account {
    email = data.google_compute_default_service_account.default_sa.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
}


### DNS ###

resource "google_dns_managed_zone" "gcp_internal" {
    name        = "gcp-internal${local.suffix}"
    dns_name    = "gcp.internal."
    description = "Zone for gcp.internal"
    visibility  = "private"
    private_visibility_config {
        networks {
            network_url = values(module.google-infra-vpc.vpcs)[0].id
        }
    }
}

resource "google_dns_record_set" "ilb_record" {
  name          = "ilb.${google_dns_managed_zone.gcp_internal.dns_name}"
  managed_zone  = google_dns_managed_zone.gcp_internal.name
  type          = "A"
  ttl           = 300
  rrdatas       = [ google_compute_address.default.address ]
}
/*
# Can't get the IP of an instance group with ephemeral IPs.
resource "google_dns_record_set" "compute_record" {
  name         = "vm.${google_dns_managed_zone.gcp_internal.dns_name}"
  managed_zone = google_dns_managed_zone.gcp_internal.name
  type         = "A"
  ttl          = 300
  rrdatas = [ google_compute_instance.frontend.network_interface[0].access_config[0].nat_ip ]
}
*/