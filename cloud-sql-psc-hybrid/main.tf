provider "google" {
  #version     = "~> 3.28.0"
  project     = var.project-id
  region      = var.region-1
}
provider "google-beta" {
  project     = var.project-id
  region      = var.region-1
}
locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

data "google_compute_image" "debian_image" {
    family  = "debian-11"
    project = "debian-cloud"
}

data "google_compute_zones" "region_availability" {
    region  = var.region-1
}

resource "random_id" "id" {
	  byte_length = 4
}
resource "random_password" "vpnpassphrase" {
  length           = 16
  special          = false
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
    enable-osconfig = "TRUE"
    enable-guest-attributes = "TRUE"
    "sql-psc-hybrid${local.suffix}" = path.cwd
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

#DNS peering for Cloud SQL to on-prem VPC.
resource "google_dns_managed_zone" "onprem_hub_peer" {
  name        = "onprem-hub-peering${local.suffix}"
  dns_name    = "sql.goog."
  description = "Cloud SQL Peering"
  visibility = "private"
  private_visibility_config {
    networks {
      network_url = module.google-infra-vpc.vpcs["vpc-onprem"].id
    }
  }
  peering_config {
    target_network {
      network_url = module.google-infra-vpc.vpcs["vpc-hub"].id
    }
  }
}

#DNS zone for Cloud SQL resolution
resource "google_dns_managed_zone" "cloud_sql_hub" {
  name        = "sql-goog-hub${local.suffix}"
  dns_name    = "sql.goog."
  description = "private zone for Cloud SQL DNS names"
  visibility = "private"
  private_visibility_config {
    networks {
      network_url = module.google-infra-vpc.vpcs["vpc-hub"].id
    }
  }
}
resource "google_dns_managed_zone" "cloud_sql_isolated" {
  name        = "sql-goog-isol${local.suffix}"
  dns_name    = "sql.goog."
  description = "private zone for Cloud SQL DNS names"
  visibility = "private"
  private_visibility_config {
    networks {
      network_url = module.google-infra-vpc.vpcs["vpc-isolated"].id
    }
  }
}

resource "google_dns_record_set" "sql_goog_a_record_hub" {
  name    = google_sql_database_instance.psc_sql.dns_name
  type    = "A"
  ttl     = 300
  managed_zone = google_dns_managed_zone.cloud_sql_hub.name
  rrdatas = [ google_compute_forwarding_rule.psc_hub_endpoint.ip_address ]
}
resource "google_dns_record_set" "sql_goog_a_record_isolated" {
  name    = google_sql_database_instance.psc_sql.dns_name
  type    = "A"
  ttl     = 300
  managed_zone = google_dns_managed_zone.cloud_sql_isolated.name
  rrdatas = [ google_compute_forwarding_rule.psc_isolated_endpoint.ip_address ]
}

#VPN

resource "google_compute_ha_vpn_gateway" "hub_gateway" {
  #provider = google-beta
  region   = var.region-1
  name     = "hub-vpn1${local.suffix}"
  network  = module.google-infra-vpc.vpcs["vpc-hub"].id
}
resource "google_compute_ha_vpn_gateway" "onprem_gateway" {
  #provider = google-beta
  region   = var.region-1
  name     = "onprem-vpn1${local.suffix}"
  network  = module.vpc-onprem.network_self_link
}

resource "google_compute_router" "router_hub" {
  #provider = google-beta
  name     = "ha-vpn-hub-rtr${local.suffix}"
  network  = module.google-infra-vpc.vpcs["vpc-hub"].id
  bgp {
    asn = 64514
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]
    advertised_ip_ranges {
      range = "10.10.192.0/28"
    }
  }
}
resource "google_compute_router" "router_onprem" {
  #provider = google-beta
  name     = "ha-vpn-onprem-rt${local.suffix}"
  network  = module.google-infra-vpc.vpcs["vpc-onprem"].id
  bgp {
    asn = 64515
  }
}

resource "google_compute_vpn_tunnel" "hub_tunnel1" {
  #provider              = google-beta
  name                  = "ha-vpn-hub-tun1${local.suffix}"
  region                = var.region-1
  vpn_gateway           = google_compute_ha_vpn_gateway.hub_gateway.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.onprem_gateway.id
  shared_secret         = random_password.vpnpassphrase.result
  router                = google_compute_router.router_hub.id
  vpn_gateway_interface = 0
}
resource "google_compute_vpn_tunnel" "hub_tunnel2" {
  #provider              = google-beta
  name                  = "ha-vpn-hub-tun2${local.suffix}"
  region                = var.region-1
  vpn_gateway           = google_compute_ha_vpn_gateway.hub_gateway.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.onprem_gateway.id
  shared_secret         = random_password.vpnpassphrase.result
  router                = google_compute_router.router_hub.id
  vpn_gateway_interface = 1
}

resource "google_compute_vpn_tunnel" "onprem_tunnel1" {
  #provider              = google-beta
  name                  = "ha-vpn-onprem-tun1${local.suffix}"
  region                = var.region-1
  vpn_gateway           = google_compute_ha_vpn_gateway.onprem_gateway.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.hub_gateway.id
  shared_secret         = random_password.vpnpassphrase.result
  router                = google_compute_router.router_onprem.id
  vpn_gateway_interface = 0
}
resource "google_compute_vpn_tunnel" "onprem_tunnel2" {
  #provider              = google-beta
  name                  = "ha-vpn-onprem-tun2${local.suffix}"
  region                = var.region-1
  vpn_gateway           = google_compute_ha_vpn_gateway.onprem_gateway.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.hub_gateway.id
  shared_secret         = random_password.vpnpassphrase.result
  router                = google_compute_router.router_onprem.id
  vpn_gateway_interface = 1
}

resource "google_compute_router_interface" "router_hub_int1" {
  #provider   = google-beta
  name       = "router-hub-int1${local.suffix}"
  router     = google_compute_router.router_hub.name
  region     = var.region-1
  ip_range   = "169.254.0.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.hub_tunnel1.name
}

resource "google_compute_router_peer" "router_hub_peer1" {
  #provider                  = google-beta
  name                      = "router-hub-peer1${local.suffix}"
  router                    = google_compute_router.router_hub.name
  region                    = var.region-1
  peer_ip_address           = "169.254.0.2"
  peer_asn                  = 64515
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_hub_int1.name
}

resource "google_compute_router_interface" "router_hub_int2" {
  #provider   = google-beta
  name       = "router-hub-int2${local.suffix}"
  router     = google_compute_router.router_hub.name
  region     = var.region-1
  ip_range   = "169.254.1.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.hub_tunnel2.name
}

resource "google_compute_router_peer" "router_hub_peer2" {
  #provider                  = google-beta
  name                      = "router1-peer2${local.suffix}"
  router                    = google_compute_router.router_hub.name
  region                    = var.region-1
  peer_ip_address           = "169.254.1.2"
  peer_asn                  = 64515
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_hub_int2.name
}

resource "google_compute_router_interface" "router_onprem_int1" {
  #provider   = google-beta
  name       = "router-onprem-int1${local.suffix}"
  router     = google_compute_router.router_onprem.name
  region     = var.region-1
  ip_range   = "169.254.0.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.onprem_tunnel1.name
}

resource "google_compute_router_peer" "router_onprem_peer1" {
  #provider                  = google-beta
  name                      = "router-onprem-peer1${local.suffix}"
  router                    = google_compute_router.router_onprem.name
  region                    = var.region-1
  peer_ip_address           = "169.254.0.1"
  peer_asn                  = 64514
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_onprem_int1.name
}

resource "google_compute_router_interface" "router_onprem_int2" {
  #provider   = google-beta
  name       = "router-onprem-int2${local.suffix}"
  router     = google_compute_router.router_onprem.name
  region     = var.region-1
  ip_range   = "169.254.1.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.onprem_tunnel2.name
}

resource "google_compute_router_peer" "router_onprem_peer2" {
  #provider                  = google-beta
  name                      = "router-onprem-peer2${local.suffix}"
  router                    = google_compute_router.router_onprem.name
  region                    = var.region-1
  peer_ip_address           = "169.254.1.1"
  peer_asn                  = 64514
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.router_onprem_int2.name
}

resource "google_sql_database_instance" "psc_sql" {
  name             = "psc-instance${local.suffix}"
  database_version = "MYSQL_8_0"
  deletion_protection = false
  settings {
    tier    = "db-f1-micro"
    ip_configuration {
      psc_config {
        psc_enabled = true
        allowed_consumer_projects = [ var.project-id ]
      }
      ipv4_enabled = false
    }
    database_flags {
      name  = "default_authentication_plugin"
      value = "mysql_native_password"
    }
    availability_type = "ZONAL"
  }
}

resource "google_sql_user" "dbadmin_user" {
  name     = "dbadmin"
  instance = google_sql_database_instance.psc_sql.name
  password = "works4me"
}

resource "google_compute_address" "psc_ip_isolated" {
  name         = "psc-isol-ip${local.suffix}"
  subnetwork   = module.vpc-isolated.subnets_ids[0]
  address_type = "INTERNAL"
  address      = cidrhost(module.vpc-isolated.subnets_ips[0],100)
  region       = module.vpc-isolated.subnets_regions[0]
}

resource "google_compute_address" "psc_ip_hub" {
  name         = "psc-hub-ip${local.suffix}"
  subnetwork   = module.vpc-hub.subnets_ids[0]
  address_type = "INTERNAL"
  address      = cidrhost(module.vpc-hub.subnets_ips[0],100)
  region       = module.vpc-hub.subnets_regions[0]
}

resource "google_compute_forwarding_rule" "psc_hub_endpoint" {
  name                    = "psc-hub-endpoint${local.suffix}"
  region                  = google_compute_address.psc_ip_hub.region
  load_balancing_scheme   = ""
  target                  = google_sql_database_instance.psc_sql.psc_service_attachment_link
  network                 = module.vpc-hub.network_id
  ip_address              = google_compute_address.psc_ip_hub.id
  allow_psc_global_access = true
}
resource "google_compute_forwarding_rule" "psc_isolated_endpoint" {
  name                    = "psc-isol-endpoint${local.suffix}"
  region                  = google_compute_address.psc_ip_isolated.region
  load_balancing_scheme   = ""
  target                  = google_sql_database_instance.psc_sql.psc_service_attachment_link
  network                 = module.vpc-isolated.network_id
  ip_address              = google_compute_address.psc_ip_isolated.id
  allow_psc_global_access = true
}

resource "google_service_account" "compute_sa" {
  account_id   = "compute-engine-sa${local.suffix}"
  display_name = "SA for VM Instance"
}
resource "google_project_iam_member" "sa_roles" {
  for_each = toset(["roles/cloudsql.viewer", "roles/cloudsql.client"])
  project = var.project-id
  role    = each.value
  member  = google_service_account.compute_sa.member
}

resource "google_compute_instance" "hub_instance" {
  name         = "inst${local.suffix}-hub01"
  machine_type = "e2-micro"
  zone         = data.google_compute_zones.region_availability.names[0]
  metadata = {  }
  tags = ["allow-hc${local.suffix}", "allow-ssh${local.suffix}"]
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
  network_interface {
    subnetwork = module.vpc-hub.subnets_self_links[0]
    access_config {
      // Ephemeral IP
    }
  }
  metadata_startup_script  = templatefile("./debian-11-client.sh.tftpl", { project = var.project-id, region = var.region-1, sqlinstance = google_sql_database_instance.psc_sql.name, dnsname =  google_sql_database_instance.psc_sql.dns_name})
  service_account {
    email  = google_service_account.compute_sa.email
    scopes = ["cloud-platform"]
  }
}

resource "google_compute_instance" "onprem_instance" {
  name         = "inst${local.suffix}-onp01"
  machine_type = "e2-micro"
  zone         = data.google_compute_zones.region_availability.names[0]
  metadata = {  }
  tags = ["allow-hc${local.suffix}", "allow-ssh${local.suffix}"]
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
  network_interface {
    subnetwork = module.vpc-onprem.subnets_self_links[0]
    access_config {
      // Ephemeral IP
    }
  }
  metadata_startup_script  = templatefile("./debian-11-client.sh.tftpl", { project = var.project-id, region = var.region-1, sqlinstance = google_sql_database_instance.psc_sql.name, dnsname =  google_sql_database_instance.psc_sql.dns_name })
  service_account {
    email  = google_service_account.compute_sa.email
    scopes = ["cloud-platform"]
  }
}

resource "google_compute_instance" "isolvpc_instance" {
  name         = "inst${local.suffix}-isol01"
  machine_type = "e2-micro"
  zone         = data.google_compute_zones.region_availability.names[0]
  metadata = {  }
  tags = ["allow-hc${local.suffix}", "allow-ssh${local.suffix}"]
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
  network_interface {
    subnetwork = module.vpc-isolated.subnets_self_links[0]
    access_config {
      // Ephemeral IP
    }
  }
  metadata_startup_script  = templatefile("./debian-11-client.sh.tftpl", { project = var.project-id, region = var.region-1, sqlinstance = google_sql_database_instance.psc_sql.name, dnsname =  google_sql_database_instance.psc_sql.dns_name })
  service_account {
    email  = google_service_account.compute_sa.email
    scopes = ["cloud-platform"]
  }
}