#Copyright ${YEAR} Google LLC
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version     = "~> 6.25"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "6.14"
    }
  }
}

provider "google" {
    project     = var.project-id-producer
}

provider "google-beta" {
    project     = var.project-id-producer
}

data "google_compute_image" "debian_img" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_default_service_account" "default" {
    for_each = toset([var.project-id-producer, var.project-id-consumer])
    project = each.key
}

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = toset(["iap-forwarders"])
  range_type = each.value
}
data "google_compute_zones" "region_availability" {
    for_each    = local.regions
    region      = each.key
}

locals {
    region    = tolist(distinct(flatten([for val in var.vpcs:  val.subnets[*].region])))[0]
    regions         = toset(flatten([ for val in var.vpcs.*.subnets[*].*.region: val]))
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
    apis_list       = { for combo in setproduct(toset([var.project-id-producer, var.project-id-consumer]), var.apis): "${combo[0]}_${combo[1]}" => combo }
}

resource "random_shuffle" "gcp_zones" {
    for_each    = data.google_compute_zones.region_availability
    input       = each.value.names
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_compute_project_metadata" "project_metadata" {
    for_each    = toset([var.project-id-producer, var.project-id-consumer])
    project     = each.key
    metadata = {
        enable-oslogin  = "TRUE"
        "swp-psc-sni-multi${local.suffix}-cwd" = path.cwd
    }
}

resource "google_project_service" "apienable" {
    for_each            = local.apis_list
    project             = each.value[0]
    service             = each.value[1]
    disable_on_destroy  = false
    disable_dependent_services  = true
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

resource "google_compute_instance" "testvms" {
    for_each            = google_compute_forwarding_rule.psc_ilb_consumer
    project             = each.value.project
    name                = "vm-${each.key}${local.suffix}"
    machine_type        = "e2-micro"
    zone                = random_shuffle.gcp_zones[each.key].result[0]
    metadata            = {
        startup-script      = templatefile("./debian-client.sh.tftpl", { })
    }
    tags = ["allow-iap-ssh${local.suffix}"]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian_img.self_link
        }
    }
    network_interface {
        subnetwork  = [for i in module.google-infra-vpc.subnets : i.id if i.purpose == "PRIVATE" && i.project == each.value.project && i.region == each.key && strcontains(i.name, "consumer")][0]
    }
    service_account {
        scopes = ["cloud-platform"]
        email = data.google_compute_default_service_account.default[each.value.project].email
    }
}

resource "google_compute_instance" "testvms_producer" {
    for_each            = google_compute_forwarding_rule.psc_ilb_consumer
    project             = var.project-id-producer
    name                = "producer-${each.key}${local.suffix}"
    machine_type        = "e2-micro"
    zone                = random_shuffle.gcp_zones[each.key].result[0]
    metadata            = {
        startup-script      = templatefile("./debian-client.sh.tftpl", { })
    }
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian_img.self_link
        }
    }
    network_interface {
        subnetwork  = [for i in module.google-infra-vpc.subnets : i.id if i.purpose == "PRIVATE" && i.project == var.project-id-producer && i.region == each.key && strcontains(i.name, "producer")][0]
    }
    service_account {
        scopes = ["cloud-platform"]
        email = data.google_compute_default_service_account.default[var.project-id-producer].email
    }
}
#################
/*
resource "google_project_service_identity" "swp_tls_sa" {
  provider = google-beta
  service = "networksecurity.googleapis.com"
}

resource "google_privateca_ca_pool" "swp_tlsinsp_rootca_pool" {
    name = "swp-tlsinsp-rootca-pool${local.suffix}"
    location = local.region
    tier = "DEVOPS"
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

resource "google_privateca_certificate_authority" "swp_tlsinsp_root_ca" {
    pool = google_privateca_ca_pool.swp_tlsinsp_rootca_pool.name
    certificate_authority_id = "swp-tlsinsp-root-ca${local.suffix}"
    location = google_privateca_ca_pool.swp_tlsinsp_rootca_pool.location
    config {
        subject_config {
            subject {
                organization = "SWP Org"
                common_name = "swp-tlsinsp-root-ca"
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
                    server_auth = false
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

resource "google_privateca_ca_pool_iam_binding" "rootca_binding" {
    ca_pool = google_privateca_ca_pool.swp_tlsinsp_rootca_pool.id
    role = "roles/privateca.certificateManager"
    members = [
        "serviceAccount:${google_project_service_identity.swp_tls_sa.email}"
    ]
}

resource "google_privateca_ca_pool" "swp_tlsinsp_ca_subpool" {
    for_each    = local.regions
    location    = each.key
    name        = "swp-ca-subpool-${each.key}${local.suffix}"
    tier        = "DEVOPS"
    publishing_options {
        publish_ca_cert = true
        publish_crl = false
    }
    issuance_policy {
        baseline_values {
            ca_options {
                is_ca = true
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

resource "google_privateca_certificate_authority" "swp_tlsinsp_sub_ca" {
    for_each                    = local.regions
    location                    = each.key
    pool                        = google_privateca_ca_pool.swp_tlsinsp_ca_subpool[each.key].name
    certificate_authority_id    = "swp-sub-ca-${each.key}${local.suffix}"
    type                        = "SUBORDINATE"
    subordinate_config {
        certificate_authority = google_privateca_certificate_authority.swp_tlsinsp_root_ca.name
    }
    config {
        subject_config {
            subject {
                organization    = "SWP Org"
                common_name     = "swp-tlsinsp-sub-ca-${local.region}"
        }
    }
    x509_config {
      ca_options {
        is_ca = true
        max_issuer_path_length = 0
      }
      key_usage {
        base_key_usage {
          cert_sign = true
          crl_sign = true
        }
        extended_key_usage {
          server_auth = true
          client_auth = false
        }
      }
    }
    }
    lifetime = "86400s"
    key_spec {
        algorithm = "EC_P256_SHA256"
    }
    deletion_protection                    = false
    skip_grace_period                      = true
    ignore_active_certificates_on_deletion = true
}

resource "google_network_security_tls_inspection_policy" "default" {
    for_each    = local.regions
    location    = each.key
    name        = "tls-pol${local.suffix}"
    ca_pool     = google_privateca_ca_pool.swp_tlsinsp_ca_subpool[each.key].id
    depends_on = [
        google_privateca_certificate_authority.swp_tlsinsp_sub_ca
    ]
}
*/

resource "google_network_security_gateway_security_policy" "swp_gsp" {
    project         = var.project-id-producer
    for_each        = local.regions
    location        = each.key
    name            = "swp-allow-hosts${local.suffix}-${each.key}"
    #tls_inspection_policy = google_network_security_tls_inspection_policy.default[each.key].id
}

resource "google_network_security_gateway_security_policy_rule" "swp_allow" {
    for_each                = google_network_security_gateway_security_policy.swp_gsp
    project                 = each.value.project
    location                = each.value.location
    name                    = "swprule${local.suffix}-${each.value.location}"
    gateway_security_policy = google_network_security_gateway_security_policy.swp_gsp[each.key].name
    enabled                 = true  
    priority                = 123
    session_matcher         = "host().endsWith('com')"
    basic_profile           = "ALLOW"
}

resource "google_network_services_gateway" "default" {
    for_each                = google_network_security_gateway_security_policy.swp_gsp
    project                 = each.value.project
    location                = each.key
    name                    = "gw${local.suffix}-${each.key}"
    type                    = "SECURE_WEB_GATEWAY"
    ports                   = ["80", "443"]
    scope                   = "scope${local.suffix}"
    gateway_security_policy = google_network_security_gateway_security_policy.swp_gsp[each.key].id
    network                 = [for i in module.google-infra-vpc.vpcs: i.id if strcontains(i.name,"producer") && i.project == each.value.project ][0]
    subnetwork              = [for i in module.google-infra-vpc.subnets : i.id if i.purpose == "PRIVATE" && i.project == each.value.project && i.region == each.key && strcontains(i.name, "producer")][0]
    delete_swg_autogen_router_on_destroy = true
    routing_mode            = "NEXT_HOP_ROUTING_MODE"
}

resource "google_compute_service_attachment" "swp_svc_attachment" {
    provider                = google-beta
    for_each                = google_network_services_gateway.default
    project                 = each.value.project
    name                    = "svc-attach${local.suffix}-${each.key}"
    region                  = each.value.location
    connection_preference   = "ACCEPT_AUTOMATIC"
    enable_proxy_protocol   = false
    nat_subnets             = [for i in module.google-infra-vpc.subnets : i.id if i.purpose == "PRIVATE_SERVICE_CONNECT" && i.region == each.key && i.project == each.value.project && strcontains(i.name, "producer")]
    #We need to use the specific google-beta provider. Regression in 6.20 or so, which fails on target_service. TO-Do: Log bug.
    target_service          = "//networkservices.googleapis.com/${google_network_services_gateway.default[each.key].id}"
}

# Consumer Side

resource "google_compute_address" "psc_ilb_consumer_address" {
    for_each        = google_compute_service_attachment.swp_svc_attachment
    project         = var.project-id-consumer
    name            = "psc-swp-add${local.suffix}-${each.key}"
    region          = each.key
    subnetwork      = [for i in module.google-infra-vpc.subnets : i.id if i.purpose == "PRIVATE" && i.project == var.project-id-consumer && i.region == each.key && strcontains(i.name, "consumer")][0]
    address_type    = "INTERNAL"
}

resource "google_compute_forwarding_rule" "psc_ilb_consumer" {
    for_each                = google_compute_service_attachment.swp_svc_attachment
    project                 = var.project-id-consumer
    name                    = "swp-fr${local.suffix}-${each.key}"
    region                  = each.key
    target                  = each.value.id
    load_balancing_scheme   = ""
    network                 = [for i in module.google-infra-vpc.vpcs: i.id if strcontains(i.name,"consumer") && i.project == var.project-id-consumer ][0]
    ip_address              = google_compute_address.psc_ilb_consumer_address[each.key].id
}

resource "google_dns_managed_zone" "microsoftupdate_zone" {
    name        = "microsoftupdate${local.suffix}"
    dns_name    = "windowsupdate.microsoft.com."
    description = "Zone for MSUpdates"
    visibility  = "private"
    private_visibility_config {
        networks {
            network_url = [for i in module.google-infra-vpc.vpcs: i.id if strcontains(i.name,"consumer") && i.project == var.project-id-consumer ][0]
        }
    }
}

resource "google_dns_record_set" "swp_geo" {
    name         = google_dns_managed_zone.microsoftupdate_zone.dns_name
    managed_zone = google_dns_managed_zone.microsoftupdate_zone.name
    type         = "A"
    ttl          = 300
    routing_policy {
        dynamic "geo" {
            for_each    = google_compute_forwarding_rule.psc_ilb_consumer
            content {
                location    = geo.key
                rrdatas     = [ google_compute_address.psc_ilb_consumer_address[geo.key].address ]
            }
        }
    }
}

# Firewall

resource "google_compute_network_firewall_policy" "fw_policy" {
    for_each    = toset([var.project-id-producer, var.project-id-consumer])
    project     = each.value
    name        = "fwpolicy${local.suffix}-${each.value}"
    description = ""
}

resource "google_compute_network_firewall_policy_association" "fw_policy_association" {
  for_each          = module.google-infra-vpc.vpcs
  project           = each.value.project
  name              = "fwpolicyassoc${local.suffix}-${each.key}"
  attachment_target = each.value.id
  firewall_policy   = google_compute_network_firewall_policy.fw_policy[each.value.project].name
}

resource "google_compute_network_firewall_policy_rule" "iap_rule" {
    for_each                = google_compute_network_firewall_policy.fw_policy
    project                 = each.value.project
    action                  = "allow"
    description             = ""
    direction               = "INGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = google_compute_network_firewall_policy.fw_policy[each.value.project].name
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
    for_each                = google_compute_network_firewall_policy.fw_policy
    project                 = each.value.project
    action                  = "allow"
    description             = ""
    direction               = "INGRESS"
    disabled                = false
    enable_logging          = false
    firewall_policy         = google_compute_network_firewall_policy.fw_policy[each.value.project].name
    priority                = 20000
    rule_name               = "rfc1918-allow${local.suffix}"
    match {
        src_ip_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
        layer4_configs {
        ip_protocol = "all"
        }
    }
}
