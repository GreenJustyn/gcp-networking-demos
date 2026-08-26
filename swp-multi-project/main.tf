resource "google_compute_router" "natrouter" {
  name    = "my-router"
  region  = "australia-southeast1"
  network = module.google-infra-vpc.vpcs["vpc-inside"].id
  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat" {
  name                               = "my-router-nat"
  router                             = google_compute_router.natrouter.name
  region                             = google_compute_router.natrouter.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

locals {
    suffix = try(var.append_rand, true) == true ? "-${random_id.id.hex}" : ""
    suffix_underscore = try(var.append_rand, true) == true ? "_${random_id.id.hex}" : ""
    suffix_nodash = try(var.append_rand, true) == true ? "${random_id.id.hex}" : ""
    project_ids = toset(flatten([var.protected_project_ids, var.unprotected_project_ids]))
    apis_per_project  = flatten([
        for project in toset(flatten([var.protected_project_ids, var.unprotected_project_ids])): [
            for api in var.apis: {
                api_name    = api
                project_id  = project
            }
        ]
    ])
  roles_per_project = flatten([
    for project in local.project_ids: [
      for role in var.sa_project_roles: {
        role = role
        project = project
      }
    ]
  ])
}
terraform {
  required_providers {
    google-beta = {
      source = "hashicorp/google-beta"
      version = "5.21.0"
    }
  }
}

provider "google" { }
provider "google-beta" { }
resource "google_project_service" "apienable" {
    for_each            = { for item in local.apis_per_project: "${item.api_name}_${item.project_id}" => item }
    project             = each.value.project_id
    service             = each.value.api_name
    disable_on_destroy  = false
    disable_dependent_services  = true
}
resource "google_compute_project_metadata" "default" {
  provider  = google.impersonation
  for_each  = toset(flatten([var.protected_project_ids, var.unprotected_project_ids]))
  project   = each.value
  metadata  = {
    enable-oslogin  = "TRUE"
    "tf-created${local.suffix}" = path.cwd
  }
  depends_on = [ google_project_iam_member.sa_roles, google_access_context_manager_service_perimeter.service_perimeter ]
}
resource "random_id" "id" {
	  byte_length = 4
}

resource "random_shuffle" "gcp_zones" {
  for_each        = { for region in data.google_compute_zones.region_availability: region.region => region.names }
  input           = [ for zone in each.value : zone ]
  result_count    = 2
}
data "google_compute_zones" "region_availability" {
  provider      = google.impersonation
  depends_on    = [ google_project_iam_member.sa_roles ]
  for_each      = toset([var.region])
  region        = each.value
}

data "google_compute_image" "debian_image" {
  family  = "debian-11"
  project = "debian-cloud"
}

################
#IAM & Service Account Setup
resource "google_service_account" "vpc_sc_sa" {
    account_id      = "vpc-sc-sa${local.suffix}"
    display_name    = "vpc-sc-service-acct${local.suffix}"
}
data "google_service_account_access_token" "sa" {
    target_service_account  = google_service_account.vpc_sc_sa.email
    lifetime                = "600s"
    scopes                  = [
        "https://www.googleapis.com/auth/cloud-platform",
    ]
}

resource "google_organization_iam_member" "vpc_sc_member" {
  org_id  = var.parent_id
  role    = "roles/accesscontextmanager.policyAdmin"
  member  = "serviceAccount:${google_service_account.vpc_sc_sa.email}"
}

resource "google_project_iam_member" "sa_roles" {
  for_each  = {for item in local.roles_per_project: "${item.role}_${item.project}" => item}
  project   = each.value.project
  role      = each.value.role
  member    = google_service_account.vpc_sc_sa.member
}
provider "google" {
  access_token  = data.google_service_account_access_token.sa.access_token
  alias         = "impersonation"
}
provider "google-beta" {
  access_token  = data.google_service_account_access_token.sa.access_token
  alias         = "impersonation"
}

data "google_client_config" "default" {
}
data "google_project" "protected_projects" {
  for_each = toset(var.protected_project_ids)
  project_id  = each.value
}
data "google_project" "unprotected_projects" {
  for_each = toset(var.unprotected_project_ids)
  project_id  = each.value
}

data "google_projects" "parents" {
  filter = "parent.type:folder AND (${join(" OR ", formatlist("id:%s",var.protected_project_ids))})"
  #distinct(data.google_projects.parents.projects.*.parent.id)
}


resource "google_access_context_manager_access_policy" "access_policy" {
  parent        = "organizations/${var.parent_id}"
  provider      = google.impersonation
  title         = "Access policy ${local.suffix_nodash}"
  depends_on    = [ google_organization_iam_member.vpc_sc_member ]
  scopes        = formatlist("folders/%s",distinct(data.google_projects.parents.projects.*.parent.id))
}

resource "google_access_context_manager_access_level" "access_level" {
    provider    = google.impersonation
    parent      = "accessPolicies/${google_access_context_manager_access_policy.access_policy.id}"
    name        = "accessPolicies/${google_access_context_manager_access_policy.access_policy.id}/accessLevels/policy${local.suffix_nodash}"
    title       = "allow service accounts into perimeter"
    basic {
        conditions {
            members = [
                google_service_account.vpc_sc_sa.member
            ]
        }
    }
}

resource "google_access_context_manager_service_perimeter" "service_perimeter" {
    provider    = google.impersonation
    parent      = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}"
    name        = "accessPolicies/${google_access_context_manager_access_policy.access_policy.name}/servicePerimeters/perim${local.suffix_nodash}"
    title       = "Restrict APIs"
    status {
        restricted_services = var.restricted_services
        resources           = formatlist("projects/%s",values(data.google_project.protected_projects)[*].number)
        access_levels       = [ google_access_context_manager_access_level.access_level.name ]
    }
}

module "google-infra-vpc" {
  providers     = {
    google      = google.impersonation
  }
    source      = "../modules/google-infra-vpc"
    vpcs        = var.vpcs
    namesuffix  = local.suffix_nodash
  depends_on = [ google_project_iam_member.sa_roles, google_access_context_manager_service_perimeter.service_perimeter ]
}

module "google-infra-firewall" {
  providers     = {
    google      = google.impersonation
  }
  source      = "../modules/google-infra-firewall"
  fw_rules    = var.fw_rules
  namesuffix  = local.suffix_nodash
  depends_on = [ module.google-infra-vpc, google_project_iam_member.sa_roles, google_access_context_manager_service_perimeter.service_perimeter ]
}

resource "google_compute_instance" "testvms" {
  provider            = google.impersonation
  for_each            = { for vm in var.vms : vm.name => vm }
  project             = each.value.project
  name                = "${each.key}${local.suffix}"
  machine_type        = each.value.size
  zone                = random_shuffle.gcp_zones[each.value.region].result[0]
  metadata            = {
      startup-script      = templatefile("./debian-11-client.sh.tftpl", {
          swp-host-ca     = tls_self_signed_cert.swp_self_signed_cert.cert_pem
          swp-tlsinsp-ca  = google_privateca_certificate_authority.swp_tlsinsp_sub_ca.pem_ca_certificates[0]
          swp-fqdn        = "https://${trimsuffix(values(google_dns_record_set.swp_proxy_record_set)[0].name, ".")}:8443"
      })
  }
  tags = [ ]
  boot_disk {
      initialize_params {
          image = data.google_compute_image.debian_image.self_link
      }
  }
  network_interface {
      subnetwork  = module.google-infra-vpc.subnets[each.value.subnet].self_link
      network_ip  = google_compute_address.vm_reservation[each.key].address
  }
  service_account {
      scopes = ["compute-ro", "storage-ro"]
  }
  depends_on  = [
    google_dns_record_set.swp_proxy_record_set,
    google_project_iam_member.sa_roles,
    google_access_context_manager_service_perimeter.service_perimeter
  ]
}
resource "google_compute_address" "vm_reservation" {
  provider      = google.impersonation
  depends_on    = [ google_project_iam_member.sa_roles, google_access_context_manager_service_perimeter.service_perimeter ]
  for_each      = { for vm in var.vms : vm.name => vm }
  project       = each.value.project
  name          = "res-${each.key}${local.suffix}"
  subnetwork    = module.google-infra-vpc.subnets[each.value.subnet].self_link
  address_type  = "INTERNAL"
  address       = cidrhost(module.google-infra-vpc.subnets[each.value.subnet].ip_cidr_range,10)
  region        = each.value.region
}

resource "google_tags_tag_key" "tag_key" {
  for_each    = toset(var.unprotected_project_ids)
  provider    = google.impersonation
  description = ""
  parent      = "projects/${each.value}"
  purpose     = "GCE_FIREWALL"
  short_name  = "tagkey${each.value}${local.suffix}"
  purpose_data = {
    network = "${each.value}/${values(module.google-infra-vpc.vpcs)[index(values(module.google-infra-vpc.vpcs).*.project,each.value)].name}"
  }
  depends_on = [ google_project_iam_member.sa_roles, google_access_context_manager_service_perimeter.service_perimeter ]
}

resource "google_tags_tag_value" "tag_value" {
  for_each    = toset(var.unprotected_project_ids)
  provider      = google.impersonation
  description = "For valuename resources."
  parent      = "tagKeys/${google_tags_tag_key.tag_key[each.value].name}"
  short_name  = "${each.value}${local.suffix}"
}

resource "google_tags_tag_key_iam_member" "tag_member" {
  provider      = google.impersonation
  for_each      = toset(var.unprotected_project_ids)
  tag_key       = google_tags_tag_key.tag_key[each.value].name
  role          = "roles/resourcemanager.tagUser"
  member        = "serviceAccount:${google_service_account.vpc_sc_sa.email}"
}

resource "google_tags_location_tag_binding" "gce_binding" {
  provider      = google.impersonation
  parent        = "//compute.googleapis.com/projects/${one(values(data.google_project.unprotected_projects)[*].number)}/zones/${google_compute_instance.testvms["testvm-outside"].zone}/instances/${google_compute_instance.testvms["testvm-outside"].instance_id}"
  tag_value     = "tagValues/${google_tags_tag_value.tag_value[google_compute_instance.testvms["testvm-outside"].project].name}"
  location      = google_compute_instance.testvms["testvm-outside"].zone
}

#
# Secure Web Proxy configuration
#
/*
resource "google_network_security_gateway_security_policy" "swp_gsp" {
  #provider              = google-beta.impersonation
  provider              = google-beta
  project               = one(var.protected_project_ids)
  location              = var.region
  name                  = "swp-allow-hosts${local.suffix}"
  tls_inspection_policy = google_network_security_tls_inspection_policy.default.id
  #depends_on            = [ google_project_iam_member.sa_roles ]
}

resource "google_network_security_gateway_security_policy_rule" "swp_allow" {
  location                = var.region
  name                    = "swprule${local.suffix}"
  gateway_security_policy = google_network_security_gateway_security_policy.swp_gsp.name
  enabled                 = true  
  priority                = 123
  session_matcher         = "host().endsWith('com')"
  basic_profile           = "ALLOW"
}

resource "google_network_security_tls_inspection_policy" "default" {
  #provider    = google-beta.impersonation
  provider    = google-beta
  location    = var.region
  name        = "tls-pol${local.suffix}"
  ca_pool     = google_privateca_ca_pool.swp_tlsinsp_ca_subpool.id
  depends_on = [
    google_privateca_certificate_authority.swp_tlsinsp_sub_ca,
    google_project_iam_member.sa_roles
  ]
}

resource "google_network_services_gateway" "default" {
  location                = var.region
  name                    = "gw${local.suffix}"
  type                    = "SECURE_WEB_GATEWAY"
  ports                   = ["8443"]
  scope                   = "scope${local.suffix}"
  certificate_urls        = [google_certificate_manager_certificate.swp_cert.id]
  gateway_security_policy = google_network_security_gateway_security_policy.swp_gsp.id
  addresses               = [cidrhost(module.google-infra-vpc.subnets["inside-ase1"].ip_cidr_range,100)]
  network                 = module.google-infra-vpc.vpcs["vpc-inside"].id
  subnetwork              = module.google-infra-vpc.subnets["inside-ase1"].id
  delete_swg_autogen_router_on_destroy = true
}

resource "google_project_service_identity" "swp_tls_sa" {
  provider  = google-beta.impersonation
  service   = "networksecurity.googleapis.com"
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
    location = var.region
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
    location = var.region
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
    location                    = var.region
    pool                        = google_privateca_ca_pool.swp_tlsinsp_ca_subpool.name
    certificate_authority_id    = "swp-sub-ca-${var.region}${local.suffix}"
    type                        = "SUBORDINATE"
    subordinate_config {
        certificate_authority = google_privateca_certificate_authority.swp_tlsinsp_root_ca.name
    }
    config {
        subject_config {
            subject {
                organization    = "SWP Org"
                common_name     = "swp-tlsinsp-sub-ca-${var.region}"
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
    location    = var.region
    name        = "swp-ca-${var.region}${local.suffix}"
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

resource "google_dns_managed_zone" "swp_private_zone" {
  for_each    = module.google-infra-vpc.vpcs
  project     = each.value.project
  name        = "swp-zone${local.suffix}"
  dns_name    = "swp.internal."
  description = "Zone for Secure Web Proxy"
  visibility  = "private"
  private_visibility_config {
      networks {
          network_url = each.value.id
      }
  }
}

resource "google_dns_record_set" "swp_proxy_record_set" {
  for_each      = google_dns_managed_zone.swp_private_zone
  project       = each.value.project
  name          = "proxy.${each.value.dns_name}"
  managed_zone  = each.value.name
  type          = "A"
  ttl           = 300
  rrdatas       = [ one(google_network_services_gateway.default.addresses) ]
}

#
# Certificate for SWP so that clients can trust the proxy when accessing via HTTPS with the hostname
# We install this certificate on the client as well
#

resource "google_certificate_manager_certificate" "swp_cert" {
    name        = "swp-cert${local.suffix}"
    location    = var.region
    self_managed {
        pem_certificate = tls_self_signed_cert.swp_self_signed_cert.cert_pem
        pem_private_key = tls_private_key.swp_key.private_key_pem
    }
}

resource "tls_private_key" "swp_key" {
    algorithm = "RSA"
    rsa_bits  = 2048
}

resource "tls_self_signed_cert" "swp_self_signed_cert" {
    private_key_pem = tls_private_key.swp_key.private_key_pem
    validity_period_hours = 8760
    subject {
        common_name = trimsuffix(values(google_dns_managed_zone.swp_private_zone)[0].dns_name, ".")
    }
    dns_names = [ trimsuffix(values(google_dns_managed_zone.swp_private_zone)[0].dns_name, ".") ]
    set_subject_key_id = true
    set_authority_key_id = true
    is_ca_certificate = true
    allowed_uses = []
}

resource "google_compute_network_peering" "peerings-a-b" {
    for_each                = { for peer in var.peerings : format("%s-%s",peer.network_a,peer.network_b) => peer }
    name                    = "${each.key}${local.suffix}"
    network                 = module.google-infra-vpc.vpcs["${each.value.network_a}"].self_link
    peer_network            = module.google-infra-vpc.vpcs["${each.value.network_b}"].self_link
    export_custom_routes    = true
    depends_on              = [  ]
}

resource "google_compute_network_peering" "peerings-b-a" {
    for_each                = { for peer in var.peerings : format("%s-%s",peer.network_b,peer.network_a) => peer }
    name                    = "${each.key}${local.suffix}"
    network                 = module.google-infra-vpc.vpcs["${each.value.network_b}"].self_link
    peer_network            = module.google-infra-vpc.vpcs["${each.value.network_a}"].self_link
    import_custom_routes    = true
    depends_on              = [ ]
}