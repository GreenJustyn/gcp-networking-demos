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

provider "google" {
 project     = var.project-id
}

provider "google-beta" {
 project     = var.project-id
}

data "google_compute_image" "debian-image" {
    family  = "debian-12"
    project = "debian-cloud"
}

data "google_compute_zones" "region-availability" {
    for_each    = local.full_region_list
    region      = each.value
}

locals {
    swp_regions         = toset([ for location in var.swp_locations : module.google-infra-vpc.subnets[location.subnet].region ])
    full_region_list    = toset(distinct(flatten([for val in var.vpcs:  val.subnets[*].region])))
}

resource "random_shuffle" "gcp-zones" {
    for_each        = { for region in data.google_compute_zones.region-availability: region.region => region.names }
    input           = [ for zone in each.value : zone ]
}

resource "random_id" "id" {
	  byte_length = 2
}

resource "google_compute_project_metadata" "default" {
  metadata = {
    enable-oslogin  = "TRUE"
    "tf-dir-${random_id.id.hex}" = path.cwd
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
    namesuffix  = random_id.id.hex
}

module "google-infra-firewall" {
    source      = "../modules/google-infra-firewall"
    project-id  = var.project-id
    fw_rules    = var.fw_rules
    namesuffix  = random_id.id.hex
    depends_on = [ module.google-infra-vpc ]
}

resource "google_compute_instance" "testvms" {
    for_each            = { for vm in var.vms : vm.name => vm }
    name                = "${each.key}-${random_id.id.hex}"
    machine_type        = "e2-micro"
    zone                = random_shuffle.gcp-zones[each.value.region].result[0]
    metadata            = {
        startup-script      = templatefile("./debian-client.sh.tftpl", {
            swp-host-ca     = tls_self_signed_cert.secure-web-proxy-self-signed-cert.cert_pem
            swp-tlsinsp-ca  = google_privateca_certificate_authority.swp-tlsinsp-sub-ca[each.value.region].pem_ca_certificates[0]
        })
    }
    tags = ["allow-iap-ssh-${random_id.id.hex}"]
    boot_disk {
        initialize_params {
            image = data.google_compute_image.debian-image.self_link
        }
    }
    network_interface {
        subnetwork  = module.google-infra-vpc.subnets[each.value.subnet].self_link
        network_ip  = google_compute_address.testvm01-reservation[each.key].address
    }
    service_account {
        scopes = ["compute-ro", "storage-ro"]
    }
    depends_on  = [ google_dns_response_policy_rule.googleapis-com ]
}

resource "google_compute_address" "testvm01-reservation" {
    for_each     = { for vm in var.vms : vm.name => vm }
    name         = "res-${each.key}-${random_id.id.hex}"
    subnetwork   = module.google-infra-vpc.subnets[each.value.subnet].self_link
    address_type = "INTERNAL"
    address      = cidrhost(module.google-infra-vpc.subnets[each.value.subnet].ip_cidr_range,100)
    region       = each.value.region
}

#
# DNS settings so clients can access the explicit proxy via hostname instead of IP
#

resource "google_dns_managed_zone" "swp-private-zone" {
    name        = "swp-zone-${random_id.id.hex}"
    dns_name    = "proxy.${var.swp_domainname}."
    description = "Zone for Secure Web Proxy"
    visibility  = "private"
    private_visibility_config {
        networks {
            network_url = module.google-infra-vpc.vpcs["net-swp-demo"].id
        }
    }
}

resource "google_dns_record_set" "swp-proxy-geo" {
    name         = google_dns_managed_zone.swp-private-zone.dns_name
    managed_zone = google_dns_managed_zone.swp-private-zone.name
    type         = "A"
    ttl          = 300
    routing_policy {
        dynamic "geo" {
            for_each    = [ for location in var.swp_locations : location.subnet ]
            content {
                location    = module.google-infra-vpc.subnets[geo.value].region
                rrdatas     = [ cidrhost(module.google-infra-vpc.subnets[geo.value].ip_cidr_range,250) ]
            }
        }
    }
}

#
# Certificate for SWP so that clients can trust the proxy when accessing via HTTPS with the hostname
# We install this certificate on the client as well
#

resource "google_certificate_manager_certificate" "secure-web-proxy-cert" {
    name        = "swp-cert-${random_id.id.hex}"
    for_each    = local.swp_regions
    location    = each.value
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
            echo '${self.private_key_pem}' > swp-privatekey-${random_id.id.hex}.pem
            chmod 400 swp-privatekey-${random_id.id.hex}.pem
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
            echo '${self.cert_pem}' > swp-cert-${random_id.id.hex}.pem
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

resource "google_privateca_ca_pool_iam_binding" "rootca-binding" {
    ca_pool = google_privateca_ca_pool.swp-tlsinsp-rootca-pool.id
    role = "roles/privateca.certificateManager"
    members = [
        "serviceAccount:${google_project_service_identity.swp_tls_sa.email}"
    ]
}

resource "google_privateca_ca_pool_iam_binding" "subordinateca-binding" {
    for_each    = local.swp_regions
    ca_pool     = google_privateca_ca_pool.swp-tlsinsp-ca-subpool[each.value].id
    role = "roles/privateca.certificateManager"
    members = [
        "serviceAccount:${google_project_service_identity.swp_tls_sa.email}"
    ]
}

resource "google_privateca_ca_pool" "swp-tlsinsp-rootca-pool" {
    name = "swp-tlsinsp-rootca-pool-${random_id.id.hex}"
    #Pick the first region in the vpcs variable. Override if necessary.
    location = var.vpcs[0].subnets[0].region
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

resource "google_privateca_certificate_authority" "swp-tlsinsp-root-ca" {
    pool = google_privateca_ca_pool.swp-tlsinsp-rootca-pool.name
    certificate_authority_id = "swp-tlsinsp-root-ca-${random_id.id.hex}"
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

resource "google_privateca_certificate_authority" "swp-tlsinsp-sub-ca" {
    for_each                    = local.swp_regions
    location                    = each.value
    pool                        = google_privateca_ca_pool.swp-tlsinsp-ca-subpool[each.value].name
    certificate_authority_id    = "swp-sub-ca-${each.value}-${random_id.id.hex}"
    type                        = "SUBORDINATE"
    subordinate_config {
        certificate_authority = google_privateca_certificate_authority.swp-tlsinsp-root-ca.name
    }
    config {
        subject_config {
            subject {
                organization    = "SWP Org"
                common_name     = "swp-tlsinsp-sub-ca-${each.value}"
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

resource "google_privateca_ca_pool" "swp-tlsinsp-ca-subpool" {
    for_each    = local.swp_regions
    location    = each.value
    name        = "swp-ca-subpool-${each.value}-${random_id.id.hex}"
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

resource "google_compute_global_address" "psc-ip" {
  for_each      = { for address in var.psc_ips : address.name => address }
  name          = "${each.key}-${random_id.id.hex}"
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
  ip_address            = google_compute_global_address.psc-ip["${each.key}"].id
  load_balancing_scheme = ""
}

resource "google_dns_response_policy" "googleapis-com" {
    provider = google-beta
    response_policy_name = "dns-rp-${random_id.id.hex}"
    networks {
      network_url = module.google-infra-vpc.vpcs["net-swp-demo"].id
    }
}

resource "google_dns_response_policy_rule" "googleapis-com" {
    provider = google-beta
    response_policy = google_dns_response_policy.googleapis-com.response_policy_name
    for_each        = { for rule in var.dns_rp_rules : rule.name => rule }
    rule_name       = "${each.key}-${random_id.id.hex}"
    dns_name        = each.value.dns_name

  local_data {
    local_datas {
      name    = each.value.dns_name
      type    = "A"
      ttl     = 300
      rrdatas = [google_compute_global_address.psc-ip["${each.value.psc-ip}"].address]
    }
  }
}
