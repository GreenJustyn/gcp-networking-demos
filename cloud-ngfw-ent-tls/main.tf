# Set up for https://codelabs.developers.google.com/cloud-ngfw-enterprise-tls
terraform {
  required_providers {
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "~> 5.40"
    }
    google = {
      source = "hashicorp/google"
      version     = "~> 5.40"
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
locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

data "google_compute_image" "debian_image" {
    family  = "debian-11"
    project = "debian-cloud"
}

data "google_compute_zones" "region_availability" {
    region  = var.region
}

data "google_project" "project_info" {
  project_id  = var.project-id
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = toset(["health-checkers", "iap-forwarders"])
  range_type = each.value
}

resource "random_id" "id" {
	  byte_length = 3
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
    "ngfw-ent-tls${local.suffix}" = path.cwd
  }
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

resource "google_network_security_security_profile" "security_profile" {
  provider    = google-beta
  name        = "fw-sp${local.suffix}"
  parent      = "organizations/${var.org-id}"
  description = "Terraform created security profile for ${local.suffix_nodash}"
  type        = "THREAT_PREVENTION"
}

resource "google_network_security_security_profile_group" "security_profile_group" {
  provider                  = google-beta
  name                      = "fw-spg${local.suffix}"
  parent                    = google_network_security_security_profile.security_profile.parent
  description               = "Terraform created security profile group for ${local.suffix_nodash}"
  threat_prevention_profile = google_network_security_security_profile.security_profile.id
}

resource "google_network_security_firewall_endpoint" "fw_endpoint" {
  provider           = google-beta
  name               = "fw-endpoint${local.suffix}"
  parent             = google_network_security_security_profile_group.security_profile_group.parent
  location           = data.google_compute_zones.region_availability.names[0]
  billing_project_id = var.project-id
}

resource "google_network_security_firewall_endpoint_association" "ngfw_association" {
  provider              = google-beta
  name                  = "fw-endpointassoc${local.suffix}"
  parent                = "projects/${var.project-id}"
  location              = google_network_security_firewall_endpoint.fw_endpoint.location
  network               = module.google-infra-vpc.vpcs[module.google-infra-vpc.network_subnets[0].network].id
  firewall_endpoint     = google_network_security_firewall_endpoint.fw_endpoint.id
  tls_inspection_policy = google_network_security_tls_inspection_policy.tls_policy.id
}

resource "google_compute_router" "nat_router" {
  name    = "nat-router${local.suffix}"
  region  = var.region
  network = module.google-infra-vpc.vpcs[module.google-infra-vpc.network_subnets[0].network].id
}

resource "google_compute_address" "nat_address" {
  count  = 1
  name   = "nat-ip${local.suffix}"
  region = google_compute_router.nat_router.region
}

resource "google_compute_router_nat" "nat_manual" {
  name   = "nat${local.suffix}"
  router = google_compute_router.nat_router.name
  region = google_compute_router.nat_router.region
  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = google_compute_address.nat_address.*.self_link
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_address" "host_reservation" {
    name         = "res-${local.suffix}"
    subnetwork   = module.google-infra-vpc.subnets[module.google-infra-vpc.network_subnets[0].subnet_name].self_link
    address_type = "INTERNAL"
    address      = cidrhost(module.google-infra-vpc.subnets[module.google-infra-vpc.network_subnets[0].subnet_name].ip_cidr_range,50)
    region       = var.region
}

data "google_compute_default_service_account" "default_sa" { }

resource "google_compute_instance" "host_instance" {
  name         = "inst${local.suffix}-host"
  machine_type = "e2-micro"
  zone         = data.google_compute_zones.region_availability.names[0]
  metadata            = {
      startup-script      = templatefile("./debian-host.sh.tftpl", {
        private_key = tls_private_key.cert_key.private_key_pem,
        certificate  = join("",concat([google_privateca_certificate.host_certificate.pem_certificate],google_privateca_certificate.host_certificate.pem_certificate_chain))
      })
  }
  tags = ["allow-hc${local.suffix}", "allow-ssh${local.suffix}"]
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
  network_interface {
    subnetwork  = module.google-infra-vpc.subnets[module.google-infra-vpc.network_subnets[0].subnet_name].self_link
    network_ip  = google_compute_address.host_reservation.address
  }
  service_account {
    email = data.google_compute_default_service_account.default_sa.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
}

resource "google_compute_instance_group" "host" {
  name        = "ig${local.suffix}-host"
  instances = [
    google_compute_instance.host_instance.id
  ]
  zone = google_compute_instance.host_instance.zone
}

resource "google_compute_region_backend_service" "host_service" {
  region                = var.region
  name                  = "bs${local.suffix}-host"
  health_checks         = [google_compute_region_health_check.health_check.id]
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  backend {
    group          = google_compute_instance_group.host.self_link
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_region_health_check" "health_check" {
  name               = "hc${local.suffix}-host"
  region             = var.region
  tcp_health_check {
    port = 80
  }
}

resource "google_compute_forwarding_rule" "default" {
  name                  = "fr${local.suffix}-host"
  region                = var.region
  port_range            = 80
  backend_service       = google_compute_region_backend_service.host_service.id
}

resource "google_compute_instance" "client_instance" {
  name         = "inst${local.suffix}-client"
  machine_type = "e2-micro"
  zone         = data.google_compute_zones.region_availability.names[0]
  metadata            = {
      startup-script  = templatefile("./debian-client.sh.tftpl", {
        host_ip       = google_compute_instance.host_instance.network_interface[0].network_ip,
        nlb_ip        = google_compute_forwarding_rule.default.ip_address,
        pem_cert      = google_privateca_certificate_authority.root_ca.pem_ca_certificates[0]
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
  }
  service_account {
    email = data.google_compute_default_service_account.default_sa.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
}


resource "google_tags_tag_key" "tag_key" {
  description = ""
  parent      = "projects/${var.project-id}"
  purpose     = "GCE_FIREWALL"
  short_name  = "vpc-tags${local.suffix}"
  purpose_data = {
    network = "${var.project-id}/${module.google-infra-vpc.vpcs[module.google-infra-vpc.network_subnets[0].network].name}"
  }
}

resource "google_tags_tag_value" "tag_values" {
  for_each    = toset(["client", "server", "quarantine"])
  description = ""
  parent      = "tagKeys/${google_tags_tag_key.tag_key.name}"
  short_name  = "${each.value}${local.suffix}"
}

resource "google_tags_location_tag_binding" "client_binding" {
  parent        = "//compute.googleapis.com/projects/${data.google_project.project_info.number}/zones/${google_compute_instance.client_instance.zone}/instances/${google_compute_instance.client_instance.instance_id}"
  tag_value     = google_tags_tag_value.tag_values["client"].id
  location      = google_compute_instance.client_instance.zone
}

resource "google_tags_location_tag_binding" "host_binding" {
  parent        = "//compute.googleapis.com/projects/${data.google_project.project_info.number}/zones/${google_compute_instance.host_instance.zone}/instances/${google_compute_instance.host_instance.instance_id}"
  tag_value     = google_tags_tag_value.tag_values["server"].id
  location      = google_compute_instance.host_instance.zone
}

resource "google_compute_network_firewall_policy" "ngfw_fw_policy" {
  name        = "ngfwpolicy${local.suffix}"
  description = ""
}

resource "google_compute_network_firewall_policy_association" "ngfw_fw_policy_association" {
  name              = "ngfwpolicyassoc${local.suffix}"
  attachment_target = module.google-infra-vpc.vpcs[module.google-infra-vpc.network_subnets[0].network].id
  firewall_policy   =  google_compute_network_firewall_policy.ngfw_fw_policy.name
}

resource "google_compute_network_firewall_policy_rule" "hc_rule" {
  action                  = "allow"
  description             = ""
  direction               = "INGRESS"
  disabled                = false
  enable_logging          = false
  firewall_policy         = google_compute_network_firewall_policy.ngfw_fw_policy.name
  priority                = 100
  rule_name               = "health-check-allow${local.suffix}"
  target_secure_tags {
    name = "tagValues/${google_tags_tag_value.tag_values["server"].name}"
  }
  match {
    src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["health-checkers"].cidr_blocks_ipv4
    layer4_configs {
      ip_protocol = "tcp"
      ports = [80]
    }
    layer4_configs {
      ip_protocol = "tcp"
      ports = [443]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "iap_rule" {
  action                  = "allow"
  description             = ""
  direction               = "INGRESS"
  disabled                = false
  enable_logging          = false
  firewall_policy         = google_compute_network_firewall_policy.ngfw_fw_policy.name
  priority                = 200
  rule_name               = "iap-allow${local.suffix}"
  target_secure_tags {
    name    = "tagValues/${google_tags_tag_value.tag_values["server"].name}"
  }
  target_secure_tags {
    name    = "tagValues/${google_tags_tag_value.tag_values["client"].name}"
  }
  match {
    src_ip_ranges = data.google_netblock_ip_ranges.ip_ranges["iap-forwarders"].cidr_blocks_ipv4
    layer4_configs {
      ip_protocol = "tcp"
      ports = [22]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "ingress_internal_rule" {
    provider                = google-beta
    action                  = "apply_security_profile_group"
    tls_inspect             = true
    description             = "allow ingress internal traffic from tagged clients"
    direction               = "INGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = google_compute_network_firewall_policy.ngfw_fw_policy.name
    priority                = 800
    rule_name               = "ingress-int-allow${local.suffix}"
    security_profile_group  = "https://networksecurity.googleapis.com/v1/${google_network_security_security_profile_group.security_profile_group.id}"
    target_secure_tags {
      name  = "tagValues/${google_tags_tag_value.tag_values["server"].name}"
    }
    match {
      src_ip_ranges = ["10.0.0.0/8"]
      layer4_configs {
        ip_protocol = "tcp"
        ports = [80,443]
      }
    }
}

resource "google_compute_network_firewall_policy_rule" "egress_out_rule" {
    provider = google-beta
    action                  = "apply_security_profile_group"
    tls_inspect             = true
    description             = "Internet egress rule from client"
    direction               = "EGRESS"
    disabled                = false
    enable_logging          = true
    firewall_policy         = google_compute_network_firewall_policy.ngfw_fw_policy.name
    priority                = 8000
    rule_name               = "egress-internet${local.suffix}"
    security_profile_group  = "https://networksecurity.googleapis.com/v1/${google_network_security_security_profile_group.security_profile_group.id}"
    target_secure_tags      {
      name = "tagValues/${google_tags_tag_value.tag_values["client"].name}"
    }
    match {
      dest_ip_ranges = ["0.0.0.0/0"]
      layer4_configs {
        ip_protocol = "tcp"
        ports = [80,443]
      }
    }
}


## TLS Config from step 7 onwards:
## https://codelabs.developers.google.com/cloud-ngfw-enterprise-tls#6

resource "google_privateca_ca_pool" "root_ca_pool" {
    provider = google-beta
    name = "root-ca-pool${local.suffix}"
    location = var.region
    tier = "ENTERPRISE"
    publishing_options {
        publish_ca_cert = true
        publish_crl = false
    }
    issuance_policy {
        baseline_values {
            ca_options {
                is_ca = false
            }
            key_usage {
                extended_key_usage {
                    server_auth = true
                }
                base_key_usage { }
            }
        }
        maximum_lifetime = "1209600s"
    }
}

resource "google_privateca_certificate_authority" "root_ca" {
    provider = google-beta
    pool = google_privateca_ca_pool.root_ca_pool.name
    certificate_authority_id = "root-ca${local.suffix}"
    location = google_privateca_ca_pool.root_ca_pool.location
    config {
        subject_config {
            subject {
                organization = "Google NGFW Enterprise Test"
                common_name = "NGFW Enterprise Test CA ${local.suffix_nodash}"
            }
        }
        x509_config {
            ca_options {
                is_ca = true
            }
            key_usage {
                base_key_usage {
                    cert_sign = true
                    crl_sign = true
                }
                extended_key_usage {
                    server_auth = true
                }
            }
        }
    }
    key_spec {
        algorithm = "RSA_PKCS1_4096_SHA256"
    }
    deletion_protection                    = false
    skip_grace_period                      = true
    ignore_active_certificates_on_deletion = true
}

#Step 7: Create a service account. This service account will be used for requesting certificates for NGFW Enterprise

resource "google_project_service_identity" "networksecurity_sa" {
  provider = google-beta
  service = "networksecurity.googleapis.com"
}

#Step 7: Set IAM permissions for the service account

resource "google_privateca_ca_pool_iam_binding" "rootca_binding" {
    ca_pool = google_privateca_ca_pool.root_ca_pool.id
    role = "roles/privateca.certificateRequester"
    members = [
        "serviceAccount:${google_project_service_identity.networksecurity_sa.email}"
    ]
}

resource "google_network_security_tls_inspection_policy" "tls_policy" {
    provider              = google-beta
    location              = google_privateca_certificate_authority.root_ca.location
    name                  = "tls-pol${local.suffix}"
    exclude_public_ca_set = false
    #ca_pool               = google_privateca_ca_pool.root_ca_pool.id
    ca_pool               = "projects/mhanline-playpen002/locations/us-central1/caPools/sub-ca-pool2024083001"
    description           = "Test tls inspection policy ${local.suffix_nodash}"
    min_tls_version       = "TLS_1_1"
    tls_feature_profile   = "PROFILE_COMPATIBLE"
    trust_config          = google_certificate_manager_trust_config.ngfw_ent_trust.id
    depends_on            = [
        google_privateca_certificate_authority.root_ca
    ]
}

#Step 7: Create the server certificate

resource "google_privateca_certificate" "host_certificate" {
  provider  = google-beta
  location  = var.region
  pool      = google_privateca_ca_pool.root_ca_pool.name
  lifetime  = "86000s"
  name      = "host-cert${local.suffix}"
  config {
    subject_config  {
      subject {
        organization  = "Google"
        common_name   = "Cloud NGFW Enterprise"
      } 
      subject_alt_name {
        ip_addresses = [ google_compute_address.host_reservation.address ]
      }
    }
    x509_config {
      ca_options {
        is_ca = false
      }
      key_usage {
        base_key_usage {
        }
        extended_key_usage {
        }
      }
    }
    public_key {
      format = "PEM"
      key = base64encode(tls_private_key.cert_key.public_key_pem)
    }
  }
}

resource "tls_private_key" "cert_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

#Step 11 - Trust config

resource "google_certificate_manager_trust_config" "ngfw_ent_trust" {
  name        = "ngfw-trust${local.suffix}"
  description = "Terraform trust config ${local.suffix_nodash}"
  location    = var.region
  trust_stores {
    trust_anchors { 
      pem_certificate = google_privateca_certificate_authority.root_ca.pem_ca_certificates[0]
    }
  }
}
