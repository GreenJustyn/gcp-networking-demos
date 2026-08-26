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
            source    = "hashicorp/google"
            version   = "= 6.31"
        }
        google-beta = {
            source    = "hashicorp/google-beta"
            version   = "= 6.31"
        }
    }
}


provider "google" {
    project     = var.project-id
    region      = local.region
}

provider "google-beta" {
    project     = var.project-id
    region      = local.region
}

data "google_compute_image" "debian-image" {
    family  = "debian-11"
    project = "debian-cloud"
}

data "google_compute_zones" "region-availability" {
    region      = local.region
}

locals {
    region    = tolist(distinct(flatten([for val in var.vpcs:  val.subnets[*].region])))[0]
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
}

resource "random_shuffle" "gcp-zones" {
    input   = data.google_compute_zones.region-availability.names
}

resource "random_id" "id" {
	  byte_length = 3
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "tf-dir${local.suffix}" = path.cwd
  }
}

resource "google_project_service" "apienable" {
    for_each                    = toset(var.apis)
    service                     = each.value
    disable_on_destroy          = false
    disable_dependent_services  = true
}

module "google-infra-vpc" {
    source      = "../modules/google-infra-vpc"
    project-id  = var.project-id
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    project-id  = var.project-id
    fw_rules    = var.fw_rules
    namesuffix  = local.suffix_nodash
    depends_on = [ module.google-infra-vpc ]
}

resource "google_compute_instance" "testvms" {
    for_each            = { for vm in var.vms : vm.name => vm }
    name                = "${each.key}${local.suffix}"
    machine_type        = "e2-micro"
    zone                = random_shuffle.gcp-zones.result[0]
    metadata            = {
        startup-script      = templatefile("./debian-11-client.sh.tftpl", {
            swp-host-ca     = tls_self_signed_cert.secure-web-proxy-self-signed-cert.cert_pem
            swp-tlsinsp-ca  = google_privateca_certificate_authority.swp_tlsinsp_sub_ca.pem_ca_certificates[0]
        })
    }
    tags = ["allow-iap-ssh${local.suffix}"]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork  = module.google-infra-vpc.subnets[each.value.subnet].self_link
        network_ip  = google_compute_address.ip_reservation[each.key].address
    }
    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }
    depends_on  = [ google_dns_response_policy_rule.googleapis-com ]
}

resource "google_compute_address" "ip_reservation" {
    for_each     = { for vm in var.vms : vm.name => vm }
    name         = "res-${each.key}${local.suffix}"
    subnetwork   = module.google-infra-vpc.subnets[each.value.subnet].self_link
    address_type = "INTERNAL"
    address      = cidrhost(module.google-infra-vpc.subnets[each.value.subnet].ip_cidr_range,100)
    region       = each.value.region
}

#
# DNS settings so clients can access the explicit proxy via hostname instead of IP
#

resource "google_dns_managed_zone" "swp-private-zone" {
    name        = "swp-zone${local.suffix}"
    dns_name    = "proxy.${var.swp_domainname}."
    description = "Zone for Secure Web Proxy"
    visibility  = "private"
    private_visibility_config {
        networks {
            network_url = module.google-infra-vpc.vpcs["net-swp-consumer"].id
        }
    }
}

resource "google_dns_record_set" "swp_proxy_rs" {
    name         = google_dns_managed_zone.swp-private-zone.dns_name
    managed_zone = google_dns_managed_zone.swp-private-zone.name
    type         = "A"
    ttl          = 300
    routing_policy {
        geo {
            location = local.region
            rrdatas  =  [cidrhost(module.google-infra-vpc.subnets["sub-swp-consumer-ase1"].ip_cidr_range,250)]
        }
    }
}

#
# Certificate for SWP so that clients can trust the proxy when accessing via HTTPS with the hostname
# We install this certificate on the client as well
#

resource "google_certificate_manager_certificate" "secure_web_proxy_cert" {
    name        = "swp-cert${local.suffix}"
    location    = local.region
    self_managed {
        pem_certificate = tls_self_signed_cert.secure-web-proxy-self-signed-cert.cert_pem
        pem_private_key = tls_private_key.secure-web-proxy-key.private_key_pem
    }
}

resource "tls_private_key" "secure-web-proxy-key" {
    algorithm = "RSA"
    rsa_bits  = 2048
    /*provisioner "local-exec" {   
        command = <<-EOT
            echo '${self.private_key_pem}' > swp-privatekey${local.suffix}.pem
            chmod 400 swp-privatekey${local.suffix}.pem
        EOT
    }*/
}

resource "tls_self_signed_cert" "secure-web-proxy-self-signed-cert" {
    private_key_pem = tls_private_key.secure-web-proxy-key.private_key_pem
    validity_period_hours = 8760
    subject {
        common_name = trimsuffix(google_dns_managed_zone.swp-private-zone.dns_name, ".")
    }
    dns_names = [ trimsuffix(google_dns_managed_zone.swp-private-zone.dns_name, ".") ]
    set_subject_key_id = true
    set_authority_key_id = true
    is_ca_certificate = true
    allowed_uses = []
    /*provisioner "local-exec" {   
        command = <<-EOT
            echo '${self.cert_pem}' > swp-cert${local.suffix}.pem
        EOT
    }*/
}

#
# Setup for Secure Web Proxy TLS Inspection
#

resource "google_project_service_identity" "swp_tls_sa" {
  provider = google-beta
  service = "networksecurity.googleapis.com"
}

resource "google_privateca_ca_pool_iam_binding" "rootca_binding" {
    ca_pool = google_privateca_ca_pool.swp_tlsinsp_rootca_pool.id
    role = "roles/privateca.certificateManager"
    members = [
        "serviceAccount:${google_project_service_identity.swp_tls_sa.email}"
    ]
}

resource "google_privateca_ca_pool_iam_binding" "subordinateca_binding" {
    ca_pool     = google_privateca_ca_pool.swp_tlsinsp_ca_subpool.id
    role = "roles/privateca.certificateManager"
    members = [
        "serviceAccount:${google_project_service_identity.swp_tls_sa.email}"
    ]
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
    #Pick the first region in the vpcs variable. Override if necessary.
    location = var.vpcs[0].subnets[0].region
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

resource "google_privateca_certificate_authority" "swp_tlsinsp_sub_ca" {
    location                    = local.region
    pool                        = google_privateca_ca_pool.swp_tlsinsp_ca_subpool.name
    certificate_authority_id    = "swp-sub-ca-${local.region}${local.suffix}"
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

resource "google_privateca_ca_pool" "swp_tlsinsp_ca_subpool" {
    location    = local.region
    name        = "swp-ca-subpool-${local.region}${local.suffix}"
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

#
# Internally access Googleapis and apt repo updates so they don't go via SWP / Cloud NAT etc
#

resource "google_compute_global_address" "psc_ip" {
  for_each      = { for address in var.psc_ips : address.name => address }
  name          = "${each.key}${local.suffix}"
  address_type  = "INTERNAL"
  purpose       = "PRIVATE_SERVICE_CONNECT"
  network       = module.google-infra-vpc.vpcs["${each.value.network}"].self_link
  address       = each.value.address
}

resource "google_compute_global_forwarding_rule" "apis-forwarding-rule" {
  for_each              = { for fwdrule in var.psc_ips : fwdrule.name => fwdrule }
  name                  = "${each.key}${random_id.id.hex}"
  target                = "all-apis"
  network               = module.google-infra-vpc.vpcs["${each.value.network}"].self_link
  ip_address            = google_compute_global_address.psc_ip["${each.key}"].id
  load_balancing_scheme = ""
}

resource "google_dns_response_policy" "googleapis-com" {
    response_policy_name = "dns-rp${local.suffix}"
    networks {
      network_url = module.google-infra-vpc.vpcs["net-swp-consumer"].id
    }
}

resource "google_dns_response_policy_rule" "googleapis-com" {
    response_policy = google_dns_response_policy.googleapis-com.response_policy_name
    for_each        = { for rule in var.dns_rp_rules : rule.name => rule }
    rule_name       = "${each.key}${local.suffix}"
    dns_name        = each.value.dns_name
    local_data {
        local_datas {
            name    = each.value.dns_name
            type    = "A"
            ttl     = 300
            rrdatas = [google_compute_global_address.psc_ip["${each.value.psc-ip}"].address]
        }
    }
}

resource "google_network_security_gateway_security_policy" "swp_gsp" {
    provider                = google-beta
    location              = local.region
    name                  = "swp-allow-hosts${local.suffix}"
    tls_inspection_policy = google_network_security_tls_inspection_policy.default.id
}

resource "google_network_security_gateway_security_policy_rule" "swp_allow" {
  location                = local.region
  name                    = "swprule${local.suffix}"
  gateway_security_policy = google_network_security_gateway_security_policy.swp_gsp.name
  enabled                 = true  
  priority                = 123
  session_matcher         = "host().endsWith('com')"
  basic_profile           = "ALLOW"
}

resource "google_network_security_tls_inspection_policy" "default" {
  location    = local.region
  name        = "tls-pol${local.suffix}"
  ca_pool     = google_privateca_ca_pool.swp_tlsinsp_ca_subpool.id
  depends_on = [
    google_privateca_certificate_authority.swp_tlsinsp_sub_ca
  ]
}

resource "google_network_services_gateway" "default" {
    location                = local.region
    name                    = "gw${local.suffix}"
    type                    = "SECURE_WEB_GATEWAY"
    ports                   = ["8443"]
    scope                   = "scope${local.suffix}"
    certificate_urls        = [google_certificate_manager_certificate.secure_web_proxy_cert.id]
    gateway_security_policy = google_network_security_gateway_security_policy.swp_gsp.id
    addresses               = [cidrhost(module.google-infra-vpc.subnets["sub-swp-producer-ase1"].ip_cidr_range,240)]
    network                 = module.google-infra-vpc.vpcs["net-swp-producer"].id
    subnetwork              = module.google-infra-vpc.subnets["sub-swp-producer-ase1"].id
    delete_swg_autogen_router_on_destroy = true
}

#PSC Setup

resource "google_compute_service_attachment" "swp_svc_attachment" {
    provider    = google-beta
    name        = "svc-attach${local.suffix}"
    region      = local.region
    connection_preference    = "ACCEPT_AUTOMATIC"
    enable_proxy_protocol    = false
    nat_subnets              = [module.google-infra-vpc.subnets["sub-producer-psc-ase1"].id]
    target_service           = "https://networkservices.googleapis.com/v1/${google_network_services_gateway.default.id}"
}