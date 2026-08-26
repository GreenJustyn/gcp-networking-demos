terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.24"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 6.24"
    }
  }
}

provider "google" {
    project     = var.project-id
    region      = var.regions[0]
}

provider "google-beta" {
    project     = var.project-id
    region      = var.region[0]
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

data "google_compute_image" "debian_image" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_zones" "region_availability" {
  for_each    = toset(var.regions)
  region      = each.value
}

data "google_compute_default_service_account" "default" { }

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = toset(["iap-forwarders"])
  range_type = each.value
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_project_service" "apienable" {
  for_each = toset(var.apis)
  service     = each.value
  disable_on_destroy = false
  disable_dependent_services = true
}

resource "google_compute_project_metadata" "project_meta" {
  metadata = {
    enable-oslogin  = "TRUE"
    enable-guest-attributes = "TRUE"
    "sql-psc-psa${local.suffix}" = path.cwd
  }
}
resource "google_compute_network" "private_network" {
  name = "default${local.suffix}"
}

resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address${local.suffix}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.private_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.private_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
  deletion_policy         = "ABANDON"
}

resource "google_sql_database_instance" "default" {
  name                = "psa-instance${local.suffix}"
  database_version    = "MYSQL_8_0"
  region              = var.regions[0]
  depends_on          = [ google_service_networking_connection.private_vpc_connection ]
  deletion_protection = false
  settings {
    tier = "db-f1-micro"
    availability_type = "ZONAL"
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.private_network.self_link
      enable_private_path_for_google_cloud_services = true
    }
    database_flags {
      name  = "default_authentication_plugin"
      value = "mysql_native_password"
    }
  }
}

resource "google_sql_user" "dbadmin_user" {
  name     = "dbadmin"
  instance = google_sql_database_instance.default.name
  password_wo = "works4me"
}

resource "google_compute_instance" "host_instance" {
  for_each      = { for region in data.google_compute_zones.region_availability: region.region => region.names }
  name          = "inst${local.suffix}-${each.key}"
  machine_type  = "e2-micro"
  zone          = each.value[0]
  metadata            = {
      startup-script      = templatefile("./debian-client.sh.tftpl", { })
  }
  tags = ["allow-hc${local.suffix}", "allow-ssh${local.suffix}"]
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
  network_interface {
    network = google_compute_network.private_network.self_link
    access_config { }
  }
  service_account {
    email = data.google_compute_default_service_account.default.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
}


resource "google_compute_network_firewall_policy" "fw_policy" {
  name        = "fwpolicy${local.suffix}"
  description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
  name              = "fwpolicyassoc${local.suffix}"
  attachment_target = google_compute_network.private_network.id
  firewall_policy   =  google_compute_network_firewall_policy.fw_policy.name
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