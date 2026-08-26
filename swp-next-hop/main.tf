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
      version     = "~> 6.26"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version     = "6.14"
    }
  }
}

provider "google" {
    project     = var.project-id
}

provider "google-beta" {
    project     = var.project-id
}

data "google_compute_image" "debian_img" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_default_service_account" "default" { }

data "google_netblock_ip_ranges" "ip_ranges" {
  for_each = toset(["iap-forwarders"])
  range_type = each.value
}
data "google_compute_zones" "region_availability" {
    for_each    = local.regions
    region      = each.key
}

locals {
    region          = [for region in distinct(flatten(var.vpcs.*.subnets[*].*.region)): region][0]
    regions         = {for region in distinct(flatten(var.vpcs.*.subnets[*].*.region)): region => null}
    suffix          = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash   = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

resource "random_shuffle" "gcp_zones" {
    for_each    = data.google_compute_zones.region_availability
    input       = each.value.names
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_compute_project_metadata" "project_metadata" {
    metadata = {
        enable-oslogin  = "TRUE"
        "swp-next-hop${local.suffix}-cwd" = path.cwd
    }
}

resource "google_project_service" "apienable" {
    for_each            = { for api in var.apis: api => null }
    service             = each.key
    disable_on_destroy  = false
    disable_dependent_services  = true
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

module "google-infra-vms" {
    source      = "../modules/google-infra-vms"
    vms         = var.vms
    namesuffix  = local.suffix_nodash
    project-id  = var.project-id
    depends_on = [
      module.google-infra-vpc
    ]
}

#################

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
    name        = "tls-pol${local.suffix}-${each.key}"
    ca_pool     = google_privateca_ca_pool.swp_tlsinsp_ca_subpool[each.key].id
    depends_on = [
        google_privateca_certificate_authority.swp_tlsinsp_sub_ca
    ]
}

resource "google_network_security_gateway_security_policy" "swp_gsp" {
    for_each        = local.regions
    location        = each.key
    name            = "swp-gsp${local.suffix}-${each.key}"
    tls_inspection_policy = google_network_security_tls_inspection_policy.default[each.key].id
}
/*
resource "google_network_security_gateway_security_policy_rule" "swp_allow" {
    for_each                = google_network_security_gateway_security_policy.swp_gsp
    location                = each.value.location
    name                    = "swprule${local.suffix}-${each.key}"
    gateway_security_policy = each.value.name
    enabled                 = true
    priority                = 2000
    session_matcher         = "host().endsWith('com')"
    basic_profile           = "ALLOW"
}
*/

resource "google_network_security_gateway_security_policy_rule" "swp_allow" {
    for_each                = google_network_security_gateway_security_policy.swp_gsp
    location                = each.value.location
    name                    = "swprule${local.suffix}-${each.key}"
    gateway_security_policy = each.value.name
    enabled                 = true
    priority                = 2000
    session_matcher         = "host().endsWith('com')"
    application_matcher     = "request.method == 'GET'"
    tls_inspection_enabled  = false
    basic_profile           = "ALLOW"
}

resource "google_network_services_gateway" "default" {
    for_each                = local.regions
    location                = each.key
    name                    = "gw${local.suffix}-${each.key}"
    type                    = "SECURE_WEB_GATEWAY"
    ports                   = ["80", "443"]
    scope                   = "scope${local.suffix}"
    gateway_security_policy = google_network_security_gateway_security_policy.swp_gsp[each.key].id
    network                 = values(module.google-infra-vpc.vpcs)[0].id
    subnetwork              = values(module.google-infra-vpc.subnets)[0].id
    delete_swg_autogen_router_on_destroy = true
    routing_mode            = "NEXT_HOP_ROUTING_MODE"
}

# Firewall

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

#Route

resource "google_compute_route" "default_to_swp" {
    for_each        = local.regions
    name            = "swp-default${local.suffix}-${each.key}"
    dest_range      = "0.0.0.0/0"
    network         = values(module.google-infra-vpc.vpcs)[0].id
    next_hop_ilb    = google_network_services_gateway.default[each.key].addresses[0]
    tags            = ["swp-${each.key}${local.suffix}"]
    priority        = 1
}