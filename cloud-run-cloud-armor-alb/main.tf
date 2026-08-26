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

provider "google" {
  project         = var.project-id
  region          = var.region
  billing_project = var.project-id
}
provider "google-beta" {
  project         = var.project-id
  region          = var.region
  billing_project = var.project-id
}

locals {
  suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
  suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

data "google_netblock_ip_ranges" "netblock" {
    range_type = "cloud-netblocks"
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = { "iap-forwarders" = null, "health-checkers" = null }
  range_type = each.key
}

data "google_compute_default_service_account" "default_sa" { }


resource "random_id" "id" {
	byte_length = 2
}

resource "google_project_service" "apienable" {
    for_each                    = { for api in var.apis : api => null }
    service                     = each.key
    disable_on_destroy          = false
    disable_dependent_services  = true
}


resource "google_compute_project_metadata" "project_metadata" {
    metadata = {
        #enable-oslogin  = "TRUE"
        "cloud-run-json${local.suffix}-cwd" = path.cwd
    }
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
    depends_on = [ module.google-infra-vpc ]
    project-id = var.project-id
}


resource "google_storage_bucket" "cloud_run_bucket" {
  name          = "cloudrun-mount${local.suffix}"
  location      = "ASIA"
  force_destroy = true
}

resource "google_storage_bucket_iam_member" "all_users_viewers" {
  bucket = google_storage_bucket.cloud_run_bucket.name
  role   = "roles/storage.legacyObjectReader"
  member = "allUsers"
}

resource "google_storage_bucket_iam_member" "compute_sa_bucket_admin" {
  bucket = google_storage_bucket.cloud_run_bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${data.google_compute_default_service_account.default_sa.email}"
}

resource "google_storage_bucket_object" "db_js" {
  name   = "db.js"
  source = "./db.js"
  bucket = google_storage_bucket.cloud_run_bucket.name
}
resource "google_storage_bucket_object" "db_json" {
  name   = "db.json"
  source = "./db.json"
  bucket = google_storage_bucket.cloud_run_bucket.name
}
resource "google_storage_bucket_object" "middleware_json" {
  name   = "middleware.json"
  source = "./middleware.json"
  bucket = google_storage_bucket.cloud_run_bucket.name
}
resource "google_cloud_run_v2_service" "json_svc" {
    name     = "cloudrun-json${local.suffix}"
    location = var.region
    ingress = "INGRESS_TRAFFIC_ALL"
    deletion_protection = false
    template {
        containers {
            image = "vimagick/json-server:latest"
            volume_mounts {
                name = "datapath"
                mount_path = "/data"
            }
            args = ["-w", "db.json"]
            startup_probe {
                initial_delay_seconds = 0
                timeout_seconds = 60
                period_seconds = 60
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
        volumes {
            name = "datapath"
            gcs {
                bucket    = google_storage_bucket.cloud_run_bucket.name
            }
        }
    }
}
/*
resource "google_cloud_run_v2_service" "json_svc" {
    name     = "cloudrun-json${local.suffix}"
    location = var.region
    ingress = "INGRESS_TRAFFIC_ALL"
    deletion_protection = false
    template {
        containers {
            image = "codfish/json-server:0.17.3"
            volume_mounts {
                name = "datapath"
                mount_path = "/data"
            }
            args = ["/app/db.json"]
            startup_probe {
                initial_delay_seconds = 0
                timeout_seconds = 60
                period_seconds = 60
                failure_threshold = 1
                tcp_socket {
                    port = 80
                    #port = 3000
                }
            }
            ports {
                container_port = 80
                #container_port = 3000
            }
        }
        volumes {
            name = "datapath"
            gcs {
                bucket    = google_storage_bucket.cloud_run_bucket.name
            }
        }
    }
}
*/

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
    #security_policy = google_compute_security_policy.security-policy-1.self_link
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

#
#Cloud Armor
#
/*
resource "google_compute_security_policy" "security-policy-1" {
    name        = "ca-secpol${local.suffix}"
    advanced_options_config {
      json_parsing  = "STANDARD"
      #log_level     = "NORMAL"
      log_level     = "VERBOSE"
    }
    adaptive_protection_config {
        layer_7_ddos_defense_config {
            enable  = true
          }
    }
    rule {
        action   = "deny(403)"
        priority = "500"
        match {
            expr {
                expression = "int(request.headers[\"content-length\"]) > 8192"
            }
        }
    }
    rule {
        action      = "deny(403)"
        priority    = "1001"
        description = "Cross-site scripting"
        match {
            expr {
                expression = "evaluatePreconfiguredWaf(\"xss-v33-stable\", {\"sensitivity\":3})"
            }
        }
    }
    rule {
        action      = "deny(403)"
        priority    = "1002"
        description = "LFI"
        match {
            expr {
                expression = "evaluatePreconfiguredWaf(\"lfi-v33-stable\", {\"sensitivity\":4})"
            }
        }
    }
    rule {
        action      = "deny(403)"
        priority    = "1003"
        description = "RCE"
        match {
            expr {
                expression = "evaluatePreconfiguredWaf(\"rce-v33-stable\", {\"sensitivity\":4})"
            }
        }
    }
    rule {
        action      = "deny(403)"
        priority    = "1004"
        description = "Block Scanner such as well-known security scanners, scripting HTTP clients, and web crawlers"
        match {
            expr {
                #expression = "evaluatePreconfiguredWaf(\"scannerdetection-v33-stable\", {\"sensitivity\":0})"
                expression = "evaluatePreconfiguredWaf(\"scannerdetection-v33-stable\", {\"sensitivity\":2})"
            }
        }
    }
    rule {
        action      = "deny(403)"
        priority    = "1005"
        description = "Block HTTP Protocol Attacks such as CR LF etc"
        match {
            expr {
                #expression = "evaluatePreconfiguredWaf(\"protocolattack-v33-stable\", {\"sensitivity\":4})"
                expression = "evaluatePreconfiguredWaf(\"protocolattack-v33-stable\", {\"sensitivity\":4, \"opt_out_rule_ids\": [\"owasp-crs-v030301-id921130-protocolattack\", \"owasp-crs-v030301-id921151-protocolattack\", \"owasp-crs-v030301-id921120-protocolattack\"]})"

            }
        }
    }
    rule {
        action      = "deny(403)"
        priority    = "1006"
        description = "Block Session Fixation"
        match {
            expr {
                #expression = "evaluatePreconfiguredWaf(\"sessionfixation-v33-stable\", {\"sensitivity\":0})"
                expression = "evaluatePreconfiguredWaf(\"sessionfixation-v33-stable\", {\"sensitivity\":4})"
            }
        }
    }
# Requires CA MPP
    rule {
        action      = "deny(403)"
        priority    = "1020"
        description = "NTI-Malicious IPs"
        match {
            expr {
                expression = "evaluateThreatIntelligence(\"iplist-known-malicious-ips\")"
            }
        }
    }
    dynamic rule {
        for_each = { for index, ipv4_blocks in chunklist(data.google_netblock_ip_ranges.netblock.cidr_blocks_ipv4, 10) : index => ipv4_blocks }
        content {
            action      = "allow"
            priority    = sum([rule.key,2000])
            match {
                versioned_expr = "SRC_IPS_V1"
                config {
                    src_ip_ranges   = rule.value
                }
            }
            description = "Cloud IP Ranges allow"
        }
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
        description = "Default allow"
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
